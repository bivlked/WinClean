#Requires -Version 5.1

<#
.SYNOPSIS
    WinClean one-command installer: install/update + elevated desktop shortcut
.DESCRIPTION
    Install (or update) the latest WinClean release with a single command from an
    elevated terminal:

        irm https://raw.githubusercontent.com/bivlked/WinClean/main/install.ps1 | iex

    What it does:
      1. Downloads the latest WinClean.ps1 release (SHA256-verified when the
         release publishes a hash) into %ProgramFiles%\WinClean.
         The admin-protected location is deliberate: the desktop shortcut launches
         the script elevated, so the file must not be writable by non-elevated
         processes. Re-run the same command anytime to update.
      2. Creates/refreshes a "WinClean" desktop shortcut targeting PowerShell 7
         with the "Run as administrator" flag set on the .lnk.

    Requirements: PowerShell 7.1+ installed at %ProgramFiles%\PowerShell\7 and an
    elevated terminal (installation writes to Program Files).
.NOTES
    Project: https://github.com/bivlked/WinClean
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = 'bivlked/WinClean'

# 1. Administrator (required: install target is %ProgramFiles%)
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "The installer must run as Administrator (it writes to Program Files)." -ForegroundColor Red
    Write-Host "Open an elevated terminal (Win+X -> Terminal (Admin)) and re-run the command." -ForegroundColor Yellow
    return
}

# 2. PowerShell 7 at the canonical location (the shortcut target).
#    Deliberately NOT resolved from PATH: the shortcut launches elevated.
$pwshPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path $pwshPath)) {
    Write-Host "PowerShell 7 not found at $pwshPath - WinClean requires it." -ForegroundColor Red
    Write-Host "Install it with:  winget install --id Microsoft.PowerShell" -ForegroundColor Yellow
    Write-Host "Then re-run this installer." -ForegroundColor Yellow
    return
}

# 3. Resolve the latest release (fail closed - no fallback to a mutable branch)
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 15
} catch {
    Write-Host "Could not query the latest WinClean release: $_" -ForegroundColor Red
    Write-Host "Check your connection and try again, or download manually: https://github.com/$repo/releases" -ForegroundColor Yellow
    return
}

$scriptAsset = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1' } | Select-Object -First 1
$hashAsset = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1.sha256' } | Select-Object -First 1
$scriptUrl = if ($scriptAsset) {
    $scriptAsset.browser_download_url
} else {
    "https://raw.githubusercontent.com/$repo/$($release.tag_name)/WinClean.ps1"
}

# 4. Download and verify, then move into place
$installDir = Join-Path $env:ProgramFiles 'WinClean'
$scriptPath = Join-Path $installDir 'WinClean.ps1'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

$previousVersion = $null
if (Test-Path $scriptPath) {
    $versionLine = Select-String -Path $scriptPath -Pattern '^\.VERSION\s+([\d.]+)' | Select-Object -First 1
    if ($versionLine) { $previousVersion = $versionLine.Matches[0].Groups[1].Value }
}

Write-Host "Downloading WinClean $($release.tag_name)..." -ForegroundColor Cyan
$tempFile = Join-Path $installDir 'WinClean.ps1.download'
Invoke-WebRequest -Uri $scriptUrl -OutFile $tempFile -TimeoutSec 60

if ($hashAsset) {
    $expected = ((Invoke-RestMethod -Uri $hashAsset.browser_download_url -TimeoutSec 30) -split '\s+')[0].Trim()
    $actual = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash
    if ($actual -notlike $expected) {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Write-Host "SHA256 mismatch - the downloaded file does not match the published hash. Aborting." -ForegroundColor Red
        return
    }
    Write-Host "SHA256 verified." -ForegroundColor DarkGray
}

$head = Get-Content $tempFile -TotalCount 5 -ErrorAction Stop
if (-not ($head -join "`n").Contains('PSScriptInfo')) {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    Write-Host "Downloaded file does not look like WinClean.ps1 - aborting." -ForegroundColor Red
    return
}
Move-Item -Path $tempFile -Destination $scriptPath -Force
Unblock-File -Path $scriptPath -ErrorAction SilentlyContinue

$newVersionLine = Select-String -Path $scriptPath -Pattern '^\.VERSION\s+([\d.]+)' | Select-Object -First 1
$newVersion = if ($newVersionLine) { $newVersionLine.Matches[0].Groups[1].Value } else { '?' }

# 5. Desktop shortcut with the "Run as administrator" flag.
#    Shortcut failure must not fail the install (e.g. profiles without a
#    Desktop folder, service contexts) - the script itself is already in place.
$lnkPath = $null
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { throw "Desktop folder is not available in this session" }
    if (-not (Test-Path $desktop)) { New-Item -ItemType Directory -Path $desktop -Force | Out-Null }
    $lnkPath = Join-Path $desktop 'WinClean.lnk'

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $pwshPath
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = '%SystemRoot%\System32\SHELL32.dll,153'
    $shortcut.Description = 'WinClean - Windows 11 maintenance (runs elevated)'
    $shortcut.Save()

    # Set the RunAsAdministrator flag (byte 0x15, bit 0x20 of the .lnk header)
    $lnkBytes = [System.IO.File]::ReadAllBytes($lnkPath)
    $lnkBytes[0x15] = $lnkBytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($lnkPath, $lnkBytes)
} catch {
    $lnkPath = $null
    Write-Host "Warning: could not create the desktop shortcut: $_" -ForegroundColor Yellow
    Write-Host "You can run WinClean from an elevated terminal: & `"$scriptPath`"" -ForegroundColor Gray
}

# 6. Summary
Write-Host ""
if ($previousVersion -and $previousVersion -ne $newVersion) {
    Write-Host "WinClean updated: v$previousVersion -> v$newVersion" -ForegroundColor Green
} elseif ($previousVersion) {
    Write-Host "WinClean reinstalled (v$newVersion)" -ForegroundColor Green
} else {
    Write-Host "WinClean v$newVersion installed" -ForegroundColor Green
}
Write-Host "  Location: $scriptPath" -ForegroundColor DarkGray
if ($lnkPath) {
    Write-Host "  Shortcut: $lnkPath (launches elevated)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Double-click the WinClean shortcut on your desktop to run maintenance." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Run WinClean from an elevated PowerShell 7: & `"$scriptPath`"" -ForegroundColor Cyan
}
