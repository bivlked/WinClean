# Result JSON schema

WinClean can write a machine-readable summary of a run to a file, for automation, CI and the Proxmox test stand. Pass `-ResultJsonPath` to enable it:

```powershell
.\WinClean.ps1 -ReportOnly -ResultJsonPath .\run-result.json
```

If `-ResultJsonPath` is not given, no JSON is written. When it is given, the file is overwritten at the start of the run, so a stale copy from a previous run can never be read as this run's outcome. The JSON is UTF-8, produced by `Write-ResultJson` in `WinClean.ps1`.

This page documents every field, gives a full sample, and explains how to consume it safely.

## Fields

| Field | Type | Meaning |
|-------|------|---------|
| `Version` | string | Script version that produced this file, e.g. `"2.19"`. |
| `Timestamp` | string | Run time in ISO-8601 round-trip format (`"o"`, e.g. `2026-07-21T03:15:42.1234567+00:00`). Use it to confirm the file belongs to the run you started, not a leftover. |
| `DurationSeconds` | number | Wall-clock duration of the run, rounded to one decimal. |
| `ReportOnly` | bool | `true` when the run was a preview (`-ReportOnly`): nothing was changed. |
| `Parameters` | object | The switches the run was invoked with (see below). |
| `TotalFreedBytes` | long | Total bytes freed across all categories. `0` in `-ReportOnly`. |
| `FreedByCategory` | object | Map of category name to bytes freed, e.g. `{ "Temp": 187912345, "DriverStore": 451801088 }`. Only non-zero categories appear. |
| `WindowsUpdatesCount` | number | Number of Windows updates installed (from PSWindowsUpdate, which reports per-update results, so this is a real installed count). |
| `AppUpdatesOffered` | number | Number of application updates winget **offered**. See the note below - this is not a confirmed install count. |
| `WarningsCount` | number | Count of warnings raised during the run. Warnings are the silent-failure alarm; treat a non-zero value as something to inspect. |
| `ErrorsCount` | number | Count of errors raised during the run. A healthy run reports `0`. |
| `RebootRequired` | bool | `true` when a change (a Windows update, an app update finishing on reboot) needs a restart to take effect. |
| `ControlledFolderAccess` | string | Tri-state, see below. Reflects whether Defender's Controlled Folder Access may have silently blocked deletions. |
| `Aborted` | string or null | `null` for a normal run. A reason string (e.g. `"PendingRebootDeclined"`) when the run stopped early. When set, the phase arrays below are incomplete by design. |
| `PhasesCompleted` | array of string | Phases whose action ran to completion without an uncaught exception. |
| `PhasesFailed` | array of string | Phases whose action threw. |
| `PhasesSkipped` | array of string | Phases a skip flag suppressed before they ran. |
| `LogPath` | string | Absolute path of the run's log file. |

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
| `DisableTelemetry` | bool |

`-ReportOnly`, `-LogPath` and `-ResultJsonPath` are not repeated here (`ReportOnly` and `LogPath` are top-level fields; the JSON path is the file you are reading).

### `AppUpdatesOffered` (renamed in v2.19)

Before v2.19 this field was `AppUpdatesCount` and was presented as an installed count. That was a false claim. `winget upgrade --all` returns exit code 0 on success but does **not** report how many packages it actually upgraded: it silently skips packages that are pinned, have no manifest, or where the user cancelled the UAC prompt. WinClean only knows how many updates winget **offered** (parsed from the upgrade table before the install), so the honest figure is the offered count.

Consequently:

- `AppUpdatesOffered` is set from the parsed upgrade table and is meaningful in every path, including `-ReportOnly` and a later failed upgrade.
- It is **not** proof that N applications were installed. If you need the true installed set, parse winget's own per-package output separately; WinClean does not attempt this.
- The console summary reflects the same honesty: `Windows: X installed, Apps: Y offered`.

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

**Invariant.** For a run that was not aborted (`Aborted` is `null`), the three arrays are pairwise disjoint and their union is exactly those nine names. A name missing from all three means the run stopped before it was dispatched (a crash outside any phase boundary). This invariant is what makes the tri-state trustworthy: you can tell "everything ran" from "phase N never happened".

## Sample

```json
{
  "Version": "2.19",
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
  "WarningsCount": 1,
  "ErrorsCount": 0,
  "RebootRequired": false,
  "ControlledFolderAccess": "disabled",
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

# Phase invariant (only meaningful when the run was not aborted)
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
- The phase arrays are disjoint, their union is the nine known phases, and any skip flag in `Parameters` is reflected in `PhasesSkipped` (for example, the `ReportNoCleanup` mode sets `-SkipCleanup` and expects the whole cleanup group to be skipped).
