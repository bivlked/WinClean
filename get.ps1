#Requires -Version 5.1

<#
.SYNOPSIS
    WinClean one-command bootstrap: download the latest release and run it
.DESCRIPTION
    Run WinClean on any machine with a single command (PowerShell 7.1+, elevated):

        irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex

    With parameters for WinClean:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1))) -ReportOnly

    The script checks prerequisites (PowerShell 7.1+, Administrator), downloads
    WinClean.ps1 from the latest GitHub Release (verifying its SHA256 when the
    release publishes one) and runs it. Fails closed: no fallback to mutable
    branches. To install permanently with a desktop shortcut use install.ps1.
.NOTES
    Project: https://github.com/bivlked/WinClean
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$WinCleanArgs
)

$ErrorActionPreference = 'Stop'
$repo = 'bivlked/WinClean'

# 1. PowerShell 7.1+
if ($PSVersionTable.PSVersion -lt [version]'7.1') {
    Write-Host "WinClean requires PowerShell 7.1+ (current: $($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host "Install it with:  winget install --id Microsoft.PowerShell" -ForegroundColor Yellow
    Write-Host "Then re-run this command from pwsh." -ForegroundColor Yellow
    return
}

# 2. Administrator
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WinClean must run as Administrator." -ForegroundColor Red
    Write-Host "Open an elevated PowerShell 7 (Win+X -> Terminal (Admin)) and re-run the command." -ForegroundColor Yellow
    return
}

# 3. Resolve the latest release. Fail closed: an elevated bootstrap must not
#    silently fall back to a mutable branch.
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
    # Release without attached assets: use the file as of the release tag
    "https://raw.githubusercontent.com/$repo/$($release.tag_name)/WinClean.ps1"
}

# 4. Download into a unique per-run directory (avoids a predictable-path race)
$destDir = Join-Path $env:TEMP ("WinClean-" + [guid]::NewGuid().ToString('N'))
$destPath = Join-Path $destDir 'WinClean.ps1'
New-Item -ItemType Directory -Path $destDir -Force | Out-Null

Write-Host "Downloading WinClean $($release.tag_name)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $scriptUrl -OutFile $destPath -TimeoutSec 60

# 5. Verify: SHA256 against the published hash asset when available,
#    plus a basic sanity check of the file itself
if ($hashAsset) {
    $expected = ((Invoke-RestMethod -Uri $hashAsset.browser_download_url -TimeoutSec 30) -split '\s+')[0].Trim()
    $actual = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash
    if ($actual -notlike $expected) {
        Write-Host "SHA256 mismatch - the downloaded file does not match the published hash. Aborting." -ForegroundColor Red
        Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Write-Host "SHA256 verified." -ForegroundColor DarkGray
}

$head = Get-Content $destPath -TotalCount 5 -ErrorAction Stop
if (-not ($head -join "`n").Contains('PSScriptInfo')) {
    Write-Host "Downloaded file does not look like WinClean.ps1 - aborting." -ForegroundColor Red
    Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}
Unblock-File -Path $destPath -ErrorAction SilentlyContinue

# 6. Run
# NOTE: splatting a plain STRING ARRAY does not bind parameter names - the
# tokens would be passed positionally ("-ReportOnly" would become a VALUE of
# the first positional parameter). Parse the tokens into a hashtable instead.
$splat = @{}
for ($i = 0; $i -lt $WinCleanArgs.Count; $i++) {
    $token = $WinCleanArgs[$i]
    if ($token -like '-*') {
        $name = $token.TrimStart('-')
        if (($i + 1) -lt $WinCleanArgs.Count -and $WinCleanArgs[$i + 1] -notlike '-*') {
            $splat[$name] = $WinCleanArgs[++$i]
        } else {
            $splat[$name] = $true
        }
    } else {
        Write-Host "Unrecognized argument: '$token' (expected -Parameter [value]). Aborting." -ForegroundColor Red
        Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
}

Write-Host "Starting WinClean..." -ForegroundColor Cyan
Write-Host ""
try {
    & $destPath @splat
} finally {
    Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
}
