#Requires -Version 7.1

<#
.SYNOPSIS
    Runs a WinClean test cycle on the Proxmox stand VM
.DESCRIPTION
    Full cycle: rollback to the baseline snapshot -> boot -> deliver the script ->
    run it -> collect console output, log and result JSON -> assert -> shutdown.

    Assertions: exit code, ErrorsCount = 0 in result JSON, no [ERROR] lines,
    log file contains pre-cleanup entries, console box geometry is intact.
    Artifacts are stored under tools/proxmox/results/<timestamp>/.
.PARAMETER Mode
    Report (default): -ReportOnly -SkipUpdates, safe and fast (~2 min in guest).
    Full: real cleanup WITHOUT updates (-SkipUpdates; updates need Windows
    licensing/network time and are better exercised manually).
    FullWithUpdates: everything enabled - the complete production scenario (slow).
.PARAMETER Source
    local (default): upload the working-tree WinClean.ps1 (tests unpushed changes).
    main / release: the guest downloads from GitHub (also validates get.ps1 path).
.PARAMETER KeepRunning
    Leave the VM running after the test (for interactive debugging via console)
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Full', 'FullWithUpdates')]
    [string]$Mode = 'Report',

    [ValidateSet('local', 'main', 'release')]
    [string]$Source = 'local',

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'stand.config.json'),
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StandCommon.ps1')
. (Join-Path $PSScriptRoot '..' 'BoxGeometry.ps1')

$cfg = Get-StandConfig -ConfigPath $ConfigPath
$vmid = $cfg.StandVmId
$resultsDir = Join-Path $PSScriptRoot 'results' (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

$guestScript = 'C:\Windows\Temp\WinClean.ps1'
$guestJson = 'C:\Windows\Temp\winclean-result.json'
$guestLog = 'C:\Windows\Temp\winclean-run.log'

Write-Host "WinClean stand test: Mode=$Mode Source=$Source VM=$vmid" -ForegroundColor Cyan

# 1. Rollback to baseline and boot
Write-Host "[1/6] Rollback to '$($cfg.SnapshotName)' and boot..." -ForegroundColor Cyan
$null = Invoke-Pve -Config $cfg -Command "qm stop $vmid --skiplock 1" -AllowFail
$null = Invoke-Pve -Config $cfg -Command "qm rollback $vmid $($cfg.SnapshotName)"
$null = Invoke-Pve -Config $cfg -Command "qm start $vmid"
$null = Wait-GuestAgent -Config $cfg -TimeoutSeconds 420
# Give the OS a moment to settle after boot (services, profile)
Start-Sleep -Seconds 20

# 2. Deliver the script
Write-Host "[2/6] Delivering WinClean.ps1 ($Source)..." -ForegroundColor Cyan
switch ($Source) {
    'local' {
        $localScript = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'WinClean.ps1')).Path
        Copy-FileToGuest -Config $cfg -LocalPath $localScript -GuestPath $guestScript
    }
    default {
        $tagExpr = if ($Source -eq 'main') {
            "'main'"
        } else {
            "(Invoke-RestMethod 'https://api.github.com/repos/bivlked/WinClean/releases/latest').tag_name"
        }
        $dl = Invoke-GuestCommand -Config $cfg -TimeoutSeconds 180 -UsePwsh -Script @"
`$tag = $tagExpr
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/`$tag/WinClean.ps1" -OutFile '$guestScript' -TimeoutSec 120
(Get-Item '$guestScript').Length
"@
        if ($dl.ExitCode -ne 0) { throw "Download in guest failed: $($dl.Error)" }
    }
}

# 3. Run WinClean
$modeArgs = switch ($Mode) {
    'Report'          { "-ReportOnly -SkipUpdates" }
    'Full'            { "-SkipUpdates" }
    'FullWithUpdates' { "" }
}
$timeout = switch ($Mode) {
    'Report'          { 1800 }
    'Full'            { 3600 }
    'FullWithUpdates' { 7200 }
}

Write-Host "[3/6] Running WinClean ($Mode, timeout ${timeout}s)..." -ForegroundColor Cyan
# Run the script as a CHILD pwsh with stdout redirected to a file in the guest:
# in-process invocation would turn Write-Host into InformationRecords (breaking
# -NoNewline lines) and pipe non-ASCII output through lossy console codepages.
# The console file is then fetched via base64 (see Get-GuestFile).
$guestConsole = 'C:\Windows\Temp\winclean-console.txt'
$run = Invoke-GuestCommand -Config $cfg -TimeoutSeconds $timeout -UsePwsh -Script @"
`$p = Start-Process -FilePath 'C:\Program Files\PowerShell\7\pwsh.exe' ``
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '$guestScript'$(if ($modeArgs) { ", '" + (($modeArgs -split ' ') -join "', '") + "'" }), '-ResultJsonPath', '$guestJson', '-LogPath', '$guestLog' ``
    -RedirectStandardOutput '$guestConsole' -PassThru -Wait -NoNewWindow
Write-Output "CHILD_EXIT=`$(`$p.ExitCode)"
"@

$childExit = if ($run.Output -match 'CHILD_EXIT=(-?\d+)') { [int]$Matches[1] } else { $null }
$consoleOut = Get-GuestFile -Config $cfg -GuestPath $guestConsole
if (-not $consoleOut) { $consoleOut = '' }
Set-Content -Path (Join-Path $resultsDir 'console-output.txt') -Value $consoleOut -Encoding UTF8

# 4. Collect artifacts
Write-Host "[4/6] Collecting artifacts..." -ForegroundColor Cyan
$jsonRaw = Get-GuestFile -Config $cfg -GuestPath $guestJson
$logRaw = Get-GuestFile -Config $cfg -GuestPath $guestLog
if ($jsonRaw) { Set-Content -Path (Join-Path $resultsDir 'result.json') -Value $jsonRaw -Encoding UTF8 }
if ($logRaw) { Set-Content -Path (Join-Path $resultsDir 'winclean-run.log') -Value $logRaw -Encoding UTF8 }

# 5. Assertions
Write-Host "[5/6] Asserting..." -ForegroundColor Cyan
$failures = @()

if ($run.ExitCode -ne 0) { $failures += "Guest wrapper exit code: $($run.ExitCode)" }
if ($null -eq $childExit) {
    $failures += "Child pwsh exit code was not reported (wrapper output: '$($run.Output)')"
} elseif ($childExit -ne 0) {
    $failures += "WinClean exit code: $childExit"
}

if (-not $jsonRaw) {
    $failures += "Result JSON was not produced"
} else {
    $result = $jsonRaw | ConvertFrom-Json
    if ($result.ErrorsCount -ne 0) { $failures += "ErrorsCount = $($result.ErrorsCount) (expected 0)" }
    if ($Mode -eq 'Report' -and -not $result.ReportOnly) { $failures += "ReportOnly not confirmed in result JSON" }
    if ($Mode -ne 'Report' -and [long]$result.TotalFreedBytes -le 0) {
        $failures += "Full mode freed nothing (TotalFreedBytes = $($result.TotalFreedBytes))"
    }
}

if (-not $logRaw) {
    $failures += "Log file was not produced"
} elseif ($logRaw -notmatch 'WinClean v[\d.]+ - Started') {
    $failures += "Log lost its header (log-survival regression?)"
}

$outLines = $consoleOut -split "`r?`n"
$errorLines = $outLines | Where-Object { $_ -match '\[ERROR\]' }
if ($errorLines) { $failures += "[ERROR] lines in console output: $($errorLines.Count)" }

# Guard against a vacuous geometry pass: if no box-drawing survived the transport,
# the output arrived garbled and the geometry check would silently check nothing
if (-not ($consoleOut -match '╔')) {
    $failures += "No box-drawing characters in console output (encoding/transport problem?)"
}
$geometryIssues = Test-BoxGeometry -Lines $outLines
foreach ($issue in $geometryIssues) { $failures += "Box geometry: $issue" }

# 6. Shutdown + verdict
if (-not $KeepRunning) {
    Write-Host "[6/6] Shutting down the stand VM..." -ForegroundColor Cyan
    $null = Invoke-Pve -Config $cfg -Command "qm shutdown $vmid --timeout 180" -AllowFail
} else {
    Write-Host "[6/6] VM left running (-KeepRunning)." -ForegroundColor Yellow
}

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "STAND TEST PASSED ($Mode/$Source)" -ForegroundColor Green
    if ($jsonRaw) {
        $result = $jsonRaw | ConvertFrom-Json
        Write-Host "  v$($result.Version), $($result.DurationSeconds)s, freed $([math]::Round($result.TotalFreedBytes/1MB,1)) MB, warnings: $($result.WarningsCount)" -ForegroundColor DarkGray
    }
    Write-Host "  Artifacts: $resultsDir" -ForegroundColor DarkGray
    exit 0
} else {
    Write-Host "STAND TEST FAILED ($($failures.Count) issue(s)):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Yellow }
    Write-Host "  Artifacts: $resultsDir" -ForegroundColor DarkGray
    exit 1
}
