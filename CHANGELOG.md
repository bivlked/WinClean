# Changelog / История изменений

All notable changes to WinClean will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

Planned for a later release: quick system health section (SMART, image integrity, WinRE),
Windows Update driver listing, run-to-run delta and HTML report. See CLAUDE.md.

---

## [2.17] - NOT RELEASED YET

Work in progress: fixes are being accumulated before publishing. The code in `main`
already carries them, but `get.ps1` and `install.ps1` keep serving 2.16 from the latest
GitHub Release until this version is tagged.

Silent failure hardening. Found by a dedicated review pass over 2.16: an operation that
quietly does nothing is worse than one that fails loudly, because the log reports success
and the user never learns that the gigabytes are still there. Every finding below is a
place where that could happen.

### Fixed

- **Cleanups that free nothing from a non-empty folder are now reported.** Previously the
  script simply stayed silent, so a blocked deletion was indistinguishable from "there was
  nothing to clean". If Controlled Folder Access is enabled, it is named as the likely cause
- **Browser caches were logged as "cleaned" even when nothing was freed** - a running browser
  locks its cache, so the success message was plainly false
- **Kernel dump deletion failures were swallowed by an empty catch block**: `-ReportOnly`
  promised gigabytes, the real run said nothing at all, and the files stayed
- **Driver package removal failures were not counted**, and a successful cleanup whose
  per-package sizes could not be attributed reported `0 B` freed. The driver store is now
  measured before and after as a fallback
- **`pnputil` exit code was never checked**: any failure looked exactly like
  "no superseded driver packages found". Unparseable packages are counted, and an
  unparseable date no longer discards the package (the date is only a sort tie-breaker)
- **Disk Cleanup did not verify that categories were armed** - a failed registry write meant
  cleanmgr ran with an empty set, exited 0 and was logged as a success. Its exit code was
  not checked either
- **Delivery Optimization reported "cache cleaned" without measuring anything**, and a
  failure of the supported cmdlet was silently swallowed
- **The temp age filter failed open**: if a subtree could not be read, the folder was treated
  as stale and deleted. It now fails closed - what cannot be verified is kept
- **Controlled Folder Access reported `false` when the check itself failed**, telling
  automated runs the figures were trustworthy when they had never been verified. Now `unknown`
- **Downloaded-but-not-applied Windows updates were counted as installed**, producing
  "All N updates installed successfully" for updates still pending a reboot
- `-ReportOnly` now measures exactly the set the real run deletes, including excluded files
- winget source update timeouts and result JSON write failures now count as warnings; the
  latter matters because an automated stand would otherwise read the previous run's file

### Fixed (second pass: full-codebase audit)

Bootstrap scripts, the most security-sensitive code here since they download and run
elevated code from the internet:

- **SHA256 verification was optional.** It sat inside `if ($hashAsset)`, so a release
  published without the hash asset ran completely unverified, silently. Removing a file
  is easier than forging one, which made this the obvious thing to attack. Both assets
  are now mandatory
- **A missing asset fell back to `raw.githubusercontent.com` at the release tag**, which
  the comment right above it described as "fail closed". Git tags are movable; release
  assets are not. The fallback is gone
- **Hashes were compared with `-notlike`**, so the published hash was treated as a
  wildcard pattern: a single `*` in that file would "verify" any download and print
  `SHA256 verified.` Now a literal, case-insensitive comparison with a format check
- `install.ps1` **trusted `$env:ProgramFiles`**, a user-writable environment variable, to
  locate `pwsh.exe` and the install directory - and then pointed an elevated desktop
  shortcut at them. Resolved through `[Environment]::GetFolderPath` instead, with the
  install path rejected if it contains characters that would inject into the shortcut
  command line
- Download URLs from the API response are validated (https, GitHub host only), redirects
  are capped, failures set a non-zero exit code, and `-ReportOnly $false` no longer
  produces an opaque binding error after the download

Main script:

- **Windows Update cache was wiped right after updates were downloaded.** Payloads
  waiting for a reboot live in that folder, so the run reported freed gigabytes that had
  to be downloaded all over again
- **The Recycle Bin was read with the wrong column**: index 2 is "Date deleted", not
  "Size", so the fallback parsed a date as a size. Emptiness is now decided by item
  count - a size of zero can equally mean "the shell would not say"
- **Path protection did not normalize**, so `C:\PROGRA~1` and `C:\Windows\..\Windows`
  bypassed it entirely
- **Empty environment variables produced dangerous paths**: under SYSTEM
  `"$env:LOCALAPPDATA\Temp"` collapses to `\Temp`, which resolves against the current
  drive, and an empty `$env:TEMP` made the whole temp cleanup throw
- **DISM exit code 3010** ("success, reboot required") was reported as a warning and
  never set the reboot flag, painting successful runs yellow; code 87 was labelled
  "cleanup not needed" when it actually means an invalid parameter
- **`pnputil` output was merged with stderr** before being cast to XML, so a single
  warning line made driver store cleanup fail silently every week
- **Driver packages were grouped by INF name alone.** Generic names are shipped by
  several vendors, so one vendor's package could be declared superseded by another's.
  Now grouped by INF plus provider plus class
- **PSWindowsUpdate version detection returned an array** with two copies installed, and
  the version threshold it compared against never existed. Capability is now queried
  from the cmdlet itself
- **Update search errors were only reported when zero updates were found**, so a failed
  system search next to a successful driver search looked like a clean run
- **DISM and Disk Cleanup results were missing from "Space freed"** entirely - the two
  most productive steps of a run. Free space is now measured around them
- `Format-FileSize` uses the invariant culture (ru-RU produced a no-break space that
  broke parsing of our own output), handles terabytes and negative values
- Category breakdown shows the remainder instead of silently truncating to five rows
- Process kills now terminate the whole tree, so a killed winget does not leave an
  installer running against the system
- Removed dead code: an unused `-RemoveFolder` parameter, a "MEF Cache" section pointing
  at a folder Visual Studio never creates, a duplicate DNS flush, an empty Firefox entry

### Fixed (third pass: MyAI-dtx8, "group A" of the remaining audit)

- **`Test-InternetConnection` ran twice per update phase**, up to 15s each on an
  offline machine. Memoized for the run
- **`Write-Log` reopened, appended to and closed the log file on every single call**
  (hundreds per run). A persistent `StreamWriter` is kept open instead, with the same
  per-line durability
- **`Show-DiskSpaceReport` could not tell "nothing above 100 MB" from "could not
  check"** - both looked identical when a folder walk hit an access error
- **`New-SystemRestorePoint` and the Windows Update search had no timeout** - VSS and a
  stuck WU agent could hang the whole script forever, fatal for an unattended nightly
  stand run. `Install-WindowsUpdate` itself is deliberately left unwrapped: killing that
  job would not necessarily cancel the in-flight WU agent call
- **`ConvertFrom-HumanReadableSize` failed on real-world localized input**: a
  space-grouped thousands separator did not match at all, `"1.234,5 MB"` (EU
  dot-thousands/comma-decimal) threw an unhandled exception instead of returning 0, the
  word form of bytes and `MiB`/`GiB`-style binary units were not recognized
- **`Remove-FilesByPattern` was the only delete path with no protected-path check and no
  age filter** - safe today because its one caller passes a single fixed pattern, but a
  latent risk for the next one. Now mirrors `Remove-FolderContent`'s guards
- **`Show-FinalStatistics` ran inside `Start-WinClean`'s `finally` block with no
  exception boundary** - a divide-by-zero from an unusual drive provider would have
  replaced whatever error the run was already reporting
- The script now **exits 1 when the run logged any errors** - it used to always exit 0
- `Get-RedundantDriverPackage` **hashed every FileRepository folder (700-1500 on a
  typical machine) before knowing whether there was anything to remove.** Candidate
  selection now runs first from pnputil's own metadata alone, and the FileRepository
  walk (needed to size each candidate) stops as soon as every candidate is matched
  instead of always hashing the whole store. Deletion accuracy is unaffected -
  `pnputil /delete-driver` has always worked from the package's own Oem id, never from
  this size-reporting map
- Ambiguous-width `↑`/`✗` in the final summary box replaced with ASCII, the same fix
  `⚠` already got in v2.14
- Nightly stand: the Telegram bot token no longer sits in `curl`'s argv (readable via
  `ps aux` on a shared host) - a `curl -K` config file keeps it out of the process
  arguments. The "no stand configs found" branch now sends a Telegram alert before
  exiting instead of failing silently exactly when the channel is needed most. The
  gateway container id and its SOCKS proxy addresses moved out of the (public) repo
  into the gitignored stand config

### Fixed (fourth pass: MyAI-dtx8, "group B" - the highest-risk item of the audit)

- **`Remove-FolderContent` walked the folder it was cleaning three to four full times**
  (size before, the age filter's own recursive check, the delete, size after) - the
  single largest performance item the audit found, and it runs roughly 35 times per
  run, including against multi-gigabyte TEMP and SoftwareDistribution. One enumeration
  pass now decides eligibility and measures size together; after deletion, each
  candidate is checked individually instead of re-walking the whole folder - fully
  gone contributes its pre-measured size, a directory that only partially emptied (a
  locked file survives inside it) gets re-measured on its own, scoped to just that
  subtree. A mutation test proved this specific accuracy path had no coverage of its
  own - removing it left the whole suite green - so it now has a dedicated one:
  a directory with one locked file and one free file inside must report exactly the
  free file's size, not the whole directory and not zero
- Removed the `-RemoveFolder` switch: dead since at least v2.16 (no caller left), and
  it would have kept a second, untested code path alive through this rewrite for
  nothing
- **`Get-FolderSize` wrapped every file in a full PSObject** (ETS properties,
  formatting metadata) just to read one `Length` value - noticeable on folders with
  tens of thousands of small files (npm/pip caches, the driver store). Walks the tree
  with the raw .NET enumerator instead, and deliberately skips reparse points while
  doing it - following a junction while summing could double-count the same bytes or
  loop on a cyclic one, something the old `Get-ChildItem -Recurse` call never guarded
  against
- **`Clear-EventLogs` spawned a separate `wevtutil` process per log** (30-80ms each,
  100-300 eligible logs on a typical run). Replaced with `EventLogSession.ClearLog`,
  the in-process .NET API `wevtutil` itself calls
- **The 9 top-level phases of a run shared one `try/catch`**, so an exception in phase
  3 silently skipped every phase after it - Developer Cleanup, Docker/WSL, Visual
  Studio, Deep System Cleanup, the disk space report, Telemetry - with only a generic
  "Critical error" line to show for it. Each phase now has its own boundary and is
  recorded in the result JSON as `PhasesCompleted`/`PhasesFailed`, so an automated
  stand can tell "everything ran" from "phase 6 threw and the rest are just missing"

### Changed

- Self-update check is now gated by `-SkipUpdates`, and the disk space report by
  `-SkipCleanup` - both used to run regardless
- Driver store cleanup runs before DISM, so the component store pass reclaims what it
  leaves behind in the same run instead of a week later
- A stale result JSON is deleted at startup, and an aborted run records why - automation
  could previously read the previous run's file as the current outcome

### Tests

- 268 Pester tests (was 222 earlier in 2.17, 141 in 2.15). The 46 new tests close part
  of a coverage gap the second audit pass found: 39 functions with no behavioral test at
  all, including 8 that delete files. `Get-SupersededDriverCandidate` (the pure
  candidate-selection logic split out of `Get-RedundantDriverPackage` for exactly this)
  gets fixture-based unit tests; the 8 deleting functions get sandboxed integration
  tests where that is safe, and fixture-shadowed tests (fake `pnputil.exe`/`docker`/
  `wsl`/etc. functions swapped in after dot-sourcing) where the real call touches OS
  state a test must not - the real Recycle Bin, the real Event Log service, the real
  driver store, real System Restore. That remaining destructive surface needs the
  Proxmox stand for real coverage, same as always
- **The helper test suite now dot-sources WinClean.ps1 instead of testing pasted copies
  of its functions.** The copies were a tautology - a bug in the product could not fail
  them - and they had already drifted apart from it, which the change immediately
  exposed
- Regex-based tests are scoped to the function under test. Verified case: the TEMP age
  filter test was matching an identical string in the kernel dump cleanup, so it passed
  with the filter deleted. One test could never match at all
- Skipped tests now fail the build and the release gate: the integration suite silently
  skipped itself without administrator rights, leaving a green run that verified nothing
- The stand verifies that the result JSON belongs to the current run, fails on
  unexpected warnings, and requires a preview run to free exactly zero bytes
- CI lints and syntax-checks `get.ps1`, `install.ps1`, `tools/` and `tests/` - previously
  only the main script - and runs the smoke test

---

## [2.16] - 2026-07-20

### Added

- **Driver store cleanup**: removes superseded third-party driver packages. A package is deleted only when no device is bound to it **and** a newer version of the same INF is installed, so drivers for temporarily unplugged hardware are preserved. `pnputil /force` is never used. Measured 451.8 MB across 31 packages on the author's workstation (one Bluetooth INF was present in nine versions)
- **Disk space report**: shows large consumers that cleanup deliberately leaves alone - MSI cache (`C:\Windows\Installer`, required for uninstall and repair), search index, `hiberfil.sys`, page file and shadow copies. On the author's machine this surfaced 51 GB of hibernation file and 10.7 GB of search index that no cleanup would ever have explained
- **Kernel dump cleanup**: deletes `LiveKernelReports\*.dmp` older than 30 days. Nothing in Windows cleans these up - an 8.99 GB watchdog dump had been sitting untouched for 18 months
- `ControlledFolderAccess` field in the result JSON

### Fixed

- **Delivery Optimization cache was measured at the wrong path**: the `ProgramData` location does not exist on Windows 11, so a 7.37 GB cache was reported as "0 B" both in `-ReportOnly` and in the freed-space statistics. The cache lives under the NetworkService profile; the old path is kept as a fallback for earlier builds
- **Temp cleanup deleted files of running applications**: entries younger than one day are now skipped (`-MinAgeDays`). `-ReportOnly` measures by the same rule, so the preview no longer promises more than the run deletes
- **Windows Update cache was cleaned while the service still held it**: a failed `Stop-Service` was swallowed silently; the script now waits for the Stopped state and warns if a service is still running
- **Controlled Folder Access was invisible**: when enabled, Defender blocks deletions without raising an error, so the log reported success while nothing was freed. A warning is now emitted up front
- **Disk Cleanup category list did not match the registry**: three handlers never existed on Windows 11 (`Memory Dump Files`, `Windows Error Reporting Archive/Queue Files`) and were silently skipped. Replaced with the real `Windows Error Reporting Files`, plus `Device Driver Packages`, `D3D Shader Cache`, `Language Pack` and four others. `DownloadsFolder` is deliberately excluded - it is the user's Downloads folder
- **Registry cleanup missed leftover flags**: `StateFlags9999` was removed only for the current category list, leaving flags from interrupted runs behind forever. Four such leftovers were found on a live machine; every handler is now swept
- **Disk Cleanup timed out on every run**: the 420 second limit was too short for a workstation with a large component store. Raised to 900 seconds, and exceeding it is no longer counted as a warning - cleanmgr keeps working after the script stops waiting
- **winget exit codes were printed as bare numbers**: `-1978335188` now reads as `0x8A15002C - some applications failed to upgrade`. `0x8A15002B` ("nothing to upgrade") is no longer reported as a warning at all
- **Progress bars stayed on screen under the summary**: the script closed two activity names that never existed while using seven real ones. All are closed now, including foreign bars from other cmdlets

### Documentation

- Removed 23 em dashes from README, README_RU, CHANGELOG and CONTRIBUTING
- Test counters corrected to the actual number (CONTRIBUTING claimed 94, CHANGELOG claimed 139)
- SECURITY.md: dropped the false claim that releases are signed, documented the SHA256 release verification and protected install location added in 2.15
- CLAUDE.md: section map and versioning checklist rebuilt from the real file

### Tests

- 187 Pester tests (was 141): 44 new validation tests covering every fix and feature above, plus an integration test proving that freshly written temp files survive cleanup

---

## [2.15] - 2026-07-18

### Fixed
- **Bootstrap parameter passthrough**: `get.ps1` initially forwarded WinClean parameters by splatting a string array, which PowerShell binds POSITIONALLY - `-ReportOnly` could silently become the `LogPath` value and an intended dry run turned into a real maintenance run. Arguments are now parsed into named-parameter (hashtable) splatting, and WinClean itself declares `PositionalBinding = $false` so stray positional arguments fail loudly instead of binding to string parameters

### Added
- **`-ResultJsonPath` parameter**: writes a machine-readable run summary (version, duration, per-category freed bytes, warning/error counts, reboot flag) - the foundation for automated verification in CI and on test stands

- **One-command run** (`get.ps1`): `irm .../get.ps1 | iex` on any machine with PowerShell 7.1+ and admin rights - checks prerequisites with friendly errors, downloads the latest GitHub Release (SHA256-verified when the release publishes a hash, fail-closed - no fallback to mutable branches) and runs it. Parameter passthrough via the documented scriptblock pattern

- **One-command install/update** (`install.ps1`): `irm .../install.ps1 | iex` (elevated) - installs or updates WinClean into the admin-protected `%ProgramFiles%\WinClean` (an elevated shortcut must not point at a user-writable file) and creates a desktop shortcut with the "Run as administrator" flag set (elevation on double-click)

- **Integration test suite** (`tests/Integration.Tests.ps1`, 24 tests): real cleanup functions run against a sandboxed fake filesystem in a child process with redirected environment variables - verifies what actually gets deleted and what must survive (active log, protected paths, browser profile data). 141 Pester tests total

- **Smoke runner** (`tools/Invoke-SmokeTest.ps1`): safe ReportOnly run with automated verification of exit code, result JSON and console box geometry (`tools/BoxGeometry.ps1` catches misaligned frames and foreign output inside boxes automatically)

- **Proxmox test stand** (`tools/proxmox/`): full-system test cycle on a disposable Windows 11 VM - rollback to baseline snapshot, boot, deliver script (local working tree or GitHub), real run, artifact collection and assertions over qemu-guest-agent. Stand infrastructure config stays out of the repository

- **Nightly stand matrix** (`tools/proxmox/Invoke-NightlyStand.ps1` + `Deploy-StandRunner.ps1`): cron-driven nightly Full runs on the Proxmox host itself (pwsh on Linux, `SshHost='local'` mode) across all configured stand VMs, with a Telegram summary (direct/SOCKS transport fallback) and artifact retention. `New-StandVM.ps1` can now convert a clone's locale (`ConvertLocaleTo`, e.g. en-US) for a locale test matrix

---

## [2.14] - 2026-07-18

### Fixed
- **Log file survival**: the log file (stored in `%TEMP%` by default) was deleted by the script's own temp cleanup - everything logged before `Clear-TempFiles` was silently lost every run. The active log is now excluded from cleanup (`Remove-FolderContent -ExcludeFile`)

- **npm cache path**: npm v7+ stores its cache in `%LOCALAPPDATA%\npm-cache`, the script only checked `%APPDATA%\npm-cache` - npm cleanup silently did nothing on modern systems. Both paths are handled now

- **Firefox cache path**: `cache2`/`startupCache` live under `%LOCALAPPDATA%\Mozilla\Firefox\Profiles`, the script iterated `%APPDATA%` (roaming profile, no cache there) - Firefox cleanup silently did nothing. Both roots are scanned now

- **Localized size parsing**: `ConvertFrom-HumanReadableSize` only understood Latin units (`KB/MB/GB`). Shell `GetDetailsOf` fallback (Recycle Bin statistics) returns localized strings on non-English Windows (e.g. `1,52 МБ` with no-break space) which parsed as 0. Cyrillic units and no-break spaces are normalized now

- **Restore points silently not created**: Windows skips restore point creation if one was made within the last 24 hours (`SystemRestorePointCreationFrequency` default), while the script reported SUCCESS. The limit is now lifted temporarily for the script's own checkpoint call and restored afterwards

- **winget update count**: when winget prints a second table ("require explicit targeting"), its header and rows were counted as available updates. Parsing now stops at the end of the first table

- **Storage Sense with disabled task**: if the StorageSense scheduled task is disabled, the script waited the full 120 s timeout and logged a false warning on every run. It now falls back to Disk Cleanup immediately

- **Dead connectivity probe**: `winget.azureedge.net` no longer resolves (CDN retired) - replaced with `cdn.winget.microsoft.com`

- **UI fixes**: misaligned right border of the "UPDATE AVAILABLE" box (inner width 63 vs 66); ghost character left by the Windows.old countdown when seconds dropped to single digits; ambiguous-width `⚠` glyph replaced with `!` inside the statistics box

- **Dead code**: removed unused `$statusIcon` and `$dockerInfo` variables

- **Docker reclaimed-space parsing**: `-match` against an array does not populate `$Matches` in PowerShell - the reclaimed size could be read from a stale value. Output is now joined via `Out-String` before matching, and `docker system prune` exit code is checked

- **Windows.old removal on non-English Windows**: `icacls ... /grant Administrators:F` used the localized group name and failed e.g. on Russian Windows ("Администраторы"). Now uses the well-known SID `*S-1-5-32-544`

- **Windows Update search errors**: a failed update search was indistinguishable from "no updates" and reported as success. Search errors are now captured via `-ErrorVariable` and reported as a warning

- **Statistics accuracy**: locked single files (e.g. `IconCache.db` held by Explorer) and Recycle Bin items that failed to delete are no longer counted as freed space; unexpected DISM exit codes now count as warnings in the final status

- **Custom log path**: `-LogPath` pointing into a non-existent directory is now created at startup instead of silently failing to log

### Improved
- **DISM component cleanup**: the component store is analyzed first (`/AnalyzeComponentStore /English`); the expensive `/StartComponentCleanup /ResetBase` pass (5-15 min) is skipped when DISM reports cleanup is not needed. DISM output is redirected to keep the console clean

- **Event logs cleanup**: only enabled, non-empty Administrative/Operational logs are cleared (~120 instead of ~1200 channel attempts) - much faster and no more chronic partial-failure warnings

- **Delivery Optimization cache**: cleared via the supported `Delete-DeliveryOptimizationCache` cmdlet (raw folder deletion usually failed silently on service-owned files), with folder cleanup as fallback

- **Safer Disk Cleanup fallback**: removed `Previous Installations` (Windows.old deletion must go through the interactive confirmation) and `Windows ESD installation files` (needed for "Reset this PC") from cleanmgr categories

- **winget hardening**: upgrade check now runs with `--accept-source-agreements --disable-interactivity` (no interactive prompts / progress junk in captured output)

### Added
- **Opera GX** cache cleanup; Opera/Opera GX caches also looked up under `%LOCALAPPDATA%` (where Chromium disk caches actually live)
- **uv cache** cleanup (`%LOCALAPPDATA%\uv\cache`)
- **npm legacy cache**: when both `%LOCALAPPDATA%` and `%APPDATA%` npm-cache folders exist, the legacy one is cleaned too
- **21 new Pester tests** (115 total): localized size parsing (Cyrillic units, NBSP) and regression tests for all v2.14 fixes

---

## [2.13] - 2026-01-18

### Added
- **Pester test suite**: Comprehensive testing framework for CI/CD
  - `tests/Helpers.Tests.ps1`: 52 unit tests for helper functions (Format-FileSize, ConvertFrom-HumanReadableSize, Get-FolderSize, Test-PathProtected, etc.)
  - `tests/Fixes.Tests.ps1`: 42 validation tests for all v2.13 fixes
  - CI workflow updated with Pester job (runs after lint and syntax checks)
  - **94 tests total**, all passing ✅

### Fixed
- **Docker statistics parsing**: Fixed regex to support both "reclaimed X" and "Total reclaimed space: X" output formats
  - Docker cleanup now correctly reports freed space in all Docker versions

- **Event logs WarningsCount**: Fixed missing `WarningsCount++` when some event logs fail to clear
  - Previously the warning was logged but not counted in final statistics

- **Windows Update false success**: Added null-check for `Install-WindowsUpdate` results
  - Prevents misleading "All 0 updates installed successfully" when module returns null

- **Temp files deduplication**: Fixed duplicate processing when `$env:TEMP` equals `$env:LOCALAPPDATA\Temp`
  - Paths are now normalized and deduplicated before cleanup

- **Browser cache negative values**: Fixed potential negative freed space calculation
  - Uses `[math]::Max(0, ...)` to prevent incorrect statistics when browser recreates files during cleanup

### Improved
- **Get-FolderSize performance**: Added `-File` flag to `Get-ChildItem` to skip directories
  - Significantly faster on large directory trees

- **Docker cleanup efficiency**: Removed redundant `docker builder prune -f` command
  - Build cache is already cleaned by `docker system prune -f`

- **Recycle Bin size fallback**: Added `GetDetailsOf` fallback when `ExtendedProperty("System.Size")` is unavailable
  - More reliable size calculation across different Windows configurations

- **Disk Cleanup registry cleanup**: StateFlags9999 are now removed from registry after cleanmgr execution
  - Uses `try/finally` to ensure cleanup even if cleanmgr times out

---

## [2.12] - 2026-01-17

### Fixed
- **PowerShell 7.4+ compatibility**: Removed deprecated `-UseBasicParsing` parameter from `Invoke-WebRequest`
  - This parameter was removed in PS 7.4 and caused errors during PSGallery connectivity check
  - Now works correctly on all PowerShell 7.x versions

- **DISM ReportOnly accuracy**: ReportOnly mode now correctly shows `/ResetBase` flag
  - Added warning that `/ResetBase` removes ability to uninstall updates
  - Previously the preview message didn't include `/ResetBase` which was misleading

- **AppUpdatesCount accuracy**: Fixed inflated statistics when winget fails
  - `AppUpdatesCount` is now only incremented when `winget upgrade` succeeds (exit code 0)
  - Previously showed available updates count even when installation failed

### Added
- **Improved space freed statistics**:
  - Docker cleanup: Now parses `docker system prune` output and adds reclaimed space to statistics
  - WSL compaction: Now tracks freed space by category ("WSL")
  - Recycle Bin: Now measures size before cleanup and shows in both ReportOnly preview and results
  - npm cache: Now tracks size freed via `npm cache clean --force`

- **New helper functions**:
  - `ConvertFrom-HumanReadableSize`: Converts strings like "2.5 GB" to bytes (inverse of `Format-FileSize`)
  - `Get-RecycleBinSize`: Measures total size of Recycle Bin items via Shell.Application COM

### Improved
- **ReportOnly mode**: Recycle Bin now shows actual size instead of generic "Would clean: Recycle Bin"

---

## [2.11] - 2026-01-17

### Fixed
- **Version display bugs**: Fixed hardcoded version strings that showed v2.9 instead of current version
  - Banner now uses dynamic `$script:Version` variable
  - Log file header now uses dynamic version
  - Removed outdated version comments from code

- **Outdated comment**: Updated comment in `Clear-WinCleanRecycleBin` that incorrectly stated name collision issue

### Added
- **Operation timeouts to prevent script hangs**:
  - `winget upgrade --include-unknown` (check): 5-minute timeout
  - `winget upgrade --all` (install): 20-minute timeout
  - `winget source update`: 2-minute timeout (via background job)
  - `DISM /StartComponentCleanup`: 15-minute timeout
  - `Storage Sense`: Added force stop when timeout exceeded

### Improved
- **Docker detection**: `$LASTEXITCODE` now captured immediately after command execution
- **Browser cache statistics**: Added null-coalescing to prevent calculation errors
- **PowerShell path**: Removed hardcoded path, now uses system PATH lookup
- **Code quality**: Added explanatory comments to intentionally empty catch blocks

---

## [2.10] - 2026-01-17

### Added
- **Auto-update check at startup**: Script now checks PowerShell Gallery for newer version
  - Runs after reboot check, before main operations
  - Shows current vs available version with visual comparison
  - Prompts user to update if newer version available
  - Performs update via `Update-Script` if user confirms
  - Shows manual installation instructions if script was downloaded manually (not via PSGallery)
  - Respects `-ReportOnly` mode (informs but doesn't update)
  - Gracefully skips in non-interactive environments

### Technical
- `Test-ScriptUpdate` function: compares `$script:Version` with PSGallery version
- `Invoke-ScriptUpdate` function: handles UI, user prompt, and update execution
- Uses existing `Test-PSGalleryConnection` for connectivity check

---

## [2.9] - 2026-01-17

### Fixed
- **PSWindowsUpdate installation hangs**: Script could hang indefinitely when installing PSWindowsUpdate module
  - Added TLS 1.2 enforcement at script start (required by PowerShell Gallery)
  - Added `Test-PSGalleryConnection` function to pre-check PowerShell Gallery availability
  - Added `Install-ModuleWithTimeout` function with 120-second timeout
  - Added `Install-PackageProviderWithTimeout` function with 60-second timeout for NuGet
  - Improved error messages with manual installation instructions
  - Clear Write-Progress before module installation to prevent UI artifacts

### Added
- `Test-PSGalleryConnection` helper function for PSGallery availability check
- `Install-ModuleWithTimeout` helper function for timeout-wrapped module installation
- `Install-PackageProviderWithTimeout` helper function for timeout-wrapped provider installation

---

## [2.8] - 2026-01-16

### Fixed
- **Disk Cleanup hangs**: Improved cleanmgr.exe handling to prevent long waits after cleanup completes
  - Reduced timeout from 10 minutes to 7 minutes
  - Replaced `-NoNewWindow` with `-WindowStyle Hidden` for more reliable operation
  - Added explicit `HasExited` loop instead of `Wait-Process` for better control
  - Added progress logging every minute ("Disk Cleanup still running... (60 seconds)")

---

## [2.7] - 2026-01-16

### Fixed
- **UI: Header frame color**: Top border (╔═╗) and side borders (║) of header now use Cyan like the rest of the frame
- Status text (COMPLETED SUCCESSFULLY / WITH WARNINGS / WITH ERRORS) remains colored (Green/Yellow/Red) to indicate completion status

---

## [2.6] - 2026-01-16

### Fixed
- **UI: Frame color consistency**: All parts of the final statistics frame now use Cyan color (separator line between main stats and categories was DarkGray)
- **UI: Label/value spacing**: Added 2-space gap between label and value to prevent merging (e.g., "installed:Windows:" → "installed:  Windows:")
- **UI: Category alignment**: Category names (Temp, System, etc.) now right-aligned using `PadLeft` so colons align with "Updates installed:"

### Improved
- **Code structure**: Moved `$labelWidth` to parent scope for reuse in both `Write-StatLine` and category formatting

---

## [2.5] - 2026-01-16

### Fixed
- **UI: Subsection lines width**: Gray subsection lines (`└────`) now extend to match TITLE frame width (70 characters instead of 67)
- **UI: Final statistics alignment**: Replaced emoji icons (⏱🗑💾) with ASCII characters (`>`) to fix border misalignment caused by emoji taking 2 visual positions
- **UI: Write-StatLine formula**: Corrected width calculation formula (`-5` → `-3`) for proper value padding

---

## [2.4] - 2026-01-16

### Improved
- **UI: Consistent left indent**: All output now has 2-space left margin, matching the banner style
- **UI: Major section frames**: TITLE sections (WINDOWS UPDATE, SYSTEM CLEANUP, etc.) now have full box frames like the banner, in Magenta color
- **UI: Subsections preserved**: Original `┌─ Title` / `└────` style kept for subsections
- **UI: Enhanced final statistics**:
  - Header color reflects status: Green (success), Yellow (warnings), Red (errors)
  - Status indicators for each metric (duration, updates, freed space, disk)
  - Space freed highlighting: Green >1GB, Yellow >100MB, White otherwise
  - Disk space warning: Red <10%, Yellow <20%

### Changed
- **Removed auto-close timeout**: Window now waits indefinitely for keypress instead of 60-second timeout - users won't miss results if distracted

---

## [2.3] - 2026-01-16

### Fixed
- **Critical: TotalFreedBytes always showed 0**: The "Space freed" counter in final statistics was always displaying 0 bytes regardless of actual cleanup
  - **Root cause**: `[System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, ...)` doesn't work with hashtable elements in PowerShell - `[ref]` creates a temporary copy instead of referencing the actual hashtable value
  - **Solution**: Replaced all 6 occurrences with simple `+=` operator - the synchronized hashtable already provides thread-safety for basic operations
  - **Impact**: All previous versions (2.0-2.2) had this bug; users saw "Space freed: 0 Bytes" even when gigabytes were actually cleaned

---

## [2.2] - 2026-01-15

### Fixed
- **TcpClient resource leak**: Now properly closed in `finally` block to prevent socket exhaustion on repeated connection failures
- **Code region markers**: Fixed 8 misplaced `#region` tags that should have been `#` (plain comment) - now IDE can properly fold code sections
- **Banner ASCII art**: Changed from "DREAM" to "CLEAN" to match the script name

---

## [2.1] - 2026-01-15

### Fixed
- **Clear-EventLogs precision**: Now uses exact match (`-ne 'Security'`) instead of `-notmatch 'Security'` to only preserve the main Security log (was incorrectly skipping all logs with "Security" in the name)
- **Browser profile cache cleanup**: Additional Chrome/Edge profiles now get full cache set (Cache, Code Cache, GPUCache, Service Worker) - previously only Cache was cleaned
- **Update-Applications error tracking**: Now increments `ErrorsCount` when no internet connection (was only logging error without counting)
- **Roslyn Temp cleanup**: File patterns (`*.roslynobjectin`) now handled correctly using new `Remove-FilesByPattern` function (was passing file paths to directory cleanup function)
- **winget update count**: Now works with any source, not just `winget|msstore` (supports custom/corporate repositories)
- **Non-console environment safety**: Added `Test-InteractiveConsole` function to prevent `[Console]::KeyAvailable` exceptions in Scheduled Tasks, ISE, or remote sessions
- **Telemetry edition detection**: Uses `EditionID` from registry instead of localized `Caption` (works on non-English Windows)
- **Final statistics box alignment**: Fixed inconsistent line widths causing visual glitches in the output table

### Added
- `Test-InteractiveConsole` helper function for safe console detection
- `Remove-FilesByPattern` helper function for cleaning file patterns (vs directories)

---

## [2.0] - 2026-01-15

### Fixed
- **Test-InternetConnection timeout**: Now uses `TcpClient` with 3-second timeout instead of `Test-NetConnection` (fixes VPN/unstable connection hangs)
- **Clear-EventLogs accuracy**: Now checks `$LASTEXITCODE` after each `wevtutil cl` call (was counting failed clears as successful)
- **winget ExitCode strictness**: Any non-zero exit code is now treated as error (was only erroring if exit code ≠ 0 AND output was empty)
- **Storage Sense language-independence**: Uses `Get-ScheduledTask` cmdlet instead of `schtasks` (works on any Windows language)
- **Storage Sense completion detection**: Tracks `Running → Ready` state transition (avoids false positive when task hasn't started yet)
- **ReportOnly mode purity**: No longer installs PSWindowsUpdate/NuGet modules (truly "no system changes" mode)

### Removed
- **DriverUpdatesCount field**: Removed unused field from Stats (was never populated or displayed)

---

## [1.9] - 2026-01-15

### Fixed
- **Progress bar accuracy**: `TotalSteps` now calculated dynamically based on active skip flags (`-SkipUpdates`, `-SkipCleanup`, `-SkipDevCleanup`, etc.)
- **winget ReportOnly**: `winget source update` now skipped in ReportOnly mode (was modifying system state during dry run)
- **winget ExitCode**: Added error handling when `winget upgrade` check fails (was showing false "all up to date" on errors)
- **winget --include-unknown**: Now used consistently in both count check and actual upgrade (count could previously differ from installed)
- **Browser cache statistics**: Now measures actual freed space by comparing before/after sizes (was reporting estimated size even if files were locked)
- **Storage Sense completion**: Now polls task status until completion instead of fixed 15-second sleep
- **DNS cache flush**: Now logs WARNING on unexpected exit code instead of false SUCCESS
- **WSL/Docker VHDX compaction**: Now finds and compacts all VHDX files directly, regardless of WSL distro list (Docker-only systems now work)
- **Update-Progress timing**: Moved calls after skip flag checks so progress percentage is accurate

---

## [1.8] - 2026-01-15

### Fixed
- **CRITICAL**: `Start-WinClean` and `Show-FinalStatistics` now use `$script:LogPath` instead of `$LogPath` parameter (fixes crash when `-LogPath` not specified)
- **Version consistency**: All version references (SYNOPSIS, NOTES, banner, log) now unified to single source
- `Clear-BrowserCaches`: Browser cache cleanup now properly tracked in freed space statistics (was missing from totals)
- `TotalSteps` corrected from 12 to 7 (progress bar now reaches 100%)
- `Update-Applications`: Winget update detection now language-independent (uses table separator instead of text phrases)

---

## [1.7] - 2026-01-15

### Added
- **Improved internet connectivity check**: HTTPS endpoint checks (Microsoft, GitHub, winget) with ICMP fallback
- More reliable detection when ICMP is blocked but internet is available

### Fixed
- `Show-Banner`: Display correct log path using `$script:LogPath` instead of parameter
- `Clear-SystemCaches`: ReportOnly mode now shows file sizes for single file caches (IconCache.db)
- `Clear-SystemCaches`: Single file cache sizes now counted in total freed statistics

---

## [1.6] - 2026-01-15

### Added
- Pause at end of execution: window stays open 60 seconds or until any key is pressed
- Prevents window from closing before user can read final statistics

### Fixed
- Visual glitch: clear progress bar before DISM output to prevent overlay artifacts

---

## [1.5] - 2026-01-15

### Fixed
- Progress bar now properly cleared before DISM cleanup to prevent visual overlap

---

## [1.4] - 2026-01-15

### Fixed
- `Clear-PrivacyTraces`: Added `-Recurse` to `Remove-Item` to prevent confirmation prompts when cleaning Recent folder (AutomaticDestinations, CustomDestinations subfolders)

---

## [1.3] - 2026-01-15

### Fixed
- **CRITICAL**: Renamed `Clear-RecycleBin` to `Clear-WinCleanRecycleBin` to avoid infinite recursion (stack overflow) caused by name collision with built-in PowerShell cmdlet
- Function now uses fully qualified path `Microsoft.PowerShell.Management\Clear-RecycleBin`

---

## [1.2] - 2026-01-15

### Fixed
- `$script:LogPath` scope issue - logging now works correctly throughout the script
- `Clear-BrowserCaches` now properly respects `-ReportOnly` mode in parallel execution
- `Windows.old` path now uses `$env:SystemDrive` instead of hardcoded `C:`
- NuGet cleanup now only removes metadata caches (`v3-cache`, `plugins-cache`, `http-cache`), preserving the packages folder
- Gradle cleanup now only removes safe build caches, not downloaded dependencies
- Windows Update services now properly restart using `try/finally` block
- WSL `--list` output UTF-16LE parsing (removes null characters)

---

## [1.1] - 2026-01-14

### Added
- Initial public release
- Windows Update with driver support via PSWindowsUpdate
- Winget application updates
- Browser cache cleanup (Edge, Chrome, Firefox, Yandex, Opera, Brave)
- Developer cache cleanup (npm, pip, NuGet, Gradle, Cargo, Go)
- Docker cleanup and WSL2 VHDX compaction
- Visual Studio and JetBrains IDE cache cleanup
- Privacy traces cleanup (DNS cache, Run history, Recent documents)
- Optional Windows telemetry configuration
- System restore point creation
- Parallel execution with thread-safe statistics
- Colored console output with progress bar
- Detailed logging to file

---

## Legend / Обозначения

| English | Русский |
|---------|---------|
| **Added** - New features | **Добавлено** - Новые функции |
| **Changed** - Changes in existing functionality | **Изменено** - Изменения существующего функционала |
| **Deprecated** - Soon-to-be removed features | **Устарело** - Функции, которые будут удалены |
| **Removed** - Removed features | **Удалено** - Удалённые функции |
| **Fixed** - Bug fixes | **Исправлено** - Исправления ошибок |
| **Security** - Vulnerability fixes | **Безопасность** - Исправления уязвимостей |
