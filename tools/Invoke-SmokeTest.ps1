#Requires -Version 7.1

<#
.SYNOPSIS
    WinClean smoke test: safe ReportOnly run + automated result and UI checks
.DESCRIPTION
    Runs WinClean.ps1 in -ReportOnly mode (no system changes), captures the console
    output and the machine-readable result JSON, then verifies:
      1. Exit code is 0 and the run produced a result JSON with ErrorsCount = 0
      2. No ERROR-level lines in the output
      3. Console box geometry: every ║/╠/╟/╚ line matches its box's ╔ border width
         (catches the "разъехавшиеся рамки" class of display bugs automatically)
    Used locally, in CI, and by the Proxmox test stand.
.PARAMETER ScriptPath
    Path to WinClean.ps1 (default: repository root relative to this script)
.PARAMETER OutDir
    Where to store captured artifacts (default: scratch dir in TEMP)
.PARAMETER IncludeUpdates
    Do NOT pass -SkipUpdates (slower: winget/WU checks run; still ReportOnly)
.OUTPUTS
    Exit code 0 = smoke test passed, 1 = failed. Prints a verdict summary.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..' 'WinClean.ps1'),
    [string]$OutDir = (Join-Path $env:TEMP "WinCleanSmoke_$(Get-Date -Format 'yyyyMMdd_HHmmss')"),
    [switch]$IncludeUpdates
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BoxGeometry.ps1')

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$outputFile = Join-Path $OutDir 'console-output.txt'
$resultJson = Join-Path $OutDir 'result.json'

$scriptArgs = @('-ReportOnly', '-ResultJsonPath', $resultJson)
if (-not $IncludeUpdates) { $scriptArgs += '-SkipUpdates' }

Write-Host "Smoke test: running WinClean in ReportOnly mode..." -ForegroundColor Cyan
Write-Host "  Script:    $ScriptPath" -ForegroundColor DarkGray
Write-Host "  Artifacts: $OutDir" -ForegroundColor DarkGray

& pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @scriptArgs *> $outputFile
$exitCode = $LASTEXITCODE

$failures = @()

# 1. Exit code
if ($exitCode -ne 0) { $failures += "Exit code: $exitCode (expected 0)" }

# 2. Result JSON
if (-not (Test-Path $resultJson)) {
    $failures += "Result JSON was not created: $resultJson"
} else {
    $result = Get-Content $resultJson -Raw | ConvertFrom-Json
    if ($result.ErrorsCount -ne 0) { $failures += "ErrorsCount = $($result.ErrorsCount) (expected 0)" }
    if (-not $result.ReportOnly) { $failures += "Result JSON does not confirm ReportOnly mode" }
}

# 3. Console output checks
$lines = Get-Content $outputFile
$errorLines = $lines | Where-Object { $_ -match '\[ERROR\]' }
if ($errorLines) { $failures += "ERROR lines in output: $($errorLines.Count) (first: '$($errorLines[0].Trim())')" }

# Guard against a vacuous geometry pass: output must contain at least one box
if (-not (($lines -join "`n") -match '╔')) {
    $failures += "No box-drawing characters in output (encoding problem?)"
}
$geometryIssues = Test-BoxGeometry -Lines $lines
foreach ($issue in $geometryIssues) { $failures += "Box geometry: $issue" }

# Verdict
Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "SMOKE TEST PASSED" -ForegroundColor Green
    Write-Host "  Boxes OK, no errors, result JSON valid (v$($result.Version), $($result.DurationSeconds)s)" -ForegroundColor DarkGray
    exit 0
} else {
    Write-Host "SMOKE TEST FAILED ($($failures.Count) issue(s)):" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Yellow }
    Write-Host "  Full output: $outputFile" -ForegroundColor DarkGray
    exit 1
}
