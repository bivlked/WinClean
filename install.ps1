#Requires -Version 5.1

<#
.SYNOPSIS
    WinClean installer: install or update locally and create an elevated desktop shortcut
.DESCRIPTION
    Install WinClean with a single command from an elevated terminal:

        irm https://raw.githubusercontent.com/bivlked/WinClean/main/install.ps1 | iex

    Downloads the latest GitHub Release into %ProgramFiles%\WinClean, verifies its
    SHA256 against the published hash, and creates a desktop shortcut that runs the
    script elevated. Re-running updates an existing installation in place.

    Fails closed. A release that does not publish BOTH WinClean.ps1 and
    WinClean.ps1.sha256 is refused, and there is no fallback to a branch or a tag.

    Requirements: PowerShell 7.1+ installed at %ProgramFiles%\PowerShell\7 and an
    elevated terminal (installation writes to Program Files).
.NOTES
    Project: https://github.com/bivlked/WinClean
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = 'bivlked/WinClean'

# Windows PowerShell 5.1 defaults to TLS 1.0/1.1 on older builds, which api.github.com
# refuses. The installer must work from whatever shell the user has before PS7 exists.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true
    $PSDefaultParameterValues['Invoke-RestMethod:UseBasicParsing'] = $true
}

function Stop-Install {
    <# Reports a failure in a way automation can detect, without killing an `iex` host session #>
    param([string]$Message, [string]$Hint, [int]$Code = 1)
    Write-Host $Message -ForegroundColor Red
    if ($Hint) { Write-Host $Hint -ForegroundColor Yellow }
    Write-Error $Message -ErrorAction Continue
    $global:LASTEXITCODE = $Code
}

function Assert-GitHubUri {
    param([string]$Uri)
    $parsed = [uri]$Uri
    if ($parsed.Scheme -ne 'https' -or
        $parsed.Host -notmatch '(^|\.)(github\.com|githubusercontent\.com)$') {
        throw "Refusing to download from an unexpected host: $($parsed.Host)"
    }
    return $Uri
}

# 1. Administrator (required: install target is %ProgramFiles%)
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Install "The installer must run as Administrator (it writes to Program Files)." `
                 "Open an elevated terminal (Win+X -> Terminal (Admin)) and re-run the command."
    return
}

# 2. PowerShell 7 at the canonical location (the shortcut target).
#    Deliberately NOT resolved from PATH, and NOT from $env:ProgramFiles: user
#    environment variables override machine ones and are writable by a non-admin
#    process, which would let it point an elevated shortcut at its own binary.
$programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$pwshPath = Join-Path $programFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path $pwshPath)) {
    Stop-Install "PowerShell 7 not found at $pwshPath - WinClean requires it." `
                 "Install it with:  winget install --id Microsoft.PowerShell"
    return
}

$pwshVersion = try { [version](((Get-Item $pwshPath).VersionInfo.ProductVersion -split '-')[0]) } catch { $null }
if ($pwshVersion -and $pwshVersion -lt [version]'7.1') {
    Stop-Install "PowerShell $pwshVersion found at $pwshPath, but WinClean requires 7.1+." `
                 "Update it with:  winget upgrade --id Microsoft.PowerShell"
    return
}

# 3. Resolve the latest release
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 15
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    $hint = if ($status -in 403, 429) {
        "GitHub API rate limit reached for your address. Wait an hour or download manually: https://github.com/$repo/releases"
    } else {
        "Check your connection and try again, or download manually: https://github.com/$repo/releases"
    }
    Stop-Install "Could not query the latest WinClean release: $_" $hint
    return
}

$scriptAsset = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1' } | Select-Object -First 1
$hashAsset   = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1.sha256' } | Select-Object -First 1

# Both assets are mandatory - see get.ps1 for the reasoning
if (-not $scriptAsset -or -not $hashAsset) {
    Stop-Install "Release $($release.tag_name) does not publish both WinClean.ps1 and WinClean.ps1.sha256." `
                 "Refusing to install unverified code. Download and check manually: https://github.com/$repo/releases"
    return
}

# 4. Download and verify, then move into place
$installDir = Join-Path $programFiles 'WinClean'
$scriptPath = Join-Path $installDir 'WinClean.ps1'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

$previousVersion = $null
if (Test-Path $scriptPath) {
    $versionLine = Select-String -Path $scriptPath -Pattern '^\.VERSION\s+([\d.]+)' | Select-Object -First 1
    if ($versionLine) { $previousVersion = $versionLine.Matches[0].Groups[1].Value }
}

$tempFile = Join-Path $installDir 'WinClean.ps1.download'
$hashFile = "$tempFile.sha256"
try {
    Write-Host "Downloading WinClean $($release.tag_name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri (Assert-GitHubUri $scriptAsset.browser_download_url) `
                      -OutFile $tempFile -TimeoutSec 60 -MaximumRedirection 3
    Invoke-WebRequest -Uri (Assert-GitHubUri $hashAsset.browser_download_url) `
                      -OutFile $hashFile -TimeoutSec 30 -MaximumRedirection 3

    $expected = ((Get-Content -LiteralPath $hashFile -Raw) -split '\s+')[0].Trim()
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') {
        Stop-Install "The published hash is not a valid SHA256 value. Aborting."
        return
    }

    $actual = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash
    # Literal comparison: -like would treat the published hash as a wildcard pattern
    if (-not [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Install "SHA256 mismatch - the downloaded file does not match the published hash. Aborting."
        return
    }
    Write-Host "SHA256 verified." -ForegroundColor DarkGray

    # The hash proves the two assets agree with each other, not that the asset is
    # WinClean. A packaging mistake in the release would otherwise replace a working
    # installation with arbitrary content.
    $head = Get-Content -LiteralPath $tempFile -TotalCount 5 -ErrorAction Stop
    if (-not ($head -join "`n").Contains('PSScriptInfo')) {
        Stop-Install "The downloaded asset does not look like WinClean.ps1 - keeping the existing installation."
        return
    }

    try {
        Move-Item -LiteralPath $tempFile -Destination $scriptPath -Force
    } catch {
        Stop-Install "Could not replace $scriptPath : $_" `
                     "Close any running WinClean window and re-run the installer."
        return
    }
} finally {
    Remove-Item $tempFile, $hashFile -Force -ErrorAction SilentlyContinue
}

$newVersion = '?'
$versionLine = Select-String -Path $scriptPath -Pattern '^\.VERSION\s+([\d.]+)' | Select-Object -First 1
if ($versionLine) { $newVersion = $versionLine.Matches[0].Groups[1].Value }

if ($previousVersion) {
    Write-Host "Updated: $previousVersion -> $newVersion" -ForegroundColor Green
} else {
    Write-Host "Installed version $newVersion to $installDir" -ForegroundColor Green
}

# 5. Desktop shortcut that runs elevated.
#    Missing Desktop is not fatal: under SYSTEM or a redirected profile there may be
#    none, and the installation itself is already complete and usable.
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw "no Desktop folder for the current user" }

    # An argument string is built by interpolation, so a quote in the path would be
    # an injection into the command line of an elevated shortcut
    if ($scriptPath -match '["`$]') { throw "unsafe characters in the install path: $scriptPath" }

    $lnkPath = Join-Path $desktop 'WinClean.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $pwshPath
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = "$pwshPath,0"
    $shortcut.Description = "WinClean - Windows 11 maintenance"
    $shortcut.Save()

    # Set the "Run as administrator" flag (bit 0x20 of byte 0x15 in the .lnk header)
    $lnkBytes = [System.IO.File]::ReadAllBytes($lnkPath)
    $lnkBytes[0x15] = $lnkBytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($lnkPath, $lnkBytes)

    Write-Host "Desktop shortcut created (runs elevated): $lnkPath" -ForegroundColor Green
} catch {
    Write-Host "Shortcut not created ($_)." -ForegroundColor Yellow
    Write-Host "WinClean is installed and can be run directly:" -ForegroundColor Yellow
    Write-Host "  & '$pwshPath' -NoProfile -File '$scriptPath'" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Run it from the shortcut, or:" -ForegroundColor Cyan
Write-Host "  & '$scriptPath' -ReportOnly     # preview without changes" -ForegroundColor Gray
Write-Host "  & '$scriptPath'                 # full maintenance" -ForegroundColor Gray
Write-Host ""
