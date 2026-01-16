# Changelog / История изменений

All notable changes to WinClean will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.7] - 2025-01-16

### Fixed
- **UI: Header frame color**: Top border (╔═╗) and side borders (║) of header now use Cyan like the rest of the frame
- Status text (COMPLETED SUCCESSFULLY / WITH WARNINGS / WITH ERRORS) remains colored (Green/Yellow/Red) to indicate completion status

---

## [2.6] - 2025-01-16

### Fixed
- **UI: Frame color consistency**: All parts of the final statistics frame now use Cyan color (separator line between main stats and categories was DarkGray)
- **UI: Label/value spacing**: Added 2-space gap between label and value to prevent merging (e.g., "installed:Windows:" → "installed:  Windows:")
- **UI: Category alignment**: Category names (Temp, System, etc.) now right-aligned using `PadLeft` so colons align with "Updates installed:"

### Improved
- **Code structure**: Moved `$labelWidth` to parent scope for reuse in both `Write-StatLine` and category formatting

---

## [2.5] - 2025-01-16

### Fixed
- **UI: Subsection lines width**: Gray subsection lines (`└────`) now extend to match TITLE frame width (70 characters instead of 67)
- **UI: Final statistics alignment**: Replaced emoji icons (⏱🗑💾) with ASCII characters (`>`) to fix border misalignment caused by emoji taking 2 visual positions
- **UI: Write-StatLine formula**: Corrected width calculation formula (`-5` → `-3`) for proper value padding

---

## [2.4] - 2025-01-16

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
- **Removed auto-close timeout**: Window now waits indefinitely for keypress instead of 60-second timeout — users won't miss results if distracted

---

## [2.3] - 2025-01-16

### Fixed
- **Critical: TotalFreedBytes always showed 0**: The "Space freed" counter in final statistics was always displaying 0 bytes regardless of actual cleanup
  - **Root cause**: `[System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, ...)` doesn't work with hashtable elements in PowerShell — `[ref]` creates a temporary copy instead of referencing the actual hashtable value
  - **Solution**: Replaced all 6 occurrences with simple `+=` operator — the synchronized hashtable already provides thread-safety for basic operations
  - **Impact**: All previous versions (2.0-2.2) had this bug; users saw "Space freed: 0 Bytes" even when gigabytes were actually cleaned

---

## [2.2] - 2025-01-15

### Fixed
- **TcpClient resource leak**: Now properly closed in `finally` block to prevent socket exhaustion on repeated connection failures
- **Code region markers**: Fixed 8 misplaced `#region` tags that should have been `#` (plain comment) — now IDE can properly fold code sections
- **Banner ASCII art**: Changed from "DREAM" to "CLEAN" to match the script name

---

## [2.1] - 2025-01-15

### Fixed
- **Clear-EventLogs precision**: Now uses exact match (`-ne 'Security'`) instead of `-notmatch 'Security'` to only preserve the main Security log (was incorrectly skipping all logs with "Security" in the name)
- **Browser profile cache cleanup**: Additional Chrome/Edge profiles now get full cache set (Cache, Code Cache, GPUCache, Service Worker) — previously only Cache was cleaned
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

## [2.0] - 2025-01-15

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

## [1.9] - 2025-01-15

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

## [1.8] - 2025-01-15

### Fixed
- **CRITICAL**: `Start-WinClean` and `Show-FinalStatistics` now use `$script:LogPath` instead of `$LogPath` parameter (fixes crash when `-LogPath` not specified)
- **Version consistency**: All version references (SYNOPSIS, NOTES, banner, log) now unified to single source
- `Clear-BrowserCaches`: Browser cache cleanup now properly tracked in freed space statistics (was missing from totals)
- `TotalSteps` corrected from 12 to 7 (progress bar now reaches 100%)
- `Update-Applications`: Winget update detection now language-independent (uses table separator instead of text phrases)

---

## [1.7] - 2025-01-15

### Added
- **Improved internet connectivity check**: HTTPS endpoint checks (Microsoft, GitHub, winget) with ICMP fallback
- More reliable detection when ICMP is blocked but internet is available

### Fixed
- `Show-Banner`: Display correct log path using `$script:LogPath` instead of parameter
- `Clear-SystemCaches`: ReportOnly mode now shows file sizes for single file caches (IconCache.db)
- `Clear-SystemCaches`: Single file cache sizes now counted in total freed statistics

---

## [1.6] - 2025-01-15

### Added
- Pause at end of execution: window stays open 60 seconds or until any key is pressed
- Prevents window from closing before user can read final statistics

### Fixed
- Visual glitch: clear progress bar before DISM output to prevent overlay artifacts

---

## [1.5] - 2025-01-15

### Fixed
- Progress bar now properly cleared before DISM cleanup to prevent visual overlap

---

## [1.4] - 2025-01-15

### Fixed
- `Clear-PrivacyTraces`: Added `-Recurse` to `Remove-Item` to prevent confirmation prompts when cleaning Recent folder (AutomaticDestinations, CustomDestinations subfolders)

---

## [1.3] - 2025-01-15

### Fixed
- **CRITICAL**: Renamed `Clear-RecycleBin` to `Clear-WinCleanRecycleBin` to avoid infinite recursion (stack overflow) caused by name collision with built-in PowerShell cmdlet
- Function now uses fully qualified path `Microsoft.PowerShell.Management\Clear-RecycleBin`

---

## [1.2] - 2025-01-15

### Fixed
- `$script:LogPath` scope issue - logging now works correctly throughout the script
- `Clear-BrowserCaches` now properly respects `-ReportOnly` mode in parallel execution
- `Windows.old` path now uses `$env:SystemDrive` instead of hardcoded `C:`
- NuGet cleanup now only removes metadata caches (`v3-cache`, `plugins-cache`, `http-cache`), preserving the packages folder
- Gradle cleanup now only removes safe build caches, not downloaded dependencies
- Windows Update services now properly restart using `try/finally` block
- WSL `--list` output UTF-16LE parsing (removes null characters)

---

## [1.1] - 2025-01-14

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
