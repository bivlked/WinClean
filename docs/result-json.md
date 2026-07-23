# Result JSON schema

WinClean can write a machine-readable summary of a run to a file, for automation, CI and the Proxmox test stand. Pass `-ResultJsonPath` to enable it:

```powershell
.\WinClean.ps1 -ReportOnly -ResultJsonPath .\run-result.json
```

If `-ResultJsonPath` is not given, no JSON is written. When it is given, the previous file is removed at startup (best-effort; the deletion error is suppressed), so a stale copy from an earlier run is not mistaken for this one. Pair it with the `Timestamp` check below to be certain. The JSON is UTF-8, produced by `Write-ResultJson` in `WinClean.ps1`.

This page documents every field, gives a full sample, and explains how to consume it safely.

## Fields

| Field | Type | Meaning |
|-------|------|---------|
| `Version` | string | Script version that produced this file, e.g. `"2.22"`. |
| `Timestamp` | string | Run time in ISO-8601 round-trip format (`"o"`, e.g. `2026-07-21T03:15:42.1234567+00:00`). Use it to confirm the file belongs to the run you started, not a leftover. |
| `DurationSeconds` | number | Wall-clock duration of the run, rounded to one decimal. |
| `ReportOnly` | bool | `true` when the run was a preview (`-ReportOnly`): no cleanup or updates were applied (the log and this result file are still written). |
| `Parameters` | object | The switches the run was invoked with (see below). |
| `TotalFreedBytes` | long | Total bytes freed across all categories. `0` in `-ReportOnly`. |
| `FreedByCategory` | object | Map of category name to bytes freed, e.g. `{ "Temp": 187912345, "DriverStore": 451801088 }`. Categories are added as work happens, so a category can appear with `0` (for example DriverStore is recorded after a successful package removal even if the measured freed size was zero). |
| `WindowsUpdatesCount` | number | Number of Windows updates installed (from PSWindowsUpdate, which reports per-update results, so this is a real installed count). |
| `AppUpdatesOffered` | number | Number of application updates winget **offered**. See the note below - this is not a confirmed install count. |
| `AppUpdatesStatus` | string | Why that count is what it is: `checked`, `check-failed`, `skipped-parameter`, `skipped-offline`, `skipped-no-winget`, or `not-run`. Added in v2.21. |
| `WarningsCount` | number | Count of warnings raised during the run. Warnings are the silent-failure alarm; treat a non-zero value as something to inspect. |
| `ErrorsCount` | number | Count of errors raised during the run. A healthy run reports `0`. |
| `RebootRequired` | bool | `true` when a change (a Windows update, an app update finishing on reboot) needs a restart to take effect. |
| `LoggingDegraded` | bool | v2.20. `true` when writing the log file failed at some point during the run. The run itself still completed, but `LogPath` points at an incomplete file: do not read that log as the full record of what happened. |
| `DiskCleanupPending` | bool | v2.20. `true` when Disk Cleanup was still **visibly working** when its timeout expired and was left running in the background; `TotalFreedBytes` is then a lower bound. Note `false` is not a proof that nothing more will ever be deleted - see `DiskCleanupStatus`, which is the field to read when that distinction matters. |
| `DiskCleanupStatus` | string | v2.22. How the Storage Sense / Disk Cleanup step actually ended - twelve values, listed below. The boolean above could not tell a cleanup that had stopped doing anything from one still deleting, and reported both as pending. |
| `ControlledFolderAccess` | string | Tri-state, see below. Reflects whether Defender's Controlled Folder Access may have silently blocked deletions. |
| `Aborted` | string or null | `null` unless the run stopped early for a known reason: `"PendingRebootDeclined"` (the user declined to continue with a reboot pending) or `"UpdatedAndExited"` (v2.21 - the script updated itself and exited so the new version runs next time). When set, the phase arrays below are incomplete by design. Note `null` does not by itself prove every phase ran - see the invariant note below. |
| `PhasesCompleted` | array of string | Phases whose action ran to completion without an uncaught exception. |
| `PhasesFailed` | array of string | Phases whose action threw. |
| `PhasesSkipped` | array of string | Phases a skip flag suppressed before they ran. |
| `LogPath` | string | Path to the run's log file (as given; it may be relative if `-LogPath` was passed a relative path). |

### `Parameters`

An object of booleans mirroring the run's switches:

| Key | Type |
|-----|------|
| `SkipUpdates` | bool |
| `SkipCleanup` | bool |
| `SkipRestore` | bool |
| `SkipDevCleanup` | bool |
| `SkipDockerCleanup` | bool |
| `SkipVSCleanup` | bool |
| `SkipDiskCleanup` | bool |
| `DisableTelemetry` | bool |

`-ReportOnly`, `-LogPath` and `-ResultJsonPath` are not repeated here (`ReportOnly` and `LogPath` are top-level fields; the JSON path is the file you are reading).

### `AppUpdatesOffered` (renamed in v2.19)

Before v2.19 this field was `AppUpdatesCount` and was presented as an installed count. That was a false claim. `winget upgrade --all` returns exit code 0 on success but does **not** report how many packages it actually upgraded: it silently skips packages that are pinned, have no manifest, or where the user cancelled the UAC prompt. WinClean only knows how many updates winget **offered** (parsed from the upgrade table before the install), so the honest figure is the offered count.

Consequently:

- `AppUpdatesOffered` is set from the parsed upgrade table and is meaningful in every path, including `-ReportOnly` and a later failed upgrade.
- It is **not** proof that N applications were installed. If you need the true installed set, parse winget's own per-package output separately; WinClean does not attempt this.
- The console summary reflects the same honesty: `Windows: X installed, Apps: Y offered`.

### `AppUpdatesStatus` (added in v2.21)

`AppUpdatesOffered: 0` on its own is ambiguous: it is what you get both when winget was asked and had nothing to upgrade, and when winget was never asked at all. Until v2.21 the two could be told apart by the exit code, because a missing winget was an error. That is no longer true - a missing optional tool is now a warning, so the run can exit 0 - and this field carries the distinction instead.

| Value | Meaning |
|-------|---------|
| `checked` | winget was found, asked, and returned a list. `AppUpdatesOffered` is a real answer. |
| `check-failed` | winget was found but the check did not produce a list - it timed out, exited non-zero, or could not be completed at all. The count is meaningless. |
| `skipped-no-winget` | winget is not installed on this machine. The run continues; a warning is logged. |
| `skipped-offline` | No connectivity. Both halves of the Updates phase (Windows and apps) read the same connectivity check, so this value describes the whole phase, not just winget. A warning, not an error, since v2.21. |
| `skipped-parameter` | `-SkipUpdates` was passed. |
| `not-run` | The phase never executed (for example the run aborted earlier). |

Treat any value other than `checked` as "the count means nothing", not as "there was nothing to update".

### `DiskCleanupStatus` (added in v2.22)

`DiskCleanupPending` alone could not tell two different situations apart, and reported
both as pending. Measured on a live workstation: `cleanmgr /sagerun` did its work in about
ten seconds, closed its window, and then stayed in the process list doing nothing at all -
no CPU, no I/O, every thread waiting. Treating process exit as the only sign that there is
still something to wait for therefore burned the remaining fifteen-minute timeout, and
then published as partial a cleanup that had not been observed doing anything for most of
that time.

Since v2.22 a second, independent signal is used to stop waiting: total stillness. If the
process was seen working and then performs no CPU work and no I/O across twelve
consecutive ten-second checks, there is nothing observable left to wait for. That is
deliberately weaker than "it has finished", and the field names the observation rather
than the conclusion.

| Value | Meaning |
|-------|---------|
| `completed` | cleanmgr ran and exited with code 0. |
| `idle-resident` | cleanmgr was seen working, then did nothing at all for two minutes and never exited. Reported as what was **observed**, not as proven completion: a process performing no CPU work and no I/O is not deleting anything, so the figures are treated as final and `DiskCleanupPending` stays `false`. |
| `timeout` | The wait expired without either signal firing. That includes the case where activity could never be measured at all (WMI unavailable) or was never observed, so it does not by itself mean cleanmgr was seen working. `DiskCleanupPending` is `true` and `TotalFreedBytes` is a lower bound. |
| `running` | Set as soon as cleanmgr starts, and replaced by one of the values above when the wait ends. Seeing it in a result file means the run was interrupted while an elevated cleanmgr was in flight - the totals are not final and the process may still be deleting. |
| `storage-sense` | Storage Sense demonstrably did the work, so cleanmgr was not run. Note this covers a different, smaller set of things than cleanmgr handlers - it does not touch Update Cleanup, memory dumps, Language Pack, old ChkDsk files or Windows Error Reporting. |
| `not-armed` | No Disk Cleanup handler could be armed, so cleanmgr was never started. Nothing was attempted and nothing is half-done. |
| `start-failed` | cleanmgr.exe could not be started at all (missing, or blocked by AppLocker/WDAC). Nothing was attempted. |
| `exit-nonzero` | cleanmgr started and exited with a non-zero code. Unlike the two above, it **ran**: the machine may be partially cleaned. |
| `skipped-parameter` | `-SkipDiskCleanup` was passed. |
| `skipped-cleanup-group` | `-SkipCleanup` was passed, which suppresses the whole cleanup group before this step is dispatched. |
| `skipped-report-only` | `-ReportOnly` was passed. This is what every preview run, the smoke test and the `Report`/`ReportNoCleanup` stand modes produce. |
| `not-run` | The step never executed - the run aborted before reaching it. |

`idle-resident` is not an error, and it is named after the observation rather than after
the conclusion on purpose. What is measured is stillness; "it finished" is an inference
from it, and the inference can be wrong - a cleanmgr blocked on something external would
look identical. Nothing downstream is built to depend on it being right: the registry
configuration of a process that has not exited is still left alone, and the log states
what was actually seen. A `cleanmgr.exe` still visible in Task Manager after the run is
the expected consequence, which is why it is reported rather than left to be discovered.

### `ControlledFolderAccess` (tri-state string)

| Value | Meaning |
|-------|---------|
| `"disabled"` | Controlled Folder Access is off. Cleanup figures are trustworthy. |
| `"enabled"` | Controlled Folder Access is on. Defender can block deletions inside protected folders without raising an error, so the freed-space figures are **understated**. Add `pwsh.exe` to the allowed apps list. |
| `"unknown"` | The check itself failed (Defender cmdlets unavailable, stripped image, broken WMI). The figures are **unverified**, not confirmed good. |

It is always a string, never a boolean, so `"unknown"` can never be mistaken for a verified state.

### Phase arrays: a dispatch status, not an outcome (v2.19)

`PhasesCompleted`, `PhasesFailed` and `PhasesSkipped` classify each of the nine top-level phases by how it was **dispatched**, not by whether the underlying work succeeded:

- **Completed** = the phase action was invoked and returned without an uncaught exception. This is not the same as "succeeded". For example, `Preparation` stays in `Completed` even when the restore point genuinely failed, because `New-SystemRestorePoint` catches that failure internally and returns without throwing. Likewise, environmental no-ops and `-ReportOnly` previews land in `Completed`.
- **Skipped** = a skip flag suppressed the phase before its action ran (for example `-SkipUpdates` puts `Updates` here; `-SkipCleanup` puts the whole cleanup group here).
- **Failed** = the phase action threw out to the phase boundary. This also increments `ErrorsCount`.

The nine known phases are:

```
Preparation, Updates, SystemCleanup, DeveloperCleanup, DockerWSLCleanup,
VisualStudioCleanup, DeepSystemCleanup, DiskSpaceReport, Telemetry
```

**Invariant.** The three arrays are pairwise disjoint by dispatcher design - a phase lands in exactly one bucket. A healthy run's union is exactly those nine names. Note that `Aborted == null` alone does not guarantee a complete union: an exception thrown *outside* any phase boundary is caught without setting `Aborted`, so a name can be missing while `Aborted` is still `null` (that path also increments `ErrorsCount`). So verify the union independently, and read a missing name together with a non-zero `ErrorsCount` as a crash outside a phase. This is what makes the tri-state trustworthy: you can tell "everything ran" from "phase N never happened".

## Sample

```json
{
  "Version": "2.22",
  "Timestamp": "2026-07-21T03:15:42.1234567+00:00",
  "DurationSeconds": 196.4,
  "ReportOnly": false,
  "Parameters": {
    "SkipUpdates": true,
    "SkipCleanup": false,
    "SkipRestore": false,
    "SkipDevCleanup": false,
    "SkipDockerCleanup": false,
    "SkipVSCleanup": false,
    "SkipDiskCleanup": false,
    "DisableTelemetry": false
  },
  "TotalFreedBytes": 3201171456,
  "FreedByCategory": {
    "Temp": 197013504,
    "Browser": 88604672,
    "DriverStore": 451801088,
    "ComponentStore": 1932735283,
    "DiskCleanup": 531016909
  },
  "WindowsUpdatesCount": 0,
  "AppUpdatesOffered": 0,
  "AppUpdatesStatus": "skipped-parameter",
  "WarningsCount": 1,
  "ErrorsCount": 0,
  "RebootRequired": false,
  "ControlledFolderAccess": "disabled",
  "LoggingDegraded": false,
  "DiskCleanupPending": false,
  "DiskCleanupStatus": "completed",
  "Aborted": null,
  "PhasesCompleted": [
    "Preparation",
    "SystemCleanup",
    "DeveloperCleanup",
    "DockerWSLCleanup",
    "VisualStudioCleanup",
    "DeepSystemCleanup",
    "DiskSpaceReport",
    "Telemetry"
  ],
  "PhasesFailed": [],
  "PhasesSkipped": [
    "Updates"
  ],
  "LogPath": "C:\\Users\\me\\AppData\\Local\\Temp\\WinClean_20260721_031542.log"
}
```

In this sample the run used `-SkipUpdates`, so `Updates` is in `PhasesSkipped` (not `Completed`), and the union of the three phase arrays is the full set of nine names.

## Consuming from CI

A minimal assertion in PowerShell after a run:

```powershell
$r = Get-Content .\run-result.json -Raw | ConvertFrom-Json

if ($r.ErrorsCount -ne 0) { throw "WinClean reported $($r.ErrorsCount) error(s)" }
if ($r.ControlledFolderAccess -eq 'unknown') { throw "Cleanup figures are unverified" }

# Phase invariant. The ErrorsCount check above already catches a crash outside a phase
# boundary (that path bumps ErrorsCount without setting Aborted), so reaching here with
# no error means the union below should be complete.
if (-not $r.Aborted) {
    $known = 'Preparation','Updates','SystemCleanup','DeveloperCleanup',
             'DockerWSLCleanup','VisualStudioCleanup','DeepSystemCleanup',
             'DiskSpaceReport','Telemetry'
    $union = @($r.PhasesCompleted + $r.PhasesFailed + $r.PhasesSkipped)
    if (@($union | Sort-Object -Unique).Count -ne $union.Count) {
        throw "Phase buckets overlap"
    }
    $missing = @($known | Where-Object { $_ -notin $union })
    if ($missing) { throw "Phases never dispatched: $($missing -join ', ')" }

    # A skipped flag must show up as Skipped, not Completed
    if ($r.Parameters.SkipUpdates -and 'Updates' -notin $r.PhasesSkipped) {
        throw "SkipUpdates set but 'Updates' not reported as skipped"
    }
}
```

`ConvertFrom-Json` in PowerShell 7 parses the ISO-8601 `Timestamp` into a `[datetime]` automatically. On a non en-US locale, do not re-parse it with `[datetime]::Parse` using the current culture; accept the `[datetime]` as-is, or parse with `[cultureinfo]::InvariantCulture` and `DateTimeStyles::RoundtripKind`.

## Consuming from a test stand

The Proxmox stand (`tools/proxmox/Invoke-StandTest.ps1`) reads this JSON and fails the run unless:

- `ErrorsCount == 0` and no `[ERROR]` lines appear in the console output.
- `Timestamp` is fresh (belongs to the run just started), so a stale file cannot pass as a new run.
- `Aborted` is `null`.
- `WarningsCount` is within the configured budget (one known warning is expected on both VMs).
- `ControlledFolderAccess` is not `"unknown"`.
- In report modes (`Report`, `ReportNoCleanup`): `ReportOnly` is `true` and `TotalFreedBytes == 0` (a preview that frees bytes is a regression).
- In full modes: `TotalFreedBytes` is well above a trivial threshold.
- The phase arrays are disjoint, their union is the nine known phases, and a skip flag that gates a whole phase is reflected in `PhasesSkipped` (for example, the `ReportNoCleanup` mode sets `-SkipCleanup` and expects the whole cleanup group to be skipped). `-SkipDiskCleanup` is the exception and deliberately so: it suppresses one step inside `DeepSystemCleanup`, not the phase, so that phase still lands in `PhasesCompleted`. These phase checks apply only to result JSON produced by 2.19 or newer: the nightly also runs a pass against the latest published release, which can predate the schema, and asserting it there would fail the run for version skew rather than for a defect. When they are skipped, the harness says so.
