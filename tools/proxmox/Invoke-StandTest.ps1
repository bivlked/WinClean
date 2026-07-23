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
    ReportNoCleanup: -ReportOnly -SkipCleanup -SkipUpdates - verifies the v2.19
    contract that -SkipCleanup suppresses the whole cleanup group (F1), e2e via the
    PhasesSkipped buckets. Also fast; changes nothing.
    Full: real cleanup WITHOUT updates (-SkipUpdates; updates need Windows
    licensing/network time and are better exercised manually).
    FullWithUpdates: everything enabled - the complete production scenario (slow).
.PARAMETER Source
    local (default): upload the working-tree WinClean.ps1 (tests unpushed changes).
    main / release: the guest downloads WinClean.ps1 by raw URL from that branch/tag
    (raw.githubusercontent.com/.../<ref>/WinClean.ps1). This exercises the script at that
    ref, not the release asset download or the get.ps1 one-liner (use -VerifyPublished
    and a manual one-liner run for those).
.PARAMETER KeepRunning
    Leave the VM running after the test (for interactive debugging via console)
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'ReportNoCleanup', 'Full', 'FullWithUpdates')]
    [string]$Mode = 'Report',

    [ValidateSet('local', 'main', 'release')]
    [string]$Source = 'local',

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'stand.config.json'),
    [switch]$KeepRunning,

    # v2.17: warnings are the silent-failure alarm; the stand fails above this budget.
    # One known warning is expected on both VMs (a single busy event log channel).
    [int]$MaxWarnings = 1
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StandCommon.ps1')
# BoxGeometry sits flat next to this script in the deployed nightly-runner
# layout (preferred), or one level up in the repository layout
$boxGeometryPath = @(
    (Join-Path $PSScriptRoot 'BoxGeometry.ps1')
    (Join-Path $PSScriptRoot '..' 'BoxGeometry.ps1')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $boxGeometryPath) { throw "BoxGeometry.ps1 not found next to or above $PSScriptRoot" }
. $boxGeometryPath

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
        # Repository layout: ../../WinClean.ps1; deployed flat layout: ./WinClean.ps1
        $localScript = @(
            (Join-Path $PSScriptRoot '..' '..' 'WinClean.ps1')
            (Join-Path $PSScriptRoot 'WinClean.ps1')
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $localScript) {
            throw "Source 'local' requires WinClean.ps1 in the repository root or next to this script (deployed runners should use -Source main/release)"
        }
        Copy-FileToGuest -Config $cfg -LocalPath (Resolve-Path $localScript).Path -GuestPath $guestScript
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
    'ReportNoCleanup' { "-ReportOnly -SkipCleanup -SkipUpdates" }
    'Full'            { "-SkipUpdates" }
    'FullWithUpdates' { "" }
}
$timeout = switch ($Mode) {
    'Report'          { 1800 }
    'ReportNoCleanup' { 1800 }
    'Full'            { 3600 }
    'FullWithUpdates' { 7200 }
}

Write-Host "[3/6] Running WinClean ($Mode, timeout ${timeout}s)..." -ForegroundColor Cyan
# v2.17: delete artifacts from any previous run inside the guest. A rollback normally
# removes them, but if WinClean fails to write a fresh result the stand would otherwise
# read the previous one and report a PASS built on stale data.
$null = Invoke-GuestCommand -Config $cfg -UsePwsh -Script @"
Remove-Item -LiteralPath '$guestJson', '$guestLog', 'C:\Windows\Temp\winclean-console.txt' -Force -ErrorAction SilentlyContinue
"@
$runStartedUtc = (Get-Date).ToUniversalTime()
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

    # The JSON must belong to THIS run (v2.17). ConvertFrom-Json in PS7 already turns the
    # ISO-8601 Timestamp into a [datetime], so [datetime]::Parse would re-stringify it via
    # the current culture and then fail to read its own output back on a non-en-US locale
    # (ru-RU: "20.07.2026" vs the "07/20/2026" Parse expects). Accept a [datetime] as-is;
    # only Parse when it actually arrived as a string.
    $stamp = try {
        if ($result.Timestamp -is [datetime]) { $result.Timestamp.ToUniversalTime() }
        else { [datetime]::Parse([string]$result.Timestamp, [cultureinfo]::InvariantCulture).ToUniversalTime() }
    } catch { $null }
    if (-not $stamp) {
        $failures += "Result JSON has no parseable Timestamp"
    } elseif ($stamp -lt $runStartedUtc.AddMinutes(-1)) {
        $failures += "Result JSON is stale (written $stamp, run started $runStartedUtc)"
    }

    if ($result.Aborted) { $failures += "Run aborted early: $($result.Aborted)" }

    # Warnings are the entire silent-failure alarm added in v2.16/v2.17 - ignoring them
    # here would switch that alarm off precisely where it matters most
    if ([int]$result.WarningsCount -gt $MaxWarnings) {
        $failures += "WarningsCount = $($result.WarningsCount) (allowed: $MaxWarnings)"
    }
    if ($result.ControlledFolderAccess -eq 'unknown') {
        $failures += "Controlled Folder Access state could not be verified - cleanup figures are unreliable"
    }

    # A report mode that silently ran for real is the 18.07 incident: guard it explicitly
    # before trusting the ReportOnly-driven branch below, or a run that dropped ReportOnly
    # would fall through to the "Full freed enough" check and pass while destroying data.
    # Parenthesised in v2.22 for readability only. An external reviewer read the
    # unparenthesised form as ambiguous and suspected ReportNoCleanup fell outside the
    # guard; it did not - PowerShell binds -in tighter than -and, and both the AST and a
    # truth table confirmed the grouping was already ($Mode -in @(...)) -and (-not ...).
    # The behaviour is unchanged; the parentheses just stop the next reader from having to
    # verify that again. StandHelpers.Tests.ps1 pins the truth table.
    if (($Mode -in 'Report', 'ReportNoCleanup') -and (-not $result.ReportOnly)) {
        $failures += "ReportOnly not confirmed in result JSON for mode $Mode"
    }
    if ($result.ReportOnly) {
        # A preview that frees bytes is the 18.07 incident happening again
        if ([long]$result.TotalFreedBytes -ne 0) {
            $failures += "Report mode freed $($result.TotalFreedBytes) bytes - it must change nothing"
        }
    } elseif ([long]$result.TotalFreedBytes -le 1MB) {
        # One byte used to be enough to pass; a real run on a rolled-back VM frees far more
        $failures += "Full mode freed almost nothing (TotalFreedBytes = $($result.TotalFreedBytes))"
    }

    # v2.19: the three phase buckets are a dispatch status. Validate the invariant on
    # real hardware - they must be disjoint, and for a run that was not aborted their
    # union must be exactly the known phase set (a name missing from all three means the
    # run crashed before dispatching it). A phase the user skipped must land in
    # PhasesSkipped, never PhasesCompleted - this exercises the F2/F3 honesty fix e2e.
    #
    # Gated on the version that produced the JSON: the -Source release pass runs the
    # latest PUBLISHED script, which predates this schema, and asserting it there would
    # fail the nightly for version skew rather than for a broken release.
    $hasPhaseBuckets = Test-ResultSupportsPhaseBuckets ([string]$result.Version)
    if (-not $result.Aborted -and -not $hasPhaseBuckets) {
        # Say it out loud: a silently skipped assertion reads as a passed one
        Write-Host "  note: phase-bucket assertions skipped, result JSON is from v$($result.Version) (pre-2.19 schema)" -ForegroundColor DarkYellow
    }
    if (-not $result.Aborted -and $hasPhaseBuckets) {
        $knownPhases = @('Preparation','Updates','SystemCleanup','DeveloperCleanup',
                         'DockerWSLCleanup','VisualStudioCleanup','DeepSystemCleanup',
                         'DiskSpaceReport','Telemetry')
        $completed = @($result.PhasesCompleted)
        $skipped   = @($result.PhasesSkipped)
        $failed    = @($result.PhasesFailed)
        $union     = @($completed + $skipped + $failed)

        if (@($union | Sort-Object -Unique).Count -ne $union.Count) {
            $failures += "Phase buckets overlap - a phase is in more than one of Completed/Skipped/Failed"
        }
        $missing = @($knownPhases | Where-Object { $_ -notin $union })
        $extra   = @($union | Where-Object { $_ -notin $knownPhases })
        if ($missing) { $failures += "Phases missing from result JSON (crashed before dispatch?): $($missing -join ', ')" }
        if ($extra)   { $failures += "Unexpected phase names in result JSON: $($extra -join ', ')" }

        if ($result.Parameters.SkipUpdates) {
            if ('Updates' -notin $skipped) { $failures += "SkipUpdates set but 'Updates' not in PhasesSkipped" }
            if ('Updates' -in $completed)  { $failures += "SkipUpdates set but 'Updates' counted as Completed" }
        }
        if ($result.Parameters.SkipCleanup) {
            foreach ($ph in 'SystemCleanup','DeepSystemCleanup','DeveloperCleanup','DockerWSLCleanup','VisualStudioCleanup','DiskSpaceReport') {
                if ($ph -notin $skipped) { $failures += "SkipCleanup set but '$ph' not in PhasesSkipped" }
            }
        }
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
