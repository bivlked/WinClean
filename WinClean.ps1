<#PSScriptInfo
.VERSION 2.21
.GUID 8f7c3b2a-1d4e-5f6a-9b8c-0d1e2f3a4b5c
.AUTHOR bivlked
.COMPANYNAME
.COPYRIGHT (c) 2026 bivlked. MIT License.
.TAGS Windows Cleanup Maintenance PowerShell Windows11 DevTools Docker WSL npm pip nuget
.LICENSEURI https://github.com/bivlked/WinClean/blob/main/LICENSE
.PROJECTURI https://github.com/bivlked/WinClean
.ICONURI https://raw.githubusercontent.com/bivlked/WinClean/main/assets/logo.svg
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
    v2.21: Self-update targeting and honest exit codes - the update could change a file that was not the one running and still report success; a missing winget or no connectivity no longer fails the run
    v2.20: Correctness and honesty round - a junction could bypass protected-path checks, four operations reported success while doing nothing, Storage Sense was unreachable so on machines where it works the slow Disk Cleanup no longer runs; where it fails, the new -SkipDiskCleanup is what removes the wait
    v2.19: Contract and documentation round - -SkipCleanup now skips ALL cleanup categories, result JSON gains a tri-state PhasesSkipped, AppUpdatesCount renamed to AppUpdatesOffered (offered, not installed), full docs overhaul
    v2.18: Correctness and hardening follow-up from external code review - diskpart failure detection, driver-store accounting, strict superseded-version rule, exact bootstrap host allowlist
    v2.17: Silent failure hardening - operations that quietly do nothing now say so instead of reporting success
    v2.16: Driver store cleanup, disk space report, kernel dump cleanup, 9 audit fixes (Delivery Optimization path, TEMP age filter, winget exit codes)
    v2.15: ResultJsonPath for automated testing, one-command install/run (get.ps1, install.ps1), integration test suite
    v2.14: Log persistence fix, correct npm/Firefox cache paths, localized size parsing, faster DISM/EventLogs, UI fixes
    v2.13: Statistics accuracy fixes, efficiency improvements, registry cleanup
    v2.12: PS 7.4+ compatibility, improved statistics (Docker/WSL/RecycleBin), ReportOnly accuracy
    v2.11: Added timeouts for winget/DISM operations, fixed version display, improved reliability
    v2.10: Added auto-update check at startup (checks PSGallery for new version)
    v2.9: Fixed PSWindowsUpdate installation hanging (TLS 1.2, timeouts)
.PRIVATEDATA
#>

<#
.SYNOPSIS
    WinClean - Ultimate Windows 11 Maintenance Script v2.21
.DESCRIPTION
    Комплексный скрипт для обновления и очистки Windows 11:
    - Обновление Windows (включая драйверы)
    - Обновление приложений через winget
    - Очистка системы, браузеров, кэшей разработчика
    - Очистка Docker/WSL
    - Очистка Visual Studio
    - Очистка DNS кэша и истории Run
    - Опциональная блокировка телеметрии Windows
    - Параллельное выполнение для максимальной скорости
    - Подробный цветной вывод + лог-файл
.NOTES
    Author: biv
    Version: 2.21
    Requires: PowerShell 7.1+, Windows 11, Administrator rights
    Changes in 2.21:
    - The self-update could update a DIFFERENT copy than the one running and report
      success - it asked whether a Gallery copy existed anywhere, not whether the
      running file was that copy
    - Several Gallery installations now disable the automatic update instead of
      changing one at random; the running path is printed so they can be told apart
    - Detection, updating and the printed advice work on a machine that has only
      PSResourceGet; an AllUsers install is no longer invisible
    - An update that reports success is verified against the version on disk
    - A missing winget, no internet connection and a failed self-update are warnings,
      not errors: the exit code no longer reports failure for a complete cleanup
    - Result JSON gains AppUpdatesStatus, and Aborted gains UpdatedAndExited
    Changes in 2.20:
    - SECURITY: a junction whose target is a protected root could be used as a cleanup
      root - the path check compared text and never resolved the link
    - Storage Sense was looked up at a path where it does not exist, so every run fell
      back to Disk Cleanup (15 of 18 minutes on a real workstation). Where Storage Sense
      itself fails, the fallback still runs - use -SkipDiskCleanup there
    - npm, event logs, privacy traces and winget source update no longer report success
      when they did nothing
    - Added -SkipDiskCleanup to skip only the slow Disk Cleanup step
    - Result JSON gains LoggingDegraded and DiskCleanupPending
    Changes in 2.19:
    - -SkipCleanup now skips the ENTIRE cleanup group (system, deep, developer,
      Docker/WSL, Visual Studio), matching the documented "skip all cleanup" contract.
      Previously it left developer/Docker/VS cleanup running (behavior change)
    - Result JSON gains a tri-state PhasesSkipped (dispatch status): a phase turned off
      by a skip flag is now recorded as skipped instead of completed
    - AppUpdatesCount renamed to AppUpdatesOffered - winget cannot confirm how many apps
      installed, so the summary reports the offered count honestly ("Apps: N offered")
    - Documentation overhaul: accurate feature list, docs/ deep-dive pages, SECURITY and
      CONTRIBUTING release-gate, SHA-pinned CI actions
    Changes in 2.18:
    - WSL/Docker VHDX compaction now detects a diskpart failure instead of reporting
      "no space saved", and a failed WSL shutdown skips compaction rather than
      touching a live disk
    - Driver store falls back to the repository delta whenever ANY removed package
      lacks a trusted per-package size, not only when the total is zero
    - Driver store "superseded" now requires a strictly newer version, never a mere
      newer date at the same version
    - The per-VHDX compaction failure is now counted as a warning
    - The one-line install scripts validate the download host against an exact
      allowlist instead of a broad *.github.com / *.githubusercontent.com suffix
    - Folder size measurement distinguishes an unreadable folder from an empty one
    Changes in 2.17:
    - Cleanups that free nothing from a non-empty folder now say so instead of
      staying silent, which was indistinguishable from "there was nothing to do"
    - Kernel dump and driver package removal failures are counted and reported
    - pnputil exit code is checked; a parse failure no longer looks like "nothing found"
    - Driver store falls back to measuring the repository when per-package sizes
      cannot be attributed, instead of reporting 0 B after a successful cleanup
    - Disk Cleanup verifies that categories were armed and checks its exit code
    - Browser caches are no longer reported as cleaned when nothing was freed
    - The temp age filter now fails closed: an unreadable subtree is kept, not deleted
    - Controlled Folder Access reports 'unknown' when the check itself fails
    - Downloaded-but-not-installed updates are no longer counted as installed
    Changes in 2.16:
    - Added driver store cleanup: removes superseded driver packages that no device
      uses and that have a newer version installed (451 MB on the author's machine)
    - Added disk space report: shows large areas cleanup deliberately never touches
      (MSI cache, search index, hiberfil.sys, shadow copies)
    - Added kernel dump cleanup for stale LiveKernelReports files (multi-gigabyte)
    - Fixed Delivery Optimization cache path - multi-gigabyte cleanups were reported as 0 B
    - Temp cleanup no longer deletes files younger than a day (running installers)
    - Windows Update cache cleanup now waits for the service to really stop
    - Warns when Controlled Folder Access may silently block deletions
    - Disk Cleanup category list reconciled with the registry; leftover StateFlags
      are now swept from every handler
    - winget exit codes are decoded instead of printed as a bare number
    - All progress bars are closed before the summary, including foreign ones
    Changes in 2.15:
    - Added -ResultJsonPath: machine-readable run summary (JSON) for automated
      testing, CI and VM test stands
    - Added get.ps1 (one-command run from the internet) and install.ps1
      (one-command install/update + elevated desktop shortcut)
    - Added integration test suite (sandboxed filesystem tests) and smoke runner
      with automated console box-geometry checking
    Changes in 2.14:
    - Fixed log file being deleted by the script's own temp cleanup (all entries
      logged before Clear-TempFiles were silently lost every run)
    - Fixed npm cache path for npm v7+ (LOCALAPPDATA\npm-cache; old APPDATA path kept as fallback)
    - Fixed Firefox cache path (cache2/startupCache live under LOCALAPPDATA, not APPDATA)
    - Fixed localized size parsing (Cyrillic units, no-break spaces) for Recycle Bin statistics
    - Fixed restore points silently not created due to the 24h system frequency limit
    - Fixed winget update count inflated by the "require explicit targeting" table
    - Fixed Storage Sense wasting 120s + false warning when the scheduled task is disabled
    - Fixed misaligned UPDATE AVAILABLE box and countdown ghost character
    - DISM: component store analyzed first (/English), cleanup skipped when not needed;
      DISM output redirected to keep console clean
    - Event logs: only enabled non-empty Administrative/Operational logs are cleared
      (much faster, no chronic partial-failure warnings)
    - Delivery Optimization cache cleared via supported Delete-DeliveryOptimizationCache cmdlet
    - Replaced dead connectivity probe winget.azureedge.net with cdn.winget.microsoft.com
    - Removed risky cleanmgr categories (Previous Installations, Windows ESD installation files)
    - Added Opera GX and uv cache cleanup; winget check hardened with --disable-interactivity
    - Removed dead code (unused statusIcon/dockerInfo variables)
    - Fixed Docker reclaimed-space parsing ($Matches after array -match) + exit code check
    - Fixed icacls on non-English Windows (SID S-1-5-32-544 instead of localized "Administrators")
    - Fixed failed Windows Update search being reported as "up to date"
    - Stats no longer count locked files / undeleted Recycle Bin items as freed
    - Custom -LogPath directories are created automatically
    Changes in 2.13:
    - Fixed Docker prune output parsing (supports "Total reclaimed space:" format)
    - Fixed WarningsCount not incrementing for event log failures
    - Fixed false "success" when Windows Update returns null results
    - Optimized Get-FolderSize with -File flag for better performance
    - Fixed temp path deduplication to avoid duplicate cleanups
    - Removed redundant docker builder prune (already included in system prune)
    - Fixed potential negative freed space in browser cache statistics
    - Added fallback for Recycle Bin size calculation via GetDetailsOf
    - Added registry cleanup for Disk Cleanup StateFlags after execution
    Changes in 2.12:
    - Fixed PS 7.4+ compatibility (removed deprecated -UseBasicParsing)
    - Fixed DISM ReportOnly to show /ResetBase and warning
    - Fixed AppUpdatesCount to only count successful updates
    - Added statistics for Docker, WSL, Recycle Bin, npm cache
    Changes in 2.11:
    - Fixed version display bugs (banner and log showed v2.9 instead of current version)
    - Added timeouts for winget/DISM operations to prevent script hangs
    - Added force stop for Storage Sense when timeout exceeded
    - Improved Docker detection and browser cache statistics reliability
    Changes in 2.10:
    - Added auto-update check: script checks PSGallery for newer version at startup
    - Added Test-ScriptUpdate function: compares local version with PSGallery
    - Added Invoke-ScriptUpdate function: prompts user and performs update if confirmed
    - Update check runs after reboot check, before main operations
    - Shows manual update instructions if script was downloaded manually (not via PSGallery)
    - Respects ReportOnly mode and non-interactive environments
    Changes in 2.9:
    - Fixed PSWindowsUpdate installation hanging: added TLS 1.2 enforcement
    - Added Test-PSGalleryConnection function: pre-checks PowerShell Gallery availability
    - Added Install-ModuleWithTimeout function: 120-second timeout for Install-Module
    - Added Install-PackageProviderWithTimeout function: 60-second timeout for NuGet provider
    - Improved error messages with manual installation instructions
    - Clear Write-Progress before module installation to prevent UI artifacts
    Changes in 2.8:
    - Fixed Disk Cleanup timeout: reduced from 10 minutes to 7 minutes
    - Fixed Disk Cleanup: replaced -NoNewWindow with -WindowStyle Hidden (more reliable)
    - Added progress logging every minute while Disk Cleanup is running
    - Replaced Wait-Process with explicit HasExited loop for better control
    Changes in 2.7:
    - Fixed UI: header frame (╔═╗║║) now uses Cyan like the rest of the frame
    - Status text (COMPLETED SUCCESSFULLY) remains colored (Green/Yellow/Red) for visual feedback
    Changes in 2.6:
    - Fixed UI: final statistics frame now uses consistent Cyan color throughout
    - Fixed UI: added 2-space gap between label and value (prevents "installed:Windows:" merging)
    - Fixed UI: category names (Temp, System) now right-aligned with PadLeft to match main labels
    - Refactored: $labelWidth moved to parent scope for reuse in category alignment
    Changes in 2.5:
    - Fixed UI: subsection gray lines now match TITLE frame width (70 chars)
    - Fixed UI: final statistics window alignment (emoji replaced with ASCII)
    - Fixed UI: Write-StatLine width formula corrected (-5 → -3)
    Changes in 2.4:
    - UI improvements: consistent left indent (2 spaces) throughout the script
    - UI improvements: major sections now have full frame (like banner)
    - UI improvements: subsections keep original style (┌─ Title / └────)
    - UI improvements: enhanced final statistics with status icons and colors
    - UI improvements: header color reflects completion status (green/yellow/red)
    - Removed 60-second auto-close timeout - window now waits indefinitely for keypress
    Changes in 2.3:
    - Fixed critical bug: TotalFreedBytes always showed 0 in final statistics
      Root cause: Interlocked.Add doesn't work with hashtable elements via [ref] in PowerShell
      Solution: Use simple += operator (synchronized hashtable handles thread-safety)
    Changes in 2.2:
    - Fixed TcpClient resource leak: now properly closed in finally block (prevents socket exhaustion)
    - Fixed code region markers: 8 misplaced #region tags corrected for proper IDE navigation
    - Fixed banner ASCII art: now displays "CLEAN" instead of incorrect "DREAM"
    Changes in 2.1:
    - Fixed Clear-EventLogs: exact match for Security log only (not all logs containing "Security")
    - Fixed browser cache cleanup: additional profiles now get full cache set (Code Cache, GPUCache, etc.)
    - Fixed Update-Applications: ErrorsCount++ now incremented when no internet
    - Fixed Roslyn Temp cleanup: file patterns now handled correctly (not just directories)
    - Fixed winget update count: works with custom sources (not just winget/msstore)
    - Fixed interactive prompts: safe defaults in non-console environments (Scheduled Tasks, ISE)
    - Fixed telemetry edition detection: uses EditionID registry (language-independent)
    - Fixed final statistics: consistent box width (no visual glitches)
    Changes in 2.0:
    - Fixed Test-InternetConnection: uses TcpClient with 3s timeout (no VPN hangs)
    - Fixed Clear-EventLogs: now checks $LASTEXITCODE for each wevtutil call
    - Fixed winget ExitCode: strict check (any non-zero = error, not just empty output)
    - Fixed Storage Sense: uses Get-ScheduledTask (language-independent status)
    - Fixed Storage Sense: detects actual completion (wasRunning -> Ready transition)
    - Fixed ReportOnly: no longer installs PSWindowsUpdate/NuGet modules
    - Removed unused DriverUpdatesCount field from Stats
    Changes in 1.9:
    - Fixed progress bar: TotalSteps now calculated dynamically based on skip flags
    - Fixed winget: source update skipped in ReportOnly mode, added ExitCode check
    - Fixed winget: --include-unknown now used consistently for count and upgrade
    - Fixed browser cache statistics: now measures actual freed space (before/after)
    - Fixed Storage Sense: now waits for task completion instead of fixed sleep
    - Fixed DNS flush: logs warning on unexpected result instead of false success
    - Fixed WSL/Docker VHDX: now compacts all VHDX files regardless of distro list
    - Moved Update-Progress calls after skip flag checks for accurate progress
    Changes in 1.8:
    - Fixed critical bug: $LogPath vs $script:LogPath in Start-WinClean and Show-FinalStatistics
    - Fixed version inconsistency: unified all version references to single source
    - Added browser cache size tracking to freed space statistics
    - Fixed TotalSteps count (was 12, actual 7 steps)
    - Improved winget update detection: language-independent parsing
    Changes in 1.7:
    - Improved internet connectivity check: HTTPS endpoints + ICMP fallback
    - Fixed Show-Banner to display correct log path ($script:LogPath)
    - Fixed Clear-SystemCaches: ReportOnly mode and size tracking for single files
    Changes in 1.6:
    - Added pause at end: window stays open 60 sec or until key press
      (prevents window from closing before user can read results)
    Changes in 1.5:
    - Fixed visual glitch: clear progress bar before DISM output to prevent overlay
    Changes in 1.4:
    - Fixed Clear-PrivacyTraces: added -Recurse to Remove-Item to prevent confirmation
      prompts when cleaning Recent folder (AutomaticDestinations, CustomDestinations)
    Changes in 1.3:
    - CRITICAL FIX: Clear-RecycleBin renamed to Clear-WinCleanRecycleBin to avoid
      infinite recursion (stack overflow) caused by name collision with built-in cmdlet
    Changes in 1.2:
    - Fixed $script:LogPath scope (logging now works correctly)
    - Fixed Clear-BrowserCaches respecting ReportOnly mode
    - Fixed Windows.old path to use $env:SystemDrive instead of hardcoded C:
    - Fixed NuGet: removed packages folder (not cache), kept only metadata caches
    - Fixed Gradle: only delete safe build caches, not downloaded dependencies
    - Fixed Windows Update services now properly restart via try/finally
    - Fixed WSL --list output UTF-16LE parsing (removes null characters)
.PARAMETER SkipUpdates
    Пропустить все обновления (Windows + winget)
.PARAMETER SkipCleanup
    Пропустить все операции очистки (система, глубокая очистка, кэши разработчика,
    Docker/WSL, Visual Studio). Отдельные -Skip*Cleanup - более точечные флаги внутри
.PARAMETER SkipRestore
    Пропустить создание точки восстановления
.PARAMETER SkipDevCleanup
    Пропустить очистку кэшей разработчика (npm, pip, nuget)
.PARAMETER SkipDockerCleanup
    Пропустить очистку Docker/WSL
.PARAMETER SkipVSCleanup
    Пропустить очистку Visual Studio
.PARAMETER SkipDiskCleanup
    Пропустить только шаг Storage Sense / Disk Cleanup (штатная утилита Windows).
    Этот шаг бывает самым долгим: на реальной рабочей станции cleanmgr занял 15 минут
    из 18 и не успел завершиться, тогда как на чистой виртуальной машине те же
    23 категории отрабатывают за 10 секунд. Причина разницы НЕ установлена: измерение
    показывает лишь, что стоимость зависит от накопленного состояния машины. Остальная
    очистка при этом выполняется - в отличие от -SkipCleanup, который гасит её целиком
.PARAMETER DisableTelemetry
    Отключить телеметрию Windows (через групповую политику)
.PARAMETER ReportOnly
    Только показать, что будет сделано (без выполнения)
.PARAMETER LogPath
    Путь к файлу лога (по умолчанию: $env:TEMP\WinClean_<date>.log)
.PARAMETER ResultJsonPath
    Путь для машиночитаемого итога прогона (JSON). Используется автотестами
    и стендами; если не задан - JSON не создаётся
#>

#Requires -Version 7.1
#Requires -RunAsAdministrator

# PositionalBinding disabled (v2.15): stray positional arguments must fail loudly
# instead of silently binding to LogPath/ResultJsonPath and turning an intended
# dry run into a real one
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipUpdates,
    [switch]$SkipCleanup,
    [switch]$SkipRestore,
    [switch]$SkipDevCleanup,
    [switch]$SkipDockerCleanup,
    [switch]$SkipVSCleanup,
    [switch]$SkipDiskCleanup,
    [switch]$DisableTelemetry,
    [switch]$ReportOnly,
    [string]$LogPath,
    [string]$ResultJsonPath
)

#region ═══════════════════════════════════════════════════════════════════════
#                              INITIALIZATION
#═══════════════════════════════════════════════════════════════════════════════

# Ensure UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Statistics storage (synchronized hashtable for safe concurrent access)
function New-RunStats {
    <#
    .SYNOPSIS
        Builds a fresh per-run statistics object
    .DESCRIPTION
        v2.20: this was a literal assigned once when the script loaded, and Start-WinClean
        reset only the phase buckets and the step counter - while the comment there
        described "dot-source and call Start-WinClean twice" as the case being handled.
        Everything else survived: freed bytes, per-category totals, update counts, warning
        and error counts, RebootRequired, Aborted and StartTime. A second run in the same
        session therefore reported the first run's bytes and errors, and computed its
        duration from the moment the script was dot-sourced.

        One definition, used both at load time and at the start of every run.
    #>
    return [hashtable]::Synchronized(@{
    TotalFreedBytes      = [long]0
    FreedByCategory      = @{}
    WindowsUpdatesCount  = 0
    # v2.19: renamed from AppUpdatesCount. winget upgrade --all cannot report how many
    # apps actually installed (it silently skips pinned/manifest-less/UAC-cancelled ones),
    # so we only ever know how many it OFFERED. Naming it "installed" was a false claim.
    AppUpdatesOffered    = 0
    # v2.21: why the app half of the Updates phase produced the count it did. Added because demoting a
    # missing winget from error to warning removed the only machine-readable way to tell
    # "checked, nothing to upgrade" from "could not check at all" - both are
    # AppUpdatesOffered = 0 with WarningsCount incremented by one of many possible causes.
    # 'not-run' | 'checked' | 'check-failed' | 'skipped-parameter' | 'skipped-offline'
    # | 'skipped-no-winget'
    AppUpdatesStatus     = 'not-run'
    WarningsCount        = 0
    ErrorsCount          = 0
    RebootRequired       = $false
    StartTime            = Get-Date
    CurrentStep          = 0
    TotalSteps           = 0  # Calculated dynamically in Start-WinClean
    # v2.16: tri-state string, 'disabled' / 'enabled' / 'unknown'. Never a boolean:
    # 'unknown' must not be mistaken for a verified state by consumers of the JSON
    ControlledFolderAccess = 'unknown'
    Aborted              = $null     # v2.17: set when the run stops before finishing
    # v2.20: cleanmgr outlived its timeout and is still deleting in the background. The
    # totals reported by this run are partial, and a consumer must not read them as final.
    DiskCleanupPending   = $false
    # v2.22: how the Storage Sense / Disk Cleanup step actually ended. DiskCleanupPending
    # alone could not tell "still deleting" from "finished but the process never exited",
    # and reported both as pending - so a completed cleanup was published as partial.
    # Same shape and reasoning as AppUpdatesStatus (v2.21): when a boolean starts covering
    # two different truths, the fix is a status, not a cleverer boolean.
    # 'not-run' | 'skipped-parameter' | 'storage-sense' | 'completed' |
    # 'completed-resident' | 'timeout' | 'failed'
    DiskCleanupStatus    = 'not-run'
    # v2.17 (p.11 of the audit): which top-level phases ran to completion vs threw.
    # Before this, one exception anywhere in the run silently skipped every phase
    # after it - Developer Cleanup, Docker/WSL, Visual Studio, Deep System Cleanup,
    # the disk space report, Telemetry - with only a single generic "Critical error"
    # in the log to show for it.
    # v2.19: these are a DISPATCH status, not an outcome. Completed = the phase action
    # was invoked and returned without an uncaught exception (NOT "succeeded" - e.g.
    # Preparation stays Completed even when the restore point genuinely failed, because
    # New-SystemRestorePoint catches that and returns $false). Skipped = a skip flag
    # suppressed the phase before it ran. Failed = the action threw. For a non-aborted
    # run the three are disjoint and their union is exactly the known phase set.
    PhasesCompleted      = @()
    PhasesFailed         = @()
    PhasesSkipped        = @()
    })
}

$script:Stats = New-RunStats

# Progress activities seen so far, so all of them can be closed at the end (v2.16)
$script:ProgressActivities = @()

# Memoized Test-InternetConnection result for the whole run (v2.17, p.5 of the audit):
# the check costs up to ~15s offline and is called from both halves of the Updates phase
$script:InternetConnectionCache = $null

# Latched by Write-Log when the log file cannot be written, so the failure is reported
# once instead of on every call - and surfaces in the result JSON as LoggingDegraded
$script:LogWriteFailed = $false

# Initialize log path (script scope for access in functions)
if (-not $LogPath) {
    $script:LogPath = Join-Path $env:TEMP "WinClean_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"
} else {
    $script:LogPath = $LogPath
    # Ensure the parent directory exists for custom log paths (v2.14)
    $logDir = Split-Path -Path $script:LogPath -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# Script version (single source of truth for version checking)
$script:Version = "2.21"

# Protected paths that should never be deleted
$script:ProtectedPaths = @(
    $env:SystemRoot,
    "$env:SystemRoot\System32",
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)},
    $env:USERPROFILE,
    "$env:SystemDrive\Users",
    "$env:SystemDrive\Program Files",
    "$env:SystemDrive\Program Files (x86)"
)

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              LOGGING FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Write-LogFileLine {
    <#
    .SYNOPSIS
        Appends one line to the log file, degrading instead of throwing
    .DESCRIPTION
        v2.22, raised in external review: extracted from Write-Log so that EVERY write to
        the log file - including the header, which Start-WinClean emits before its main
        try/finally exists - degrades the same way instead of each caller inventing its
        own fault tolerance.

        The header used to be two bare Out-File calls. Measured, not assumed: six of seven
        bad log paths make Out-File throw a TERMINATING error even though the script leaves
        ErrorActionPreference at Continue (missing directory, path is a directory, invalid
        characters, colon in the name, over-long path, unreachable UNC; only a reserved
        device name did not). Thrown there, before the safety net, the exception escaped
        Start-WinClean entirely: no result JSON, no final summary, no exit-code accounting,
        and none of the maintenance the run was started for - all because of the log.

        A log that cannot be written is a degraded run, never a failed one.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line,

        # The header line starts a fresh file. The Out-File call this replaced had no
        # -Append, so it truncated on every run; preserved deliberately rather than lost
        # in the refactor, or a custom -LogPath reused across runs would accumulate them
        # all into one file and the log would no longer describe a single run.
        [switch]$StartNewFile
    )

    # v2.17 (p.7 of the audit): Out-File used to open, seek to end, write and close the
    # file on every single call - Write-Log fires hundreds of times per run. A StreamWriter
    # kept open for the run avoids that, with AutoFlush so each line still lands on disk
    # immediately (same durability as before, just cheaper). FileShare.Delete matters for
    # tests: they Remove-Item the log path in AfterAll while this writer may still be the
    # last one that touched it.
    try {
        if ($StartNewFile -or -not $script:LogWriter -or $script:LogWriterPath -ne $script:LogPath) {
            if ($script:LogWriter) { $script:LogWriter.Dispose() }
            $mode = if ($StartNewFile) { [System.IO.FileMode]::Create } else { [System.IO.FileMode]::Append }
            $fileStream = [System.IO.File]::Open(
                $script:LogPath, $mode, [System.IO.FileAccess]::Write,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $script:LogWriter = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8)
            $script:LogWriter.AutoFlush = $true
            $script:LogWriterPath = $script:LogPath
        }
        $script:LogWriter.WriteLine($Line)
    } catch {
        # v2.20: this used to be an empty catch, so a log that stopped being written
        # (full volume, revoked permissions, the v2.14 case where cleanup deleted the
        # log out from under us) was invisible: destructive work carried on, the final
        # JSON said ErrorsCount=0, and LogPath pointed at a truncated file.
        #
        # Latched: one console line, not one per call - Write-Log fires hundreds of
        # times per run. Deliberately Write-Host and not Write-Log, which would
        # recurse straight back into this catch.
        # v2.20, corrected in review: drop the writer so the NEXT call reopens it.
        # Without this the guard above stays satisfied by a dead writer object and
        # every later line is silently discarded for the rest of the run - the empty
        # catch would simply have moved from the first failure to all the others.
        try { if ($script:LogWriter) { $script:LogWriter.Dispose() } } catch { }
        $script:LogWriter = $null
        $script:LogWriterPath = $null

        if (-not $script:LogWriteFailed) {
            $script:LogWriteFailed = $true
            $script:Stats.WarningsCount++
            Write-Host "  [WARN]  Log file could not be written ($($_.Exception.Message)) - the run continues, but $($script:LogPath) may be incomplete" -ForegroundColor Yellow
        }
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes colored output to console and plain text to log file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'TITLE', 'SECTION', 'DETAIL')]
        [string]$Level = 'INFO',

        [switch]$NoNewLine,
        [switch]$NoTimestamp,
        [switch]$NoLog
    )

    # Consistent left indent for all output (matches banner style)
    $indent = "  "
    $boxWidth = 70  # Inner width for framed sections

    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $logMessage = "[$timestamp] [$Level] $Message"

    if (-not $NoLog) {
        Write-LogFileLine -Line $logMessage
    }

    # Console output with colors
    $colors = @{
        INFO    = @{ Tag = 'Cyan';    Message = 'White' }
        SUCCESS = @{ Tag = 'Green';   Message = 'White' }
        WARNING = @{ Tag = 'Yellow';  Message = 'Yellow' }
        ERROR   = @{ Tag = 'Red';     Message = 'Red' }
        TITLE   = @{ Tag = 'Magenta'; Message = 'Magenta' }
        SECTION = @{ Tag = 'Cyan';    Message = 'Cyan' }
        DETAIL  = @{ Tag = 'DarkGray';Message = 'Gray' }
    }

    $tagColors = $colors[$Level]

    switch ($Level) {
        'TITLE' {
            # Full frame for major sections (like banner style, but Magenta)
            $titleText = $Message.ToUpper()
            $padding = [math]::Max(0, $boxWidth - $titleText.Length)
            $leftPad = [math]::Floor($padding / 2)
            $rightPad = $padding - $leftPad
            $centeredTitle = (" " * $leftPad) + $titleText + (" " * $rightPad)

            Write-Host ""
            Write-Host "$indent╔$("═" * $boxWidth)╗" -ForegroundColor $tagColors.Tag
            Write-Host "$indent║$centeredTitle║" -ForegroundColor $tagColors.Tag
            Write-Host "$indent╚$("═" * $boxWidth)╝" -ForegroundColor $tagColors.Tag
        }
        'SECTION' {
            # Subsection header (keep original style with indent)
            Write-Host ""
            Write-Host "$indent┌─ " -NoNewline -ForegroundColor DarkGray
            Write-Host $Message -ForegroundColor $tagColors.Message
            Write-Host "$indent└$("─" * 70)" -ForegroundColor DarkGray
        }
        'DETAIL' {
            # Detail line with vertical bar
            Write-Host "$indent  │ " -NoNewline -ForegroundColor DarkGray
            Write-Host $Message -ForegroundColor $tagColors.Message -NoNewline:$NoNewLine
            if (-not $NoNewLine) { Write-Host "" }
        }
        default {
            # Standard log line with timestamp and tag
            Write-Host $indent -NoNewline

            if (-not $NoTimestamp) {
                Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
            }

            $tagText = switch ($Level) {
                'INFO'    { '[INFO]  ' }
                'SUCCESS' { '[OK]    ' }
                'WARNING' { '[WARN]  ' }
                'ERROR'   { '[ERROR] ' }
            }

            Write-Host $tagText -NoNewline -ForegroundColor $tagColors.Tag
            Write-Host $Message -ForegroundColor $tagColors.Message -NoNewline:$NoNewLine
            if (-not $NoNewLine) { Write-Host "" }
        }
    }
}

function Update-Progress {
    <#
    .SYNOPSIS
        Updates progress bar and step counter
    #>
    param(
        [string]$Activity,
        [string]$Status = "Processing..."
    )

    $script:Stats.CurrentStep++
    $percent = [math]::Min(100, [math]::Round(($script:Stats.CurrentStep / $script:Stats.TotalSteps) * 100))

    # Remember the activity so Clear-AllProgress can close it later (v2.16)
    if ($Activity -and $script:ProgressActivities -notcontains $Activity) {
        $script:ProgressActivities += $Activity
    }

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $percent
}

function Clear-AllProgress {
    <#
    .SYNOPSIS
        Closes every progress bar before the final report is printed
    .DESCRIPTION
        v2.16: "Write-Progress -Activity 'Complete' -Completed" only closed an activity
        that never existed, so leftover bars stayed on screen under the summary - both
        our own (seven different activities are used) and foreign ones from cmdlets such
        as Clear-RecycleBin, whose activity name is not ours to know. Clearing by Id
        covers those: an unused Id is simply a no-op.
        v2.17 (p.16 of the audit): 0..10 was eyeballed, not derived from anything. Widened
        to 0..30 - ForEach-Object -Parallel and nested cmdlets can allocate Ids well past
        10, and clearing an unused Id costs nothing.
    #>
    foreach ($activity in $script:ProgressActivities) {
        Write-Progress -Activity $activity -Completed -ErrorAction SilentlyContinue
    }
    for ($id = 0; $id -le 30; $id++) {
        Write-Progress -Id $id -Activity ' ' -Completed -ErrorAction SilentlyContinue
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              HELPER FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Get-RunMarkerPath {
    Join-Path $env:TEMP 'WinClean.recovery-marker.json'
}

function Set-RunMarker {
    <#
    .SYNOPSIS
        Records that a risky, hard-to-undo operation is about to start
    .DESCRIPTION
        v2.17 (p.13 of the audit): Ctrl+C already unwinds through try/finally - the
        gap is a HARD kill (taskkill /F, a closed terminal, a reset VM), which skips
        every finally block, including the ones that restore
        SystemRestorePointCreationFrequency or restart wuauserv/bits. This marker lets
        the next run detect that and recover - a plain "is the value 0 right now"
        check cannot tell an interrupted run from a value the user or IT policy set on
        purpose, and blindly overwriting that would be the wrong kind of surprise.
        Best-effort: a failed marker write must never block the real operation.
    #>
    param(
        [Parameter(Mandatory)][string]$Phase,
        [hashtable]$Data = @{}
    )
    try {
        $marker = [ordered]@{ Phase = $Phase; Pid = $PID; Timestamp = (Get-Date).ToString('o') }
        foreach ($key in $Data.Keys) { $marker[$key] = $Data[$key] }
        $marker | ConvertTo-Json -Compress | Set-Content -LiteralPath (Get-RunMarkerPath) -Encoding utf8 -ErrorAction Stop
    } catch { }
}

function Clear-RunMarker {
    Remove-Item -LiteralPath (Get-RunMarkerPath) -Force -ErrorAction SilentlyContinue
}

function Restore-RestorePointFrequency {
    <#
    .SYNOPSIS
        Puts SystemRestorePointCreationFrequency back to $PreviousValue, if it is still 0
    .DESCRIPTION
        Shared by the inline timeout path in New-SystemRestorePoint and by
        Invoke-StaleMarkerRecovery, so both behave identically. Only acts when the value
        is currently 0 (i.e. still holding this script's override) - if something else
        has since set a real value, that is left alone.
    .OUTPUTS
        [bool] $true when nothing needs doing or the restore succeeded, $false on failure
    #>
    param($PreviousValue)

    try {
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $current = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        if ($current -ne 0) { return $true }   # already a real value - not ours to touch

        if ($null -ne $PreviousValue) {
            Set-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value $PreviousValue -Type DWord -Force -ErrorAction Stop
        } else {
            Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Log "Could not restore SystemRestorePointCreationFrequency: $_" -Level WARNING
        return $false
    }
}

function Invoke-StaleMarkerRecovery {
    <#
    .SYNOPSIS
        Recovers system state left behind by a hard-killed previous run, if any
    .DESCRIPTION
        v2.17 (p.13 of the audit). Called once at the start of a run. A marker left by
        THIS run's own process id is not evidence of anything (re-entrant call, or a
        race) - only a marker from a different process means the previous run never
        reached its cleanup.

        The marker is kept when recovery FAILS, so the next run can retry instead of
        leaving the damage in place forever with no record of it.

        Known limitation, deliberately not solved here: a PID is not a durable identity
        (Windows recycles them, and two concurrent runs would each see the other as
        "foreign"). Both cases need a second WinClean running as administrator at the
        same time, which the script does not support anyway; the recovery actions are
        also written to be no-ops when there is nothing to repair.
    #>
    $markerPath = Get-RunMarkerPath
    if (-not (Test-Path -LiteralPath $markerPath -ErrorAction SilentlyContinue)) { return }

    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        return
    }

    if ($marker.Pid -eq $PID) { return }

    Write-Log "Recovery marker found from an interrupted previous run (phase: $($marker.Phase), pid $($marker.Pid)) - checking for leftover state" -Level WARNING
    $script:Stats.WarningsCount++

    $recovered = $true
    switch ($marker.Phase) {
        'RestorePointFrequencyOverride' {
            $recovered = Restore-RestorePointFrequency -PreviousValue $marker.PreviousValue
            if ($recovered) {
                Write-Log "Checked SystemRestorePointCreationFrequency after the interrupted run" -Level INFO
            }
        }
        'WUServiceStop' {
            # Only services this script actually stopped are restarted. Starting every
            # stopped service would fight an administrator who disabled one on purpose.
            foreach ($svcName in @($marker.ServicesToRestart)) {
                if (-not $svcName) { continue }
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Stopped') {
                        Start-Service -Name $svcName -ErrorAction Stop
                        Write-Log "Restarted $svcName, left stopped by the interrupted run" -Level INFO
                    }
                } catch {
                    Write-Log "Could not restart $svcName : $_" -Level WARNING
                    $recovered = $false
                }
            }
        }
    }

    if ($recovered) {
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "Recovery incomplete - keeping the marker so the next run retries" -Level WARNING
    }
}

function Test-InteractiveConsole {
    <#
    .SYNOPSIS
        Checks if running in an interactive console environment
    .DESCRIPTION
        Returns $false for Scheduled Tasks, ISE, remote sessions, etc.
        Used to safely skip [Console]::KeyAvailable calls that would throw exceptions
    #>
    try {
        # Check if we're in ConsoleHost and have a valid console window
        if ($Host.Name -ne 'ConsoleHost') {
            return $false
        }
        # Try to access console properties - will throw in non-console environments
        $null = [Console]::WindowWidth
        return $true
    } catch {
        return $false
    }
}

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Проверяет доступ к интернету через TCP-соединения с таймаутом
    .DESCRIPTION
        Использует TcpClient с явным таймаутом (3 сек) вместо Test-NetConnection,
        который может зависать на 20-30 секунд при VPN или нестабильном соединении.
        Результат кэшируется на весь прогон (v2.17): вызывается из обеих половин фазы
        Updates (Windows Update, Applications Update), до 15 сек на офлайн-машине каждый раз.
        Сетевая связность внутри одного прогона скрипта не меняется настолько часто,
        чтобы повторная проверка была оправдана. -Force сбрасывает кэш.
    #>
    param([switch]$Force)

    if (-not $Force -and $null -ne $script:InternetConnectionCache) {
        return $script:InternetConnectionCache
    }

    $targets = @(
        @{ Host = 'www.microsoft.com'; Port = 443 }
        @{ Host = 'api.github.com'; Port = 443 }
        @{ Host = 'cdn.winget.microsoft.com'; Port = 443 }
    )

    $timeoutMs = 3000  # 3 секунды таймаут на каждое соединение

    foreach ($target in $targets) {
        $tcpClient = $null
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($target.Host, $target.Port, $null, $null)
            $success = $connect.AsyncWaitHandle.WaitOne($timeoutMs, $false)

            if ($success -and $tcpClient.Connected) {
                $tcpClient.EndConnect($connect)
                $script:InternetConnectionCache = $true
                return $true
            }
        } catch {
        } finally {
            # Always close TcpClient to prevent resource leaks (fixed in v2.2)
            if ($tcpClient) {
                $tcpClient.Close()
            }
        }
    }

    # Запасной вариант: ICMP (может быть заблокирован в некоторых сетях)
    $dnsServers = @('8.8.8.8', '1.1.1.1', '208.67.222.222')

    foreach ($dns in $dnsServers) {
        if (Test-Connection -ComputerName $dns -Count 1 -Quiet -TimeoutSeconds 2 -ErrorAction SilentlyContinue) {
            $script:InternetConnectionCache = $true
            return $true
        }
    }
    $script:InternetConnectionCache = $false
    return $false
}

function Test-PSGalleryConnection {
    <#
    .SYNOPSIS
        Проверяет доступность PowerShell Gallery перед установкой модулей
    .DESCRIPTION
        Использует Invoke-WebRequest с коротким таймаутом для проверки доступности
        powershellgallery.com. Более специфичная проверка чем общий Test-InternetConnection.
    .OUTPUTS
        [bool] $true если PowerShell Gallery доступен, $false в противном случае
    #>
    try {
        # Check PSGallery API endpoint (faster than main page)
        # Note: -UseBasicParsing removed - it was deprecated in PS 6.0 and removed in PS 7.4+
        $response = Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2" `
            -TimeoutSec 10 -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Test-PathInsideRoot {
    <#
    .SYNOPSIS
        Tells whether a path lies inside a directory
    .DESCRIPTION
        Pure decision, added in v2.21 for the update-channel rule below.
        The root gets a trailing separator before the comparison, so C:\Temp2\x is not
        read as living inside C:\Temp. Case-insensitive, matching the file system.
        An unusable path or root answers "not inside" rather than throwing: the only
        consumer picks wording from the answer, and a wrong "yes" prints an instruction
        that does not apply to the copy the user is running.
    #>
    param(
        [AllowNull()][string]$Path,
        [AllowNull()][string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    } catch {
        return $false
    }

    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ScriptUpdateChannel {
    <#
    .SYNOPSIS
        Decides how THIS running copy of WinClean can be updated
    .DESCRIPTION
        Pure decision, added in v2.21 to fix an update that reported success while
        updating a different file.
        Until now the question asked was "does a Gallery copy exist anywhere on this
        machine", and the answer was acted on as if it had been "is the file I am
        running that copy". Both are commonly true at once: install.ps1 (v2.15) puts a
        copy in %ProgramFiles%\WinClean while an older Install-Script copy still sits in
        Documents\PowerShell\Scripts. Update-Script then updated the copy in Documents,
        printed "run WinClean again to use the new version", and the shortcut kept
        starting the untouched Program Files copy - forever, with no error anywhere.
        Returns one of:
          gallery           - the running file IS the only Gallery copy; it can update itself
          gallery-ambiguous - it matches a Gallery copy, but several installs exist
          installer         - it lives in %ProgramFiles%\WinClean, so install.ps1 updates it
          oneliner          - it lives under TEMP, so get.ps1 downloaded it for this run
          manual            - somewhere else; only a manual download applies
          unknown           - the path is unavailable, so nothing may be promised
        Ambiguity resolves away from 'gallery' on purpose: the cost of the wrong answer
        is asymmetric. Printing an instruction to a copy that could have updated itself
        is a minor annoyance; auto-updating a file nobody is running is the defect.
        That is also why several installs (AllUsers and CurrentUser can coexist) refuse
        the automatic path outright, raised in review. PowerShellGet's Update-Script has no
        -Scope at all; PSResourceGet's Update-PSResource does have one, but WinClean does
        not map a matched install location back to a scope, and the updater is chosen by
        which provider answered rather than by which install matched. So the target cannot
        currently be named, and declining beats guessing: verifying afterwards would report
        a miss honestly, but only after the unused copy had already been modified. Same rule
        as Select-StorageSenseTask. Aiming the PSResourceGet updater by scope is possible
        and is left as future work rather than claimed here.
        Known limit: the comparison is lexical. A path reached through a junction or an
        8.3 alias fails to match and is merely shown an instruction (safe). The reverse -
        two files differing only in case inside one case-sensitive directory - would match
        wrongly, and is left unhandled as a configuration this script does not support.
        'installer' and 'oneliner' describe WHERE the file is, which is what decides the
        right instruction; they do not claim to prove which tool put it there.
    #>
    param(
        [AllowNull()][string]$ExecutingPath,
        [AllowNull()][string[]]$GalleryLocation,
        [AllowNull()][string]$ProgramFilesRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles),
        [AllowNull()][string]$TempRoot = [System.IO.Path]::GetTempPath()
    )

    if ([string]::IsNullOrWhiteSpace($ExecutingPath)) { return 'unknown' }
    try { $fullPath = [System.IO.Path]::GetFullPath($ExecutingPath) } catch { return 'unknown' }

    # Compare the full file path, not its folder: a Gallery install owns exactly
    # WinClean.ps1 inside InstalledLocation, and a differently named copy sharing that
    # folder is not the file the provider would replace.
    # Deduplicate case-insensitively, matching the comparison below and the file system.
    # Select-Object -Unique is case-SENSITIVE (verified, 22.07.2026), so the two providers
    # reporting one install with different casing would have looked like two installs and
    # silently switched a perfectly updatable machine to the refusal path.
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $candidates = @()
    foreach ($location in @($GalleryLocation)) {
        if ([string]::IsNullOrWhiteSpace($location)) { continue }
        try { $candidate = [System.IO.Path]::GetFullPath((Join-Path $location 'WinClean.ps1')) } catch { continue }
        if ($seen.Add($candidate)) { $candidates += $candidate }
    }

    foreach ($candidate in $candidates) {
        if ([string]::Equals($fullPath, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($candidates.Count -gt 1) { return 'gallery-ambiguous' }
            return 'gallery'
        }
    }

    $installerRoot = if ([string]::IsNullOrWhiteSpace($ProgramFilesRoot)) { $null }
                     else { Join-Path $ProgramFilesRoot 'WinClean' }
    if (Test-PathInsideRoot -Path $fullPath -Root $installerRoot) { return 'installer' }
    if (Test-PathInsideRoot -Path $fullPath -Root $TempRoot) { return 'oneliner' }
    return 'manual'
}

function Get-UpdateVerification {
    <#
    .SYNOPSIS
        Decides whether an update that reported no error actually replaced the file
    .DESCRIPTION
        Pure decision, added in v2.21. "The cmdlet did not throw" is not "the file on
        disk is now the new version" - the whole point of this release's predecessor was
        that operations reporting success without doing anything are the expensive kind
        of defect, and an updater is the last place to trust a silent success.
        Returns Applied and Reason ('applied' | 'unchanged' | 'unreadable').
        An unreadable or unparsable version is never 'applied': that is the state where
        nothing is known, and claiming success there is the behaviour being removed.
    #>
    param(
        [AllowNull()][string]$ExpectedVersion,
        [AllowNull()][string]$ObservedVersion
    )

    $observed = $null
    $expected = $null
    if (-not [Version]::TryParse([string]$ObservedVersion, [ref]$observed) -or
        -not [Version]::TryParse([string]$ExpectedVersion, [ref]$expected)) {
        return @{ Applied = $false; Reason = 'unreadable' }
    }

    # Missing components are -1 in [Version], not 0, so "2.21" compares as LESS than
    # "2.21.0" (raised in review). The Gallery is free to report either form for the same
    # release, and without this the check would announce "the update did not apply" after
    # a perfectly good update - a false alarm in the one place whose job is to be trusted.
    $observed = [Version]::new($observed.Major, $observed.Minor,
                               [math]::Max(0, $observed.Build), [math]::Max(0, $observed.Revision))
    $expected = [Version]::new($expected.Major, $expected.Minor,
                               [math]::Max(0, $expected.Build), [math]::Max(0, $expected.Revision))

    if ($observed -lt $expected) { return @{ Applied = $false; Reason = 'unchanged' } }
    return @{ Applied = $true; Reason = 'applied' }
}

function Get-ScriptFileVersion {
    <#
    .SYNOPSIS
        Reads the .VERSION line out of a WinClean.ps1 file on disk
    .DESCRIPTION
        Added in v2.21 to verify an update against the file actually being run, rather
        than against what a package provider believes it installed. PowerShell reads a
        script into memory before executing it, so the running file can be replaced and
        re-read while the current run continues.
        Returns the version string, or $null when the file cannot be read or carries no
        .VERSION line - both mean "not verified", never "verified".
    #>
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { $head = Get-Content -LiteralPath $Path -TotalCount 40 -ErrorAction Stop } catch { return $null }

    foreach ($line in $head) {
        if ($line -match '^\s*\.VERSION\s+([\d.]+)\s*$') { return $Matches[1] }
    }
    return $null
}

function Get-InstalledWinCleanLocation {
    <#
    .SYNOPSIS
        Returns the folders holding a PowerShell Gallery copy of WinClean
    .DESCRIPTION
        Two providers can own that copy: PowerShellGet (Install-Script) and PSResourceGet
        (Install-PSResource). Measured on 22.07.2026 with each in turn: both report the
        other's install, because they share the InstalledScriptInfos metadata, and for a
        script InstalledLocation is the Scripts folder itself - unlike modules, it carries
        no version subfolder. Both are still queried, because which provider ships is a
        property of the PowerShell version rather than of this machine. PSResourceGet is
        asked for AllUsers explicitly, because its -Scope defaults to CurrentUser.
        An array: CurrentUser and AllUsers installs can coexist. THROWS when no provider
        covered the machine and at least one query failed - including when some locations
        WERE found, because a partial list is not a smaller answer: a hidden install turns
        an ambiguous target back into a confident one. An unreadable machine must not be
        reported as a machine with no Gallery copy either, because that answer sends the
        caller on to advise an installer command and build a second installation.
    #>
    $locations = @()
    $failures = @()
    $answered = $false

    # Each provider is isolated (raised in review): -ErrorAction SilentlyContinue only
    # covers non-terminating errors, so a broken PowerShellGet used to abort this function
    # outright and PSResourceGet was never asked - turning a repairable half-outage into
    # "no Gallery copy exists", which is exactly the wrong answer to give this caller.
    if (Get-Command Get-InstalledScript -ErrorAction SilentlyContinue) {
        try {
            # Enumerated without -Name and filtered here (raised in review, verified
            # 22.07.2026): asking for a specific name raises a plain Exception when it is
            # not installed, which cannot be told from a real outage without matching a
            # localised message - so the query had to run with SilentlyContinue and a
            # suppressed failure then passed as an authoritative "no copy installed".
            # Listing everything returns an EMPTY COLLECTION when nothing is installed, so
            # -ErrorAction Stop now separates the two properly. This provider enumerates
            # both scopes, so one completed call covers the machine.
            $locations += @(Get-InstalledScript -ErrorAction Stop |
                            Where-Object { $_.Name -eq 'WinClean' } |
                            ForEach-Object { $_.InstalledLocation })
            $answered = $true
        } catch {
            $failures += $_
            Write-Log "PowerShellGet could not be queried for installed copies: $_" -Level DETAIL
        }
    }
    if (Get-Command Get-PSResource -ErrorAction SilentlyContinue) {
        # -ErrorAction Stop here too, but for a different reason than above: measured
        # 22.07.2026, this provider raises a TYPED ResourceNotFoundException for "nothing
        # installed", so the two outcomes are separated by exception type rather than by
        # asking a question that cannot fail.
        $currentUserRead = $false
        try {
            $locations += @(Get-PSResource -Name 'WinClean' -ErrorAction Stop |
                            Where-Object { $_.Type -eq 'Script' } |
                            ForEach-Object { $_.InstalledLocation })
            $currentUserRead = $true
        } catch {
            if ($_.Exception.GetType().Name -eq 'ResourceNotFoundException') {
                $currentUserRead = $true   # answered: this scope holds no copy
            } else {
                $failures += $_
                Write-Log "PSResourceGet could not be queried for installed copies: $_" -Level DETAIL
            }
        }

        # AllUsers has to be asked for explicitly (raised in review, verified here):
        # Get-PSResource's -Scope is not nullable, so an unbound call means CurrentUser and
        # searches only the Documents paths. PowerShellGet's Get-InstalledScript enumerates
        # both scopes, which is why this was invisible on any machine that has it - and why
        # it mattered exactly on the PSResourceGet-only machine this release added support
        # for. AllUsers is the natural scope for a script that requires administrator, so
        # missing it classified a Gallery copy as 'manual' and advised install.ps1, adding a
        # second installation.
        # Support is read from the cmdlet's own metadata rather than tried and ignored
        # (raised in review): "this build has no -Scope" is a limitation to accept, but any
        # OTHER failure means the AllUsers half went unread, and swallowing that would hide
        # precisely the installation this branch exists to find.
        # Tracked per scope (raised in review): a single "somebody answered" flag let a
        # successful CurrentUser query mask a failed AllUsers one, and AllUsers is the half
        # this whole branch exists to read. This provider counts as having covered the
        # machine only when BOTH scopes were read - or when the build predates -Scope, which
        # is an accepted limitation rather than a failure.
        $allUsersRead = $true
        if ((Get-Command Get-PSResource).Parameters.ContainsKey('Scope')) {
            $allUsersRead = $false
            try {
                $locations += @(Get-PSResource -Name 'WinClean' -Scope AllUsers -ErrorAction Stop |
                                Where-Object { $_.Type -eq 'Script' } |
                                ForEach-Object { $_.InstalledLocation })
                $allUsersRead = $true
            } catch {
                if ($_.Exception.GetType().Name -eq 'ResourceNotFoundException') {
                    $allUsersRead = $true
                } else {
                    $failures += $_
                    Write-Log "PSResourceGet could not be queried for AllUsers copies: $_" -Level DETAIL
                }
            }
        }

        if ($currentUserRead -and $allUsersRead) { $answered = $true }
    }

    # Nothing found AND something failed is not the same as nothing installed (raised in
    # review). Treating them alike classified the running file as 'manual' and printed
    # "this copy did not come from the Gallery" plus an installer command - which would add
    # a SECOND installation next to the one that was merely unreadable, building the very
    # state this release exists to stop misreporting. The caller turns this into a warning
    # and offers nothing, which is the honest answer when the machine cannot be read.
    # An absent provider is not a failure: a machine with no package provider at all
    # legitimately has no Gallery copy.
    # Keyed on "nobody answered", not "somebody failed" (raised in review): with a broken
    # PowerShellGet beside a working PSResourceGet that legitimately reports no copy, a
    # failure count above zero would raise a warning on a machine that answered correctly.
    # Coverage alone decides, NOT emptiness (raised in review): with CurrentUser returning
    # the running copy while the AllUsers query failed, a non-empty list looked like a
    # complete answer - and a hidden second install turns 'gallery-ambiguous' back into
    # 'gallery', re-enabling exactly the automatic update whose target cannot be resolved.
    # A partial list is not a smaller answer, it is a different question answered.
    if (-not $answered -and $failures.Count -gt 0) {
        throw "installed copies could not be enumerated: $($failures[-1])"
    }

    # Case-insensitive, for the reason given in Get-ScriptUpdateChannel: both providers
    # report the same install, and differing casing between them must not read as two.
    # Normalised first (raised in review), so "C:\Scripts" and "C:\Scripts\" are one
    # location here too - this function promises distinct locations, and the caller is not
    # the only thing entitled to rely on that.
    $unique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = @()
    foreach ($location in $locations) {
        if ([string]::IsNullOrWhiteSpace($location)) { continue }
        $normalized = try { [System.IO.Path]::GetFullPath($location) } catch { $location }
        # GetFullPath keeps a trailing separator, so "C:\Scripts" and "C:\Scripts\" would
        # still be two. Trimmed everywhere except a root, where the separator is meaningful:
        # "C:\" is the root while "C:" means the current directory on that drive.
        $root = try { [System.IO.Path]::GetPathRoot($normalized) } catch { '' }
        if ($normalized.Length -gt $root.Length) { $normalized = $normalized.TrimEnd('\', '/') }
        if ($unique.Add($normalized)) { $result += $normalized }
    }
    return $result
}

function Select-UpdateCommand {
    <#
    .SYNOPSIS
        Picks the cmdlet that should perform the update on this machine
    .DESCRIPTION
        Added in v2.21, raised in review. Choosing the updater by mere presence sent a
        machine whose PowerShellGet is installed but broken - an unregistered PSGallery,
        say - straight back to Update-Script, even though discovery had just succeeded
        through PSResourceGet. The provider that answered is evidence about which one
        works, so it goes first; the other remains as a fallback for the case where the
        answering provider has no updater available.
        Returns the command name, or $null when neither exists.
    #>
    param([AllowNull()][string]$Provider)

    $order = if ($Provider -eq 'PSResourceGet') { @('Update-PSResource', 'Update-Script') }
             else { @('Update-Script', 'Update-PSResource') }

    foreach ($command in $order) {
        if (Get-Command $command -ErrorAction SilentlyContinue) { return $command }
    }
    return $null
}

function Wait-ForKeyPress {
    <#
    .SYNOPSIS
        Best-effort "press any key" pause for the update prompts
    .DESCRIPTION
        Split out in v2.21 for two reasons. It centralises the guard - Test-InteractiveConsole
        can be satisfied by a host whose RawUI still refuses ReadKey, and an exception there
        must never abort a maintenance run or a COMPLETED update.
        It also makes the interactive branches testable at all: RawUI.ReadKey blocks on a
        real console, so a test that reached it hung the whole suite until it was killed.
        A named function can be mocked; a method call on $Host cannot.
    #>
    # The failure is recorded rather than erased: at the non-Gallery prompt this pause is
    # what gives the user time to read the instruction the whole release exists to deliver,
    # and a host that refuses ReadKey turns it into a no-op that scrolls past (raised in
    # review). DETAIL, because it changes nothing about the run's outcome.
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    catch { Write-Log "Console did not accept a keypress, continuing without the pause: $_" -Level DETAIL }
}

function Get-UpdateInstruction {
    <#
    .SYNOPSIS
        The correct way to update the copy identified by Get-ScriptUpdateChannel
    .DESCRIPTION
        Split out in v2.21 so the advice can be tested. The old code had exactly two
        messages, and the one shown to every non-Gallery copy advised
        "Install-Script -Name WinClean" - which installs a SECOND copy in Documents and
        leaves the running one untouched. That is not a hint that fails to help; it
        builds the two-installation state this release exists to stop misreporting.
        Returns the lines to print.
    #>
    param(
        [AllowNull()][string]$Channel,
        [AllowNull()][string]$ExecutingPath,
        [AllowNull()][string]$Provider
    )

    $installer = '    irm https://raw.githubusercontent.com/bivlked/WinClean/main/install.ps1 | iex'

    # Listing commands for the two-installation cases. Both providers are shown because
    # either can report the other's install; whichever module is absent simply reports an
    # unknown command, which is why the caller is told to expect that (raised in review -
    # -ErrorAction cannot suppress a missing command, only a failing one).
    $inspect = @(
        '    Get-InstalledScript -Name WinClean -ErrorAction SilentlyContinue |',
        '        Select-Object Version, InstalledLocation',
        '    Get-PSResource -Name WinClean -ErrorAction SilentlyContinue |',
        '        Where-Object { $_.Type -eq ''Script'' } | Select-Object Version, InstalledLocation',
        '  (one of the two may not exist on this machine - that is expected)'
    )
    $running = if ([string]::IsNullOrWhiteSpace($ExecutingPath)) { @() }
               else { @("  The file you are running now is:", "    $ExecutingPath") }

    switch ($Channel) {
        'gallery' {
            # Name the command this machine actually has, preferring the provider that
            # discovery just proved works (raised in review). Advising Update-Script on a
            # PSResourceGet-only machine is advice that cannot be run; naming either one
            # where NEITHER exists is the same mistake twice.
            $manual = Select-UpdateCommand -Provider $Provider
            if ($manual) { return @("  To update manually: $manual -Name WinClean") }
            # "no update command is available" rather than "no provider is installed":
            # Get-Command proves the former, and a module that fails to auto-load looks
            # identical to one that is absent
            return @(
                '  No PowerShell update command is available, so this copy cannot update itself.',
                '  Download the latest release: https://github.com/bivlked/WinClean/releases/latest'
            )
        }
        'gallery-ambiguous' {
            # Several Gallery installs exist and Update-Script cannot be aimed at one of
            # them, so WinClean declines to touch any (raised in review). Naming the running
            # path matters here: it is the only way the reader can tell the copies apart.
            # Must end with something the reader can actually do (raised in review):
            # removing an install is only safe when the copies differ, so the always-works
            # answer - replace the printed file from the release - is stated first.
            return @(
                '  Several PowerShell Gallery installations of WinClean are present, and WinClean',
                '  cannot tell which one an automatic update would change - so it did not try.'
            ) + $running + @(
                '  Update it directly by replacing that file with the latest release:',
                '    https://github.com/bivlked/WinClean/releases/latest',
                '  To stop this recurring, list the installations and remove the ones you do not run:'
            ) + $inspect
        }
        'gallery-unverified' {
            # Shown after an update that reported success but left the running file at the
            # old version. Raised in review: this branch used to print the 'manual' advice,
            # telling a copy that IS Gallery-managed that it is not, and pointing it at
            # install.ps1 - which would add a second installation, the very state that made
            # the update target the wrong file in the first place.
            return @(
                '  The provider may have updated a different installation than the one you are running.'
            ) + $running + @(
                '  List the copies present and compare their locations with the path above:'
            ) + $inspect + @(
                '  Or download the latest release manually: https://github.com/bivlked/WinClean/releases/latest'
            )
        }
        'installer' {
            # Describes where the file is, not who put it there (the header of
            # Get-ScriptUpdateChannel says the same): the instruction is right either way,
            # because re-running the installer replaces exactly this location
            return @(
                '  This copy lives where install.ps1 installs. Update it by re-running the installer',
                '  in an elevated terminal:',
                $installer
            )
        }
        'oneliner' {
            return @(
                '  This copy is running from a temporary folder, which is where get.ps1 puts the',
                '  release it downloads - and it downloads the latest one every time:',
                '    irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex'
            )
        }
        default {
            # 'manual', 'unknown' and anything unforeseen: never advise Install-Script,
            # which would add a copy instead of updating this one.
            # States what was observed, not where the file came from (raised in review):
            # the location list can also be short because a provider could not be read, and
            # asserting provenance on that basis is a claim the code cannot back.
            $lead = if ($Channel -eq 'unknown') {
                '  The location of this copy could not be determined, so it cannot update itself.'
            } else {
                '  This copy does not match a PowerShell Gallery installation, so it cannot update itself.'
            }
            return @(
                $lead,
                '  Install it properly (creates an elevated desktop shortcut, updates in place):',
                $installer,
                '  Or download the release manually: https://github.com/bivlked/WinClean/releases/latest'
            )
        }
    }
}

function Find-GalleryWinClean {
    <#
    .SYNOPSIS
        Asks the PowerShell Gallery for the latest published WinClean
    .DESCRIPTION
        Added in v2.21, raised in review. Discovery called Find-Script unconditionally,
        which is a PowerShellGet command. On a machine carrying only PSResourceGet - the
        exact configuration the updater fallback below exists for - that command does not
        exist, discovery threw, the surrounding catch turned it into "no update available",
        and the entire update path was dead while every test around it passed. A fallback
        that cannot be reached is not a fallback.
        Returns Version, ReleaseNotes and Provider ('PowerShellGet' | 'PSResourceGet'), or
        $null when the providers answered and the Gallery has nothing. THROWS when every
        provider that exists failed - "could not ask" is not an answer, and swallowing it
        made an unregistered repository look identical to "you are up to date".
        Provider is carried because it is evidence: the one that just answered is known to
        work, and the updater should not then be chosen by mere presence and land on the
        one that failed.
    #>
    # Each provider is tried on its own merits (raised in review): falling back only when
    # a command is ABSENT leaves a present-but-broken PowerShellGet - an unregistered
    # PSGallery, say - masking a PSResourceGet that would have answered. Each keeps its own
    # repository registration, so one failing says nothing about the other. Discovery is
    # read-only, so trying both costs nothing but a round trip.
    $found = $null
    $provider = $null
    $failures = @()
    $answered = $false

    if (Get-Command Find-Script -ErrorAction SilentlyContinue) {
        try {
            $found = @(Find-Script -Name 'WinClean' -Repository PSGallery -ErrorAction Stop)[0]
            $answered = $true
            if ($found) { $provider = 'PowerShellGet' }
        } catch { $failures += $_; $found = $null }
    }
    if (-not $found -and (Get-Command Find-PSResource -ErrorAction SilentlyContinue)) {
        # Filtered to scripts: a module sharing the name would otherwise set the version.
        # [0] of an empty filtered array is $null, which is the intended "nothing found".
        # The provider returns the latest matching version, so no sorting is done here.
        try {
            $found = @(Find-PSResource -Name 'WinClean' -Repository PSGallery -ErrorAction Stop |
                       Where-Object { $_.Type -eq 'Script' })[0]
            $answered = $true
            if ($found) { $provider = 'PSResourceGet' }
        } catch { $failures += $_; $found = $null }
    }

    # "Could not ask" must not look like "asked, nothing newer" (raised in review - this
    # was a regression introduced by the per-provider catches above). Before them, a failing
    # Find-Script threw all the way to the caller, which logged a warning; swallowing it
    # here made an unregistered PSGallery, a TLS or proxy failure and an unpublished script
    # all read as "you are up to date", with nothing in the log at all.
    # Keyed on "nobody answered", not on "somebody failed" (also raised in review): with a
    # broken PowerShellGet beside a working PSResourceGet, a failure count above zero would
    # turn a perfectly good answer into a warning on every run.
    if (-not $answered -and $failures.Count -gt 0) {
        throw "the PowerShell Gallery could not be queried: $($failures[-1])"
    }

    if (-not $found) { return $null }
    return @{ Version = $found.Version; ReleaseNotes = $found.ReleaseNotes; Provider = $provider }
}

function Test-ScriptUpdate {
    <#
    .SYNOPSIS
        Проверяет наличие обновлений WinClean в PowerShell Gallery
    .DESCRIPTION
        Сравнивает текущую версию скрипта с последней версией в PowerShell Gallery.
        Определяет, каким способом можно обновить ИМЕННО выполняемую копию (v2.21).
    .OUTPUTS
        [hashtable] с информацией об обновлении или $null если обновление не требуется
    #>
    # Check if we can reach PSGallery
    if (-not (Test-PSGalleryConnection)) {
        return $null
    }

    try {
        $currentVersion = [Version]$script:Version

        # Query PSGallery for latest version, through whichever provider this machine has
        $galleryScript = Find-GalleryWinClean
        if (-not $galleryScript) { return $null }
        $latestVersion = [Version]$galleryScript.Version

        if ($latestVersion -gt $currentVersion) {
            # v2.21: which copy is running decides what can be offered, not whether a
            # Gallery copy exists somewhere on the machine
            return @{
                CurrentVersion = $currentVersion.ToString()
                LatestVersion  = $latestVersion.ToString()
                Channel        = Get-ScriptUpdateChannel -ExecutingPath $PSCommandPath `
                                                         -GalleryLocation (Get-InstalledWinCleanLocation)
                Provider       = $galleryScript.Provider
                ReleaseNotes   = $galleryScript.ReleaseNotes
            }
        }
    } catch {
        # Counted (raised in review): Write-Log does not touch the counters - every warning
        # in this file increments one by hand - so this one was invisible in the summary and
        # in the result JSON. The "silently fail" comment it replaces had outlived the code:
        # the level was already WARNING, and the try now covers channel classification,
        # provider lookup and two [Version] casts, any of which can throw.
        Write-Log "Update check failed: $_" -Level WARNING
        $script:Stats.WarningsCount++
    }

    return $null
}

function Invoke-ScriptUpdate {
    <#
    .SYNOPSIS
        Предлагает пользователю обновить WinClean и выполняет обновление при подтверждении
    .PARAMETER UpdateInfo
        Хэштаблица с информацией об обновлении от Test-ScriptUpdate
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$UpdateInfo
    )

    # Dynamically centered title in a 70-char box (matches the rest of the UI; v2.14
    # fixes a misaligned right border caused by hardcoded padding)
    $boxWidth = 70
    $updateTitle = "UPDATE AVAILABLE"
    $titlePadding = [math]::Max(0, $boxWidth - $updateTitle.Length)
    $titleLeftPad = [math]::Floor($titlePadding / 2)

    Write-Host ""
    Write-Host "  ╔$("═" * $boxWidth)╗" -ForegroundColor Cyan
    Write-Host "  ║$(" " * $titleLeftPad)" -NoNewline -ForegroundColor Cyan
    Write-Host $updateTitle -NoNewline -ForegroundColor Yellow
    Write-Host "$(" " * ($titlePadding - $titleLeftPad))║" -ForegroundColor Cyan
    Write-Host "  ╚$("═" * $boxWidth)╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Current version: " -NoNewline -ForegroundColor Gray
    Write-Host "v$($UpdateInfo.CurrentVersion)" -ForegroundColor White
    Write-Host "  Latest version:  " -NoNewline -ForegroundColor Gray
    Write-Host "v$($UpdateInfo.LatestVersion)" -NoNewline -ForegroundColor Green
    Write-Host " (new)" -ForegroundColor DarkGreen
    Write-Host ""

    # The channel belongs in the log line, not only on screen (raised in review): the two
    # automatic paths below print their advice with Write-Host alone, so a scheduled or CI
    # run recorded that an update existed and nothing about which copy was running or what
    # was advised - the one fact this release is about.
    Write-Log "Update available: v$($UpdateInfo.CurrentVersion) -> v$($UpdateInfo.LatestVersion) (channel: $($UpdateInfo.Channel))" -Level INFO

    # In ReportOnly mode, just inform and continue
    if ($ReportOnly) {
        Write-Log "ReportOnly mode - no update attempted" -Level INFO
        Write-Host "  ReportOnly mode - skipping update" -ForegroundColor DarkGray
        # Raised in review: the applicable method is still worth naming here. A preview run
        # is often exactly when someone is deciding how to update, and printing nothing
        # contradicted the documented promise that WinClean names the option that applies.
        foreach ($line in (Get-UpdateInstruction -Channel $UpdateInfo.Channel -ExecutingPath $PSCommandPath -Provider $UpdateInfo.Provider)) {
            Write-Host $line -ForegroundColor Gray
        }
        Write-Host ""
        return $false
    }

    # Check if interactive console is available
    if (-not (Test-InteractiveConsole)) {
        Write-Log "Non-interactive mode - no update attempted" -Level INFO
        Write-Host "  Non-interactive mode - skipping update prompt" -ForegroundColor DarkGray
        # v2.21: the instruction now follows the running copy. It used to name
        # Update-Script unconditionally, which does nothing for the copy in
        # %ProgramFiles% that the desktop shortcut starts.
        foreach ($line in (Get-UpdateInstruction -Channel $UpdateInfo.Channel -ExecutingPath $PSCommandPath -Provider $UpdateInfo.Provider)) {
            Write-Host $line -ForegroundColor Gray
        }
        Write-Host ""
        return $false
    }

    if ($UpdateInfo.Channel -ne 'gallery') {
        # Anything but a single unambiguous Gallery copy: say what applies to THIS file and
        # continue. 'gallery-ambiguous' deliberately lands here too - it IS a Gallery copy,
        # but with several installs present no updater can be aimed at this one.
        # The wording must not contradict the channel (raised in review): a
        # 'gallery-ambiguous' copy IS Gallery-managed - that is precisely why it is here.
        # 'unknown' exists precisely to promise nothing, so the log must not promise either
        # (raised in review): it used to state flatly that the copy is not Gallery-managed
        # while the console, two lines later, said its location could not be determined.
        $why = switch ($UpdateInfo.Channel) {
            'gallery-ambiguous' { "several Gallery installations exist and WinClean does not resolve which one an update would change" }
            'unknown'           { "the location of the running copy could not be determined" }
            default             { "this copy does not match a Gallery installation" }
        }
        Write-Log "Update available but $why (channel: $($UpdateInfo.Channel))" -Level INFO
        foreach ($line in (Get-UpdateInstruction -Channel $UpdateInfo.Channel -ExecutingPath $PSCommandPath -Provider $UpdateInfo.Provider)) {
            Write-Host $line -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  Press any key to continue with current version..." -ForegroundColor DarkGray
        Wait-ForKeyPress
        Write-Host ""
        return $false
    }

    # The running file is the Gallery copy, so updating it updates what runs next
    Write-Host "  Update now? (" -NoNewline -ForegroundColor Gray
    Write-Host "Y" -NoNewline -ForegroundColor Green
    Write-Host "/n): " -NoNewline -ForegroundColor Gray

    $response = Read-Host
    if ($response -ne '' -and $response -inotmatch '^[YyДд]') {
        Write-Log "Update skipped by user" -Level INFO
        Write-Host "  Update skipped. Continuing with current version..." -ForegroundColor DarkGray
        Write-Host ""
        return $false
    }

    Write-Host ""
    Write-Host "  Updating WinClean..." -ForegroundColor Cyan

    try {
        # PowerShellGet ships with PowerShell today and PSResourceGet is its replacement;
        # either can be the one present, and the one that answered discovery goes first
        # $null = ... deliberately: v2.22 made this function's return value meaningful
        # ("the run is over"), and a bare switch emits whatever the update provider writes
        # to the pipeline. A provider that returned an object would turn $true into an
        # array, and `if (Invoke-ScriptUpdate ...)` would then be deciding on the array's
        # truthiness rather than on the answer this function meant to give.
        $null = switch (Select-UpdateCommand -Provider $UpdateInfo.Provider) {
            'Update-Script'     { Update-Script -Name WinClean -Force -ErrorAction Stop }
            'Update-PSResource' { Update-PSResource -Name WinClean -Force -TrustRepository -ErrorAction Stop }
            default { throw "no update command available (neither Update-Script nor Update-PSResource)" }
        }
    } catch {
        # A warning, not an error (raised in review): the exit code is computed from
        # ErrorsCount alone, and the old level/counter pairing logged ERROR while still
        # exiting 0 - a contradiction in the one place that must be believable. Failing to
        # update the script is not a failure of the maintenance the user actually asked for.
        Write-Log "Update failed: $_" -Level WARNING
        $script:Stats.WarningsCount++
        Write-Host "  ✗ Update failed: $_" -ForegroundColor Red
        Write-Host "  Continuing with current version..." -ForegroundColor Yellow
        Write-Host ""
        return $false
    }

    # v2.21: verify against the file being executed. A provider that reports success
    # while the running file stays at the old version is the exact failure this release
    # fixes, and it must not be re-announced as "update complete".
    $observedVersion = Get-ScriptFileVersion -Path $PSCommandPath
    $verification = Get-UpdateVerification -ExpectedVersion $UpdateInfo.LatestVersion `
                                           -ObservedVersion $observedVersion
    if (-not $verification.Applied) {
        # Report what was actually read, not what this process started as: with several
        # installations present those two can differ, and naming the wrong one would send
        # the reader looking at the wrong file (raised in review).
        $detail = if ($verification.Reason -eq 'unchanged') {
            "the file still reports v$observedVersion"
        } else {
            "its version could not be read back"
        }
        Write-Log "Update reported success but $detail - continuing with the current version" -Level WARNING
        $script:Stats.WarningsCount++
        Write-Host "  ! The update reported success, but $detail." -ForegroundColor Yellow
        foreach ($line in (Get-UpdateInstruction -Channel 'gallery-unverified' -ExecutingPath $PSCommandPath)) {
            Write-Host $line -ForegroundColor Gray
        }
        Write-Host ""
        return $false
    }

    Write-Log "Update successful" -Level SUCCESS
    Write-Host ""
    Write-Host "  ✓ Update complete!" -ForegroundColor Green
    Write-Host "  Please run WinClean again to use the new version." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray

    Wait-ForKeyPress

    # v2.22: this used to call exit here, which bypassed the finally in Start-WinClean and
    # therefore had to hand-copy the result JSON write and the exit-code rule alongside it.
    # The caller now owns ending the run, through the one path that does it (raised in
    # external review). The exit code is unchanged: the entry point already derives it from
    # ErrorsCount, which is what the copied lines here were re-deriving.
    $script:Stats.Aborted = 'UpdatedAndExited'
    return $true
}

function Install-ModuleWithTimeout {
    <#
    .SYNOPSIS
        Устанавливает PowerShell модуль с таймаутом
    .DESCRIPTION
        Использует Background Job для установки модуля с возможностью прервать
        операцию по таймауту. Решает проблему бесконечного зависания Install-Module.
    .PARAMETER ModuleName
        Имя модуля для установки
    .PARAMETER TimeoutSeconds
        Таймаут в секундах (по умолчанию 120)
    .OUTPUTS
        [bool] $true если модуль успешно установлен, $false при ошибке/таймауте
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [int]$TimeoutSeconds = 120
    )

    $job = Start-Job -ScriptBlock {
        param($moduleName)
        # Set TLS 1.2 in the job process as well
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-Module -Name $moduleName -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop
    } -ArgumentList $ModuleName

    $completed = Wait-Job $job -Timeout $TimeoutSeconds

    if ($completed) {
        $jobState = $job.State
        $jobError = $null

        try {
            Receive-Job $job -ErrorAction Stop
        } catch {
            $jobError = $_
        }

        Remove-Job $job -Force

        if ($jobState -eq 'Completed' -and -not $jobError) {
            return $true
        } else {
            if ($jobError) {
                Write-Log "Module installation failed: $jobError" -Level ERROR
            }
            return $false
        }
    } else {
        # Timeout - kill the job
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force
        Write-Log "Module installation timed out after $TimeoutSeconds seconds" -Level ERROR
        return $false
    }
}

function Install-PackageProviderWithTimeout {
    <#
    .SYNOPSIS
        Устанавливает PackageProvider с таймаутом
    .DESCRIPTION
        Аналогично Install-ModuleWithTimeout, но для Install-PackageProvider
    .PARAMETER ProviderName
        Имя провайдера (обычно NuGet)
    .PARAMETER TimeoutSeconds
        Таймаут в секундах (по умолчанию 60)
    .OUTPUTS
        [bool] $true если провайдер успешно установлен, $false при ошибке/таймауте
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [string]$MinimumVersion = "2.8.5.201",

        [int]$TimeoutSeconds = 60
    )

    $job = Start-Job -ScriptBlock {
        param($providerName, $minVersion)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name $providerName -MinimumVersion $minVersion -Force -ErrorAction Stop
    } -ArgumentList $ProviderName, $MinimumVersion

    $completed = Wait-Job $job -Timeout $TimeoutSeconds

    if ($completed) {
        $jobState = $job.State
        $jobError = $null

        try {
            Receive-Job $job -ErrorAction Stop | Out-Null
        } catch {
            $jobError = $_
        }

        Remove-Job $job -Force

        if ($jobState -eq 'Completed' -and -not $jobError) {
            return $true
        } else {
            if ($jobError) {
                Write-Log "Package provider installation failed: $jobError" -Level ERROR
            }
            return $false
        }
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force
        Write-Log "Package provider installation timed out after $TimeoutSeconds seconds" -Level ERROR
        return $false
    }
}

function Get-WindowsUpdateWithTimeout {
    <#
    .SYNOPSIS
        Runs a Get-WindowsUpdate search in a background job with a timeout
    .DESCRIPTION
        v2.17 (p.15 of the audit): a hung WU agent call used to hang the whole script
        forever - fatal for an unattended nightly stand run with no one to notice.
        Read-only search, so killing the job on timeout is safe: there is nothing to
        roll back. -ErrorVariable does not cross the job boundary, so the job captures
        its own error and returns it as a plain string instead.
    .PARAMETER CategoryParamName
        'Category' or 'NotCategory' - which Get-WindowsUpdate parameter to use
    .PARAMETER CategoryValue
        Value for that parameter (e.g. "Drivers")
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Category', 'NotCategory')]
        [string]$CategoryParamName,

        [Parameter(Mandatory)]
        [string]$CategoryValue,

        [int]$TimeoutSeconds = 300
    )

    $job = Start-Job -ScriptBlock {
        param($categoryParamName, $categoryValue)
        Import-Module PSWindowsUpdate -ErrorAction Stop
        $errs = $null
        $params = @{ MicrosoftUpdate = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'errs' }
        $params[$categoryParamName] = $categoryValue
        $updates = @(Get-WindowsUpdate @params)
        [PSCustomObject]@{
            Updates    = $updates
            FirstError = if ($errs) { $errs[0].ToString() } else { $null }
        }
    } -ArgumentList $CategoryParamName, $CategoryValue

    $completed = Wait-Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            Updates    = @()
            FirstError = "search timed out after $TimeoutSeconds seconds"
        }
    }

    $jobError = $null
    $output = $null
    try {
        $output = Receive-Job $job -ErrorAction Stop
    } catch {
        $jobError = $_
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    if ($jobError -or -not $output) {
        return [PSCustomObject]@{
            Updates    = @()
            FirstError = if ($jobError) { $jobError.ToString() } else { 'search job returned no output' }
        }
    }
    return $output
}

function Test-PendingReboot {
    <#
    .SYNOPSIS
        Checks if Windows has a pending reboot from previous operations
    .DESCRIPTION
        Checks multiple registry locations and system flags to determine
        if a reboot is pending from Windows Update, CBS, file rename operations, etc.
    #>
    $rebootRequired = $false
    $reasons = @()

    # Check Windows Update reboot flag
    $wuKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if (Test-Path $wuKey) {
        $rebootRequired = $true
        $reasons += "Windows Update"
    }

    # Check Component-Based Servicing
    $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    if (Test-Path $cbsKey) {
        $rebootRequired = $true
        $reasons += "Component Servicing"
    }

    # Check Pending File Rename Operations
    $pfroKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    try {
        $pfroValue = Get-ItemProperty -Path $pfroKey -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfroValue.PendingFileRenameOperations) {
            $rebootRequired = $true
            $reasons += "File Rename Operations"
        }
    } catch { }

    # Check if Computer Rename is pending
    $compNameKey = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName"
    try {
        $activeName = (Get-ItemProperty "$compNameKey\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
        $pendingName = (Get-ItemProperty "$compNameKey\ComputerName" -ErrorAction SilentlyContinue).ComputerName
        if ($activeName -ne $pendingName) {
            $rebootRequired = $true
            $reasons += "Computer Rename"
        }
    } catch { }

    return @{
        RebootRequired = $rebootRequired
        Reasons        = $reasons
    }
}

function Get-FolderSize {
    <#
    .SYNOPSIS
        Calculates folder size in bytes
    .DESCRIPTION
        v2.17 (p.2 of the audit): Get-ChildItem wraps every single file in a full
        PSObject (ETS properties, formatting metadata) just to read one Length value -
        expensive on folders with tens of thousands of small files (npm/pip caches,
        the driver store). Walks the tree with the raw .NET enumerator instead.
        IgnoreInaccessible mirrors the old -ErrorAction SilentlyContinue tolerance.
        AttributesToSkip=ReparsePoint is a deliberate refinement, not just a port:
        following junctions/symlinks while summing could double-count the same bytes
        (WinSxS-style hardlink dedup) or loop on a cyclic junction - the old
        Get-ChildItem -Recurse call had no equivalent guard.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return 0
    }

    try {
        $options = [System.IO.EnumerationOptions]::new()
        $options.RecurseSubdirectories = $true
        $options.IgnoreInaccessible = $true
        $options.AttributesToSkip = [System.IO.FileAttributes]::ReparsePoint

        $total = 0L
        foreach ($file in [System.IO.Directory]::EnumerateFiles($Path, '*', $options)) {
            try {
                $total += [System.IO.FileInfo]::new($file).Length
            } catch { }   # vanished between enumeration and the Length read - skip it
        }
        return $total
    } catch {
        return 0
    }
}

function Get-FolderSizeChecked {
    <#
    .SYNOPSIS
        Like Get-FolderSize, but distinguishes "empty" from "could not measure"
    .DESCRIPTION
        v2.17 (p.10 of the audit): Get-FolderSize returns 0 on ANY access error, which
        Show-DiskSpaceReport read as "nothing above 100 MB" when the true answer was
        "could not check". Returns $null when Get-ChildItem hit access errors while
        walking the tree, 0 only when the path is genuinely absent or truly empty.
    #>
    param([string]$Path)

    # v2.18: Test-Path returns $false for BOTH "absent" and "present but access-denied",
    # so an unreadable folder used to report 0 (= "empty") instead of $null (= "could not
    # measure"). GetAttributes throws a *NotFound* exception only when the path is truly
    # absent; an access error surfaces as a different exception and must yield $null.
    try {
        $null = [System.IO.File]::GetAttributes($Path)
    } catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
        return 0
    } catch {
        return $null
    }

    $walkErrors = $null
    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File `
                -ErrorAction SilentlyContinue -ErrorVariable walkErrors
    if ($walkErrors) {
        return $null
    }

    $sum = ($items | Measure-Object -Property Length -Sum).Sum
    return [long]($sum ?? 0)
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formats bytes to human-readable size
    #>
    param([long]$Bytes)

    # Invariant culture (v2.17): with "{0:N2}" on ru-RU the group separator is a
    # NO-BREAK space, which mixes locales in the log and quietly breaks anything that
    # parses our own output (smoke test, stand assertions, ConvertFrom-HumanReadableSize)
    $inv = [cultureinfo]::InvariantCulture
    if ($Bytes -lt 0) { return "-" + (Format-FileSize (-$Bytes)) }
    if ($Bytes -ge 1TB) { return [string]::Format($inv, "{0:N2} TB", $Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return [string]::Format($inv, "{0:N2} GB", $Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return [string]::Format($inv, "{0:N2} MB", $Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return [string]::Format($inv, "{0:N2} KB", $Bytes / 1KB) }
    return "$Bytes B"
}

function ConvertFrom-HumanReadableSize {
    <#
    .SYNOPSIS
        Converts human-readable size string to bytes (inverse of Format-FileSize)
    .DESCRIPTION
        v2.17 (p.17 of the audit) widened localization handling. Previously failed on:
        a space-grouped thousands separator (it sat INSIDE the numeric group, which the
        old regex did not allow), "1.234,5" EU-style dot-thousands/comma-decimal (threw
        an unhandled exception instead of returning 0), the word form of bytes, and
        "MiB"/"GiB"/etc binary-unit spelling (this script's own *B literals are already
        1024-based, so the multiplier is identical to KB/MB/GB/TB).
        v2.20: a lone separator is no longer assumed to be the decimal point. The grouping
        SHAPE decides first, and only a string that could honestly be read either way is
        settled by the culture - so the result for such a string is culture-dependent.
    .PARAMETER SizeString
        The text to convert, e.g. "2.5 GB", "1,234 KB", "816 КБ".
    .PARAMETER Culture
        Consulted only for an ambiguous grouping such as "1,234", where en-US means 1234
        and ru-RU means 1.234. Defaults to the current culture, which is what the Shell
        used to format the string this function's only caller parses. Shapes that cannot
        be a grouping ("1,5", "1,2345") are decimal in every culture.
    .EXAMPLE
        ConvertFrom-HumanReadableSize "2.5 GB"  # Returns 2684354560
        ConvertFrom-HumanReadableSize "512MB"   # Returns 536870912
    .EXAMPLE
        ConvertFrom-HumanReadableSize "1,234 KB" -Culture ([cultureinfo]'en-US')  # 1263616
        ConvertFrom-HumanReadableSize "1,234 KB" -Culture ([cultureinfo]'ru-RU')  # 1264
    #>
    param(
        [string]$SizeString,
        # Only consulted for a genuinely ambiguous string (see the disambiguation below).
        # Injectable so the rule can be tested without changing the machine's locale.
        [cultureinfo]$Culture = [cultureinfo]::CurrentCulture
    )

    if (-not $SizeString) { return 0 }

    # Drop all whitespace outright (including no-break/thin-space variants) - it only
    # ever separates thousands groups or sits between the number and the unit, never
    # meaningful data.
    $normalized = ($SizeString -replace '[\u00A0\u202F\u2007\s]', '')
    $normalized = $normalized -ireplace 'байт(а|ов)?$', 'B' -ireplace 'bytes?$', 'B' -replace 'ТБ$', 'TB' -replace 'ГБ$', 'GB' -replace 'МБ$', 'MB' -replace 'КБ$', 'KB' -replace 'Б$', 'B'
    $normalized = $normalized -ireplace 'KiB$', 'KB' -ireplace 'MiB$', 'MB' -ireplace 'GiB$', 'GB' -ireplace 'TiB$', 'TB'

    # Handle formats: "2.5GB", "512MB", "100.5MB", "1234.5MB", "1234,5MB" (whitespace
    # already stripped above, so no \s* needed between the number and the unit)
    if ($normalized -notmatch '^([\d.,]+)([KMGT]?B)$') {
        return 0
    }

    $numberPart = $Matches[1]
    $unit = $Matches[2].ToUpper()

    # Decimal-separator disambiguation.
    #
    # When BOTH marks appear the answer is certain: whichever comes LAST is the decimal
    # point and the earlier one was grouping ("1.234,5" EU against "1,234.5" US).
    #
    # A LONE mark is the hard case, and v2.20 is where it was fixed. The old rule was
    # "a lone mark is the decimal point", which read the ordinary en-US thousands form
    # "1,234 KB" as 1.234 KB - low by a factor of a thousand, on the shell fallback that
    # measures the Recycle Bin.
    # The obvious repair is worse. Handing the string to [double]::TryParse with the
    # current culture looks right and is not: measured on .NET, AllowThousands does NOT
    # validate the grouping shape, so en-US reads "1,5" as 15 and "1,2345" as 12345 -
    # trading a 1000x under-read for a 10x over-read, and breaking "1,5 GB".
    # So the SHAPE is checked here first, and the culture is consulted only for a string
    # that could honestly be either reading.
    $lastComma = $numberPart.LastIndexOf(',')
    $lastDot = $numberPart.LastIndexOf('.')

    if ($lastComma -ge 0 -and $lastDot -ge 0) {
        if ($lastComma -gt $lastDot) {
            $numberPart = $numberPart.Replace('.', '').Replace(',', '.')
        } else {
            $numberPart = $numberPart.Replace(',', '')
        }
    } elseif ($lastComma -ge 0 -or $lastDot -ge 0) {
        $sep = if ($lastComma -ge 0) { ',' } else { '.' }

        # A thousands grouping is "1-3 digits, then one or more groups of exactly 3".
        # "1,5" and "1,2345" cannot be that, so there the mark is the decimal point and
        # no culture can argue otherwise.
        if ($numberPart -match "^\d{1,3}($([regex]::Escape($sep))\d{3})+$") {
            $isDecimal = $Culture.NumberFormat.NumberDecimalSeparator -eq $sep
            if (-not $isDecimal -and $Culture.NumberFormat.NumberGroupSeparator -ne $sep) {
                # The culture uses this mark for neither purpose - ru-RU groups with a
                # no-break space and would call a lone dot meaningless. Our own
                # Format-FileSize writes invariant text, so fall back to reading it that
                # way: a dot is the decimal point, a comma is grouping.
                $isDecimal = ($sep -eq '.')
            }
            if ($isDecimal) {
                $numberPart = $numberPart.Replace(',', '.')
            } else {
                $numberPart = $numberPart.Replace($sep, '')
            }
        } else {
            $numberPart = $numberPart.Replace(',', '.')
        }
    }

    $multiplier = switch ($unit) {
        'B'  { 1 }
        'KB' { 1KB }
        'MB' { 1MB }
        'GB' { 1GB }
        'TB' { 1TB }
        default { 1 }
    }

    try {
        return [long]([double]$numberPart * $multiplier)
    } catch {
        return 0
    }
}

function Resolve-PathThroughLinks {
    <#
    .SYNOPSIS
        Resolves a path through reparse points at ANY level, not just the last segment
    .DESCRIPTION
        v2.20, corrected in review. The first version of the link-aware protected-path
        check only asked whether the leaf itself was a reparse point. That closed the
        obvious case ("C:\cache" is a junction to "C:\") and left the real one open:
        "C:\cache\Windows" has no reparse attribute on the leaf, GetFullPath does not
        resolve the junction above it, and the textual comparison never matches - measured,
        with 120 real C:\Windows children visible through the link.

        So every ancestor is examined, the deepest link found is resolved, and the walk
        restarts on the rebuilt path (a resolved target can itself sit under another link).
    .OUTPUTS
        The fully resolved path, or $null when a link cannot be resolved - the caller must
        treat that as "unknown", never as "fine".
    #>
    param([Parameter(Mandatory)][string]$Path)

    $current = $Path
    # Bounded: a link loop would otherwise spin here forever
    for ($round = 0; $round -lt 64; $round++) {
        # Raised in review: the ancestor walk used to climb past the root of a UNC share.
        # Split-Path turns \\server\share into \\server, which is not a filesystem object,
        # so Get-Item failed, the fail-closed rule above answered $null, and every UNC
        # cleanup root was refused. Nothing above the volume root is ours to inspect.
        $rootPath = ''
        try { $rootPath = [System.IO.Path]::GetPathRoot($current).TrimEnd('\', '/') } catch { $rootPath = '' }

        $probe = $current
        $tail = @()
        $changed = $false

        while ($probe) {
            # Raised in review: an ancestor that could not be examined used to be silently
            # classified as "not a link" and the walk carried on upward, so an unreadable
            # junction ancestor answered "safe to empty". That is the half of the guard
            # which closes the real attack (C:\cache\Windows where C:\cache is the link),
            # and it was the half that failed open. Unknown is not safe.
            $item = $null
            try { $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop } catch { return $null }

            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                $target = $null
                try { $target = $item.ResolveLinkTarget($true) } catch { $target = $null }
                if (-not $target) { return $null }

                $current = if ($tail.Count -gt 0) {
                    Join-Path $target.FullName ($tail -join [System.IO.Path]::DirectorySeparatorChar)
                } else {
                    $target.FullName
                }
                $changed = $true
                break
            }

            $parent = Split-Path $probe -Parent
            if (-not $parent -or $parent -eq $probe) { break }
            if ($rootPath -and $parent.Length -lt $rootPath.Length) { break }
            $tail = ,(Split-Path $probe -Leaf) + $tail
            $probe = $parent
        }

        # Nothing left to resolve: this is the fully resolved answer
        if (-not $changed) { return $current }
    }

    # The bound was exhausted while links were still being followed, which means the chain
    # could not be resolved. The contract for that is $null. Returning the partially
    # resolved path (raised in review) handed Test-PathProtected a value that still
    # contained a link and was then judged on its text alone - fail-open in the one
    # function this release rewrote to fail closed.
    return $null
}

function Get-RegistryValueCount {
    <#
    .SYNOPSIS
        Counts the real values under a registry key, ignoring PowerShell's own metadata
    .DESCRIPTION
        v2.20. Privacy cleanup used to announce "cleared" without looking, because
        Remove-Item with -ErrorAction SilentlyContinue never throws. Confirming the result
        needs a before/after count, and Get-ItemProperty decorates every key with PSPath,
        PSParentPath, PSChildName, PSDrive and PSProvider - counting those would make an
        emptied key look like it still holds five entries.

        Tri-state on purpose (corrected in review before release): 0 for a key that is
        absent or genuinely empty, the count for a readable key, and $null when the key is
        there but cannot be read. The first draft returned 0 for unreadable too, which
        recreated the very bug it was written to fix: a delete that failed, followed by an
        unreadable after-read, would have counted as 0 and been reported as cleared.
    .OUTPUTS
        [int] the number of values, or $null when the key exists but cannot be read
    #>
    param([Parameter(Mandatory)][string]$Key)

    try {
        $props = Get-ItemProperty -LiteralPath $Key -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        return 0        # not there at all - nothing to clear, and nothing to worry about
    } catch {
        return $null    # there, but unreadable: refuse to answer rather than answer 0
    }

    if (-not $props) { return 0 }

    return @($props.PSObject.Properties | Where-Object {
        $_.Name -notin 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
    }).Count
}

function Test-PathProtected {
    <#
    .SYNOPSIS
        Checks whether a path must be refused as a bulk-cleanup root (v2.17: normalized,
        v2.20: link-aware)
    .DESCRIPTION
        Guards the roots listed in $script:ProtectedPaths against being emptied.
        Paths are resolved with GetFullPath first, otherwise the check is trivially
        bypassed by an 8.3 name (C:\PROGRA~1), a "\\?\" prefix, a relative path or
        a "C:\Windows\..\Windows" round trip.

        Only the roots themselves are protected, not everything below them: the script
        legitimately cleans %SystemRoot%\Temp and other subfolders. Callers that must
        never touch a subtree pass explicit paths instead.

        v2.20: the checks above compare TEXT, and GetFullPath does not resolve reparse
        points (measured, not assumed). A junction whose visible path looks innocent can
        therefore point at a protected root, and enumerating that junction lists the
        TARGET's children - deleting them deletes the real files. So an existing link is
        resolved to its final target and the same rules are applied to that.

        Only the cleanup ROOT needs this. Links found deeper in the tree are already
        harmless: Get-ChildItem -Recurse does not descend into a reparse point, and
        Remove-Item on a junction removes the link and leaves the target intact (both
        measured on a live filesystem).
    .PARAMETER SkipLinkResolution
        Internal. Set when re-checking an already-resolved target so a pathological link
        chain cannot recurse.
    #>
    param(
        [string]$Path,
        [switch]$SkipLinkResolution
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }   # nothing sane to clean

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $normalizedPath = $fullPath.TrimEnd('\', '/')
    } catch {
        # Unparseable path: refuse rather than guess
        return $true
    }

    # A volume root is always protected (v2.17). It is not in $ProtectedPaths and would
    # otherwise slip through: TEMP set to "C:\" - or an empty variable resolving to a
    # root - would hand the entire drive to the cleanup routine, running elevated.
    # Note GetFullPath does expand 8.3 names, so "C:\PROGRA~1" is caught by the list below.
    try {
        $root = [System.IO.Path]::GetPathRoot($fullPath)
        if ($root -and ($fullPath.TrimEnd('\', '/') -ieq $root.TrimEnd('\', '/'))) {
            return $true
        }
    } catch { return $true }

    foreach ($protected in $script:ProtectedPaths) {
        if ([string]::IsNullOrWhiteSpace($protected)) { continue }
        try {
            $normalizedProtected = [System.IO.Path]::GetFullPath($protected).TrimEnd('\', '/')
        } catch { continue }

        if ($normalizedPath -ieq $normalizedProtected) {
            return $true
        }
    }

    # v2.20: resolve a link root and re-check the real target (see .DESCRIPTION).
    # A path that is not there answers $false - there is nothing to delete through it, and
    # callers probe optional locations constantly. A path that EXISTS but cannot be
    # examined answers $true; the two are decided separately below.
    #
    # (This comment described the opposite of the code until review caught it: the first
    # draft lumped "cannot be inspected" in with "does not exist". A comment asserting a
    # safety property the code does not have is how the fail-open bootstrap shipped in
    # v2.17, and it ended up copied into SECURITY.md.)
    if (-not $SkipLinkResolution) {
        # A path that cannot be inspected is not the same as a path that is not there.
        # Access denied, an I/O error, a path too long: none of them mean "safe to empty",
        # and collapsing them all to "not protected" is fail-open (raised in review).
        # Same shape as Get-FolderSizeChecked: not-found is an answer, anything else is not.
        try {
            $null = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            return $false   # nothing there to clean through
        } catch [System.IO.DirectoryNotFoundException] {
            return $false
        } catch [System.IO.FileNotFoundException] {
            return $false
        } catch [System.Management.Automation.DriveNotFoundException] {
            # An unmapped or removed drive is a not-found answer too (raised in review).
            # Without this it fell to the refuse arm below, and every cleanup target on a
            # removable drive became a "Protected path skipped" WARNING - noise in exactly
            # the channel this release uses as its silent-failure alarm.
            return $false
        } catch {
            return $true    # exists in some form but cannot be examined - refuse
        }

        $resolved = Resolve-PathThroughLinks -Path $fullPath
        if (-not $resolved) {
            # A link that cannot be resolved: the real target is unknown, so protection
            # cannot be verified. Refuse rather than guess.
            return $true
        }
        if ($resolved -ne $fullPath) {
            return (Test-PathProtected -Path $resolved -SkipLinkResolution)
        }
    }

    return $false
}

function Remove-FolderContent {
    <#
    .SYNOPSIS
        Safely removes folder contents with size tracking
    .DESCRIPTION
        v2.17 (p.1 of the audit, the single largest performance item in the script):
        this used to walk $Path in full three to four times - Get-FolderSize before,
        the age filter's own recursive check, the delete, Get-FolderSize after - called
        ~35 times per run, including against multi-gigabyte TEMP and
        SoftwareDistribution. Now one enumeration pass decides eligibility AND measures
        size at the same time (a directory's age check and its size come from the same
        recursive Get-ChildItem instead of two separate walks), and after deletion each
        candidate is checked individually - Test-Path for "fully gone", a single
        Get-FolderSize scoped to just that candidate for "partially gone" (some locked
        file inside) - instead of re-walking the whole of $Path a second time.

        -RemoveFolder was removed: it had no caller left (dead since at least v2.16) and
        kept a second, untested code path alive through this rewrite for nothing.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Category,

        [string]$Description,

        [string[]]$ExcludeFile = @(),

        # v2.16: skip entries younger than N days. Used for TEMP, where deleting
        # files of currently running installers/applications breaks them mid-work.
        [int]$MinAgeDays = 0
    )

    # Safety check
    if (Test-PathProtected -Path $Path) {
        Write-Log "Protected path skipped: $Path" -Level WARNING
        return
    }

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return
    }

    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { $null }

    # Single top-level enumeration. Eligibility and size are decided together, and used
    # by both the report and the real run so "would clean" never promises more than the
    # run actually deletes.
    $candidates = @()
    foreach ($item in (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        # Skip excluded files and any directory that contains one. Deliberately
        # conservative: a directory holding an excluded file is kept whole rather than
        # partially cleaned (safe > thorough here)
        $isExcluded = [bool]($ExcludeFile | Where-Object {
            $_ -and (($item.FullName -ieq $_) -or
                     $_.StartsWith($item.FullName + '\', [System.StringComparison]::OrdinalIgnoreCase))
        })
        if ($isExcluded) { continue }

        # v2.18: carry whether Size is a real measurement. Only the no-cutoff directory
        # branch below can produce a genuinely unmeasurable size ($null from
        # Get-FolderSizeChecked); every other path is measured, an empty dir included.
        $measured = $true

        if ($item.PSIsContainer) {
            if ($cutoff) {
                # BOTH halves are required, and each covers a case the other misses:
                #   - the directory's own timestamp: an EMPTY fresh directory has no
                #     descendants to prove anything (a running installer's scratch
                #     folder looks exactly like this), and a directory written to just
                #     now can still hold nothing but old files;
                #   - the recursive walk: a folder's own LastWriteTime does not move
                #     when a GRANDchild changes, so a fresh file nested deeper would be
                #     deleted along with its old-looking parent.
                # Fail closed throughout: if the subtree cannot be fully read (ACL,
                # path length, locked folder), staleness cannot be proven, so the
                # directory is kept.
                if ($item.LastWriteTime -ge $cutoff) { continue }

                $walkErrors = $null
                $children = Get-ChildItem -LiteralPath $item.FullName -Recurse -Force `
                                -ErrorAction SilentlyContinue -ErrorVariable walkErrors
                if ($walkErrors) { continue }
                if ($children | Where-Object { $_.LastWriteTime -ge $cutoff } | Select-Object -First 1) { continue }
                # Same walk also gives the size - no second pass needed for it
                $size = ($children | Where-Object { -not $_.PSIsContainer } |
                         Measure-Object -Property Length -Sum).Sum
            } else {
                # Checked variant: plain Get-FolderSize returns 0 both for "empty" and
                # for "could not read", and that 0 would later be reported as freed
                # bytes. $null here means "unmeasured" and is now genuinely carried as
                # such (Measured=$false) instead of being flattened to a silent 0.
                $size = Get-FolderSizeChecked -Path $item.FullName
                $measured = ($null -ne $size)
            }
        } else {
            if ($cutoff -and $item.LastWriteTime -ge $cutoff) { continue }
            $size = $item.Length
        }

        $candidates += [pscustomobject]@{ Item = $item; Size = [long]($size ?? 0); Measured = $measured }
    }

    $totalSize = [long](($candidates | Measure-Object -Property Size -Sum).Sum ?? 0)

    if ($ReportOnly) {
        if ($totalSize -gt 0 -and $Description) {
            Write-Log "Would clean: $Description - $(Format-FileSize $totalSize)" -Level DETAIL
        }
        # v2.18: an unmeasurable candidate contributes 0 to $totalSize, so a set that is
        # entirely unmeasurable would otherwise report nothing at all. Name it instead of
        # staying silent (the estimate genuinely excludes these).
        $unmeasuredCount = @($candidates | Where-Object { -not $_.Measured }).Count
        if ($unmeasuredCount -gt 0 -and $Description) {
            Write-Log "$Description - $unmeasuredCount item(s) present but not measurable (excluded from the estimate)" -Level DETAIL
        }
        return
    }

    if ($candidates.Count -eq 0) {
        return
    }

    try {
        $freed = 0
        $unmeasuredRemoved = 0
        foreach ($c in $candidates) {
            $item = $c.Item
            try {
                # Handle read-only files
                if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                    $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                }
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            } catch { }

            if (-not (Test-Path -LiteralPath $item.FullName -ErrorAction SilentlyContinue)) {
                # Fully gone. Credit the pre-deletion size only if it was a real
                # measurement; an unmeasured directory (v2.18) is removed but its freed
                # bytes are unknown, so it is counted apart rather than booked as 0.
                if ($c.Measured) { $freed += $c.Size } else { $unmeasuredRemoved++ }
            } elseif ($item.PSIsContainer) {
                # Partially deleted (some locked file inside) - re-measure only this one
                # subtree, not the whole of $Path. Get-FolderSizeChecked, not
                # Get-FolderSize: the latter reports 0 both for "empty" and for "could
                # not read", and reading that 0 as "nothing left" would credit the whole
                # directory as freed while its files are still sitting on disk.
                $remaining = Get-FolderSizeChecked -Path $item.FullName
                if ($null -ne $remaining) {
                    $freed += [math]::Max(0, $c.Size - $remaining)
                }
                # $null: the remainder is unknown, so claim nothing rather than overstate
                # v2.18: a directory that was unmeasurable to begin with and only partially
                # deleted freed an unknown amount too - count it so it is not silently lost.
                if (-not $c.Measured) { $unmeasuredRemoved++ }
            }
            # A file that still exists (locked) contributes 0 - correctly nothing freed
        }

        if ($unmeasuredRemoved -gt 0) {
            # Honest about the gap instead of silently understating: these directories
            # were deleted but their size could not be measured beforehand.
            Write-Log "Removed $unmeasuredRemoved item(s) whose size could not be measured; freed space is underreported for them" -Level DETAIL
        }

        if ($freed -gt 0) {
            # Update statistics (synchronized hashtable handles thread-safety)
            $script:Stats.TotalFreedBytes += $freed

            # Update category (not thread-safe, but acceptable for reporting)
            if (-not $script:Stats.FreedByCategory.ContainsKey($Category)) {
                $script:Stats.FreedByCategory[$Category] = 0
            }
            $script:Stats.FreedByCategory[$Category] += $freed

            if ($Description) {
                Write-Log "$Description - $(Format-FileSize $freed)" -Level SUCCESS
            }
        } elseif ($totalSize -gt 0 -and $Description) {
            # v2.16: silence here is indistinguishable from "there was nothing to do".
            # Say it out loud - this is exactly how the Controlled Folder Access bug hid:
            # deletions were blocked without an error and the log simply stayed quiet.
            # Compare explicitly against 'enabled': the field is tri-state, and the
            # string 'unknown' is truthy in PowerShell - a plain truthiness test would
            # confidently blame Controlled Folder Access for a state never checked
            $reason = switch ($script:Stats.ControlledFolderAccess) {
                'enabled' { ' (Controlled Folder Access is enabled and may be blocking it)' }
                'unknown' { ' (files are probably locked, or Controlled Folder Access is blocking it - the check itself failed)' }
                default   { ' (files are probably locked by a running process)' }
            }
            Write-Log "$Description - nothing freed, $(Format-FileSize $totalSize) still present$reason" -Level WARNING
            $script:Stats.WarningsCount++
        }
    } catch {
        Write-Log "Error cleaning $Path`: $_" -Level WARNING
        $script:Stats.WarningsCount++
    }
}

function Remove-FilesByPattern {
    <#
    .SYNOPSIS
        Removes files matching a pattern with size tracking
    .DESCRIPTION
        Handles file patterns (like *.roslynobjectin) that Remove-FolderContent can't handle.

        v2.17 (p.18 of the audit): this was the one delete path in the whole script with
        no protected-path check and no age filter - safe today because the only caller
        passes a single fixed pattern under %APPDATA%, but that made it a latent risk for
        the next caller. Mirrors Remove-FolderContent's guards for consistency.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Category,

        [string]$Description,

        [int]$MinAgeDays = 0
    )

    $files = Get-Item -Path $Pattern -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }

    if (-not $files) {
        return
    }

    # Skip anything whose containing folder is itself a protected root, and anything
    # younger than the age cutoff (matches Remove-FolderContent's -MinAgeDays intent:
    # a file belonging to something still running should not be deleted mid-use)
    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $files = $files | Where-Object {
        (-not (Test-PathProtected -Path $_.DirectoryName)) -and
        ($MinAgeDays -le 0 -or $_.LastWriteTime -lt $cutoff)
    }

    if (-not $files) {
        return
    }

    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    $totalSize = [long]($totalSize ?? 0)

    if ($ReportOnly) {
        if ($totalSize -gt 0 -and $Description) {
            Write-Log "Would clean: $Description - $(Format-FileSize $totalSize)" -Level DETAIL
        }
        return
    }

    $freedSize = 0
    foreach ($file in $files) {
        try {
            $fileSize = $file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $file.FullName)) {
                $freedSize += $fileSize
            }
        } catch { }
    }

    if ($freedSize -gt 0) {
        $script:Stats.TotalFreedBytes += $freedSize

        if (-not $script:Stats.FreedByCategory.ContainsKey($Category)) {
            $script:Stats.FreedByCategory[$Category] = 0
        }
        $script:Stats.FreedByCategory[$Category] += $freedSize

        if ($Description) {
            Write-Log "$Description - $(Format-FileSize $freedSize)" -Level SUCCESS
        }
    }
}

function New-SystemRestorePoint {
    <#
    .SYNOPSIS
        Creates system restore point using Windows PowerShell (for compatibility)
    #>
    param([string]$Description = "WinClean Maintenance")

    if ($SkipRestore) {
        Write-Log "Restore point creation skipped (parameter)" -Level INFO
        return $true
    }

    if ($ReportOnly) {
        Write-Log "Would create restore point: $Description" -Level INFO
        return $true
    }

    Write-Log "Creating system restore point..." -Level INFO

    try {
        # Checkpoint-Computer doesn't work in PowerShell 7, use Windows PowerShell
        # Note (v2.14): Windows silently skips restore point creation if one was made in
        # the last 24h (SystemRestorePointCreationFrequency default = 1440 minutes).
        # For a maintenance script that can run daily this means points were almost never
        # created - temporarily lift the limit for this call only, then restore it.
        $scriptBlock = @"
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue

                `$srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
                `$prevFreq = (Get-ItemProperty -Path `$srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
                Set-ItemProperty -Path `$srKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -Force
                try {
                    Checkpoint-Computer -Description "$Description" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                } finally {
                    if (`$null -ne `$prevFreq) {
                        Set-ItemProperty -Path `$srKey -Name SystemRestorePointCreationFrequency -Value `$prevFreq -Type DWord -Force
                    } else {
                        Remove-ItemProperty -Path `$srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
                    }
                }
                Write-Output "SUCCESS"
            } catch {
                Write-Output "ERROR: `$_"
            }
"@

        # Use Windows PowerShell 5.1 (Checkpoint-Computer not available in PS7).
        # v2.17 (p.14 of the audit): this was the one external call in the whole script
        # with no timeout at all, and VSS is known to hang for minutes.
        #
        # v2.17 (regression caught on the stand): the timeout rewrite first passed the
        # script via Start-Process -ArgumentList @(..., '-Command', $scriptBlock).
        # Start-Process concatenates ArgumentList with spaces and does NOT re-quote its
        # elements, so a $Description containing spaces (it always does - "WinClean
        # 2026-07-20 19:00") was split into positional arguments and Checkpoint-Computer
        # failed every time. -EncodedCommand (base64 of the UTF-16LE script) sidesteps
        # command-line quoting entirely. Invisible to the test suite because a real
        # Checkpoint-Computer only runs on a live machine, not in the sandbox.
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock))

        $outFile = [System.IO.Path]::GetTempFileName()
        $errFile = [System.IO.Path]::GetTempFileName()

        # v2.17 (p.13 of the audit): a hard kill of this process (or of the child, e.g.
        # via "End process tree") skips the child's own finally above, leaving
        # SystemRestorePointCreationFrequency at 0 forever. Read the current value from
        # out here so the marker can restore the RIGHT value on the next run instead of
        # just assuming the shipped default.
        $srKeyOuter = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $prevFreqOuter = (Get-ItemProperty -Path $srKeyOuter -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-RunMarker -Phase 'RestorePointFrequencyOverride' -Data @{ PreviousValue = $prevFreqOuter }

        $childKilled = $false
        $childExited = $true    # only meaningful once a kill has been attempted
        try {
            $proc = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
                -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

            $timeoutMs = 120000  # 2 minutes - a restore point should never legitimately take this long
            if (-not $proc.WaitForExit($timeoutMs)) {
                $proc.Kill($true)
                $childKilled = $true
                # v2.20, corrected in review: Kill returns once termination has been
                # REQUESTED, not once the tree is gone. Without this wait the finally
                # below could read the creation frequency while the dying child was still
                # writing 0 into it, see a non-zero value, conclude there was nothing to
                # repair and delete the marker - leaving the frequency pinned at 0 with no
                # record of it, which is exactly the damage this mechanism exists for.
                $childExited = $proc.WaitForExit(5000)
                throw "restore point creation timed out after $($timeoutMs / 1000) seconds"
            }

            $result = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)
        } finally {
            Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue

            # A killed child never ran its own finally, so the registry override it set
            # is still in place - repair it here and now. Clearing the marker
            # unconditionally would throw away the record of exactly the damage this
            # mechanism exists for, so it survives whenever the repair did not.
            #
            # v2.20: this repair now runs on BOTH paths. A child that exits normally can
            # still have failed its own finally (a transient registry error), and the
            # parent then deleted the marker anyway - leaving the creation frequency
            # pinned at 0 indefinitely with nothing left to make a later run retry.
            # Restore-RestorePointFrequency is idempotent by design: it returns $true
            # without touching anything when the value is no longer 0, so verifying on the
            # normal path costs nothing and turns an assumption into a check.
            if (Restore-RestorePointFrequency -PreviousValue $prevFreqOuter) {
                if ($childKilled -and -not $childExited) {
                    # Raised in review: the wait above has a bound, and a child that
                    # outlives it can still write the override AFTER this check passed.
                    # Keeping the marker costs one repair attempt on the next run;
                    # clearing it here would lose the only record that anything happened.
                    Write-Log "Restore point child was killed but had not exited 5 seconds later - the marker is kept, because it can still re-apply the override after this check" -Level WARNING
                    $script:Stats.WarningsCount++
                } else {
                    Clear-RunMarker
                }
            } else {
                $how = if ($childKilled) { 'was killed' } else { 'exited normally' }
                Write-Log "Restore point child $how but its registry override could not be undone - the marker is kept so the next run retries" -Level WARNING
                $script:Stats.WarningsCount++
            }
        }

        if ($result -like "SUCCESS*") {
            Write-Log "Restore point created: $Description" -Level SUCCESS
            return $true
        } else {
            throw $result
        }
    } catch {
        Write-Log "Failed to create restore point: $_" -Level WARNING
        $script:Stats.WarningsCount++
        return $false
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              UPDATE FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Update-WindowsSystem {
    <#
    .SYNOPSIS
        Updates Windows including optional driver updates
    #>
    Write-Log "WINDOWS UPDATE" -Level TITLE
    Update-Progress -Activity "Windows Update" -Status "Checking for updates..."

    if ($SkipUpdates) {
        Write-Log "Windows Update skipped (parameter)" -Level INFO
        return
    }

    # Early exit for ReportOnly - don't install modules or modify system
    if ($ReportOnly) {
        Write-Log "Would check and install: Windows Updates and Drivers" -Level DETAIL
        return
    }

    if (-not (Test-InternetConnection)) {
        # v2.21: a warning, not an error, for the same reason a missing winget is one - the
        # exit code is computed from ErrorsCount alone, so an offline machine ended every
        # run with code 1 no matter how completely the cleanup succeeded, and a laptop that
        # runs maintenance away from the network reported failure forever. Having no
        # connectivity is a state of the environment, not a failure of this run. It stays
        # visible: the warning is logged and counted, and the result JSON carries
        # AppUpdatesStatus = 'skipped-offline' for the whole Updates phase.
        Write-Log "No internet connection - skipping Windows Update" -Level WARNING
        $script:Stats.WarningsCount++
        return
    }

    # Check Windows Update service
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if (-not $wuService) {
        Write-Log "Windows Update service not found!" -Level ERROR
        $script:Stats.ErrorsCount++
        return
    }

    if ($wuService.Status -ne 'Running') {
        Write-Log "Starting Windows Update service..." -Level INFO
        try {
            Start-Service wuauserv -ErrorAction Stop
        } catch {
            Write-Log "Failed to start Windows Update service: $_" -Level ERROR
            $script:Stats.ErrorsCount++
            return
        }
    }

    try {
        # Install PSWindowsUpdate if needed
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            # Clear any lingering progress bar before module installation
            Write-Progress -Activity "Windows Update" -Completed -ErrorAction SilentlyContinue

            # Check PowerShell Gallery availability first
            Write-Log "Checking PowerShell Gallery availability..." -Level INFO
            if (-not (Test-PSGalleryConnection)) {
                Write-Log "PowerShell Gallery is unavailable" -Level ERROR
                Write-Log "Please check your internet connection or install PSWindowsUpdate manually:" -Level INFO
                Write-Log "  Install-Module PSWindowsUpdate -Force -Scope CurrentUser" -Level INFO
                $script:Stats.ErrorsCount++
                return
            }

            Write-Log "Installing PSWindowsUpdate module..." -Level INFO

            # Ensure NuGet provider with timeout
            $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nuget -or $nuget.Version -lt [version]"2.8.5.201") {
                Write-Log "Installing NuGet provider..." -Level INFO
                if (-not (Install-PackageProviderWithTimeout -ProviderName "NuGet" -TimeoutSeconds 60)) {
                    Write-Log "Failed to install NuGet provider - Windows Update skipped" -Level ERROR
                    Write-Log "Try manual installation: Install-PackageProvider -Name NuGet -Force" -Level INFO
                    $script:Stats.ErrorsCount++
                    return
                }
                Write-Log "NuGet provider installed" -Level SUCCESS
            }

            # Install PSWindowsUpdate module with timeout
            if (-not (Install-ModuleWithTimeout -ModuleName "PSWindowsUpdate" -TimeoutSeconds 120)) {
                Write-Log "Failed to install PSWindowsUpdate - Windows Update skipped" -Level ERROR
                Write-Log "Try manual installation: Install-Module PSWindowsUpdate -Force -Scope CurrentUser" -Level INFO
                $script:Stats.ErrorsCount++
                return
            }
            Write-Log "PSWindowsUpdate installed" -Level SUCCESS
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop
        # v2.17: with two copies installed (CurrentUser + AllUsers) .Version returns an
        # ARRAY, and every later comparison silently degrades into an array filter
        $moduleVersion = (Get-Module PSWindowsUpdate | Sort-Object Version -Descending |
                          Select-Object -First 1).Version
        Write-Log "PSWindowsUpdate v$moduleVersion loaded" -Level INFO

        # Register Microsoft Update service
        $muService = Get-WUServiceManager -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Microsoft Update" }
        if (-not $muService) {
            Write-Log "Registering Microsoft Update service..." -Level INFO
            Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }

        # Search for updates
        Write-Log "Searching for updates..." -Level INFO

        Write-Log "System Updates" -Level SECTION
        $sysResult = Get-WindowsUpdateWithTimeout -CategoryParamName NotCategory -CategoryValue "Drivers"
        $systemUpdates = @($sysResult.Updates)

        Write-Log "Driver Updates" -Level SECTION
        $drvResult = Get-WindowsUpdateWithTimeout -CategoryParamName Category -CategoryValue "Drivers"
        $driverUpdates = @($drvResult.Updates)

        $totalUpdates = $systemUpdates.Count + $driverUpdates.Count
        $wuSearchErrors = @($sysResult.FirstError, $drvResult.FirstError) | Where-Object { $_ }

        # v2.17: report search errors regardless of how many updates were found. The
        # check used to live inside the "zero updates" branch, so a failed system search
        # paired with a successful driver search was reported as a clean run.
        if ($wuSearchErrors) {
            Write-Log "Update search completed with errors: $($wuSearchErrors[0])" -Level WARNING
            Write-Log "Some updates may not have been discovered" -Level DETAIL
            $script:Stats.WarningsCount++
        }

        if ($totalUpdates -eq 0) {
            # Distinguish "no updates" from "search failed" (v2.14) - previously a
            # failed search was reported as "Windows is up to date"
            if (-not $wuSearchErrors) {
                Write-Log "Windows is up to date" -Level SUCCESS
            }
            return
        }

        Write-Log "Found $($systemUpdates.Count) system updates, $($driverUpdates.Count) driver updates" -Level INFO

        # Display updates
        if ($systemUpdates.Count -gt 0) {
            Write-Host ""
            Write-Host "  System Updates:" -ForegroundColor Cyan
            foreach ($update in $systemUpdates) {
                $size = if ($update.Size) { " ($(Format-FileSize $update.Size))" } else { "" }
                Write-Host "    - " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($update.KB)" -NoNewline -ForegroundColor Yellow
                Write-Host " $($update.Title)$size" -ForegroundColor Gray
            }
        }

        if ($driverUpdates.Count -gt 0) {
            Write-Host ""
            Write-Host "  Driver Updates:" -ForegroundColor Cyan
            foreach ($update in $driverUpdates) {
                Write-Host "    - " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($update.Title)" -ForegroundColor Gray
            }
        }

        Write-Host ""

        # Install updates
        Write-Log "Installing updates..." -Level INFO

        $installParams = @{
            MicrosoftUpdate = $true
            AcceptAll       = $true
            IgnoreReboot    = $true
            ErrorAction     = 'SilentlyContinue'
        }

        # Ask the cmdlet what it supports instead of guessing from a version number.
        # v2.17: the old check compared against 2.3.0, a version PSWindowsUpdate never
        # shipped, so the branch was dead - and would have misfired on an array anyway.
        $installCmd = Get-Command Install-WindowsUpdate -ErrorAction SilentlyContinue
        if ($installCmd -and -not $installCmd.Parameters.ContainsKey('IgnoreReboot')) {
            $installParams.Remove('IgnoreReboot')
            if ($installCmd.Parameters.ContainsKey('AutoReboot')) {
                $installParams['AutoReboot'] = $false
            }
        }

        # v2.17 (p.15 of the audit, partial): the two searches above got a job-based
        # timeout - they are read-only, so killing the job on timeout is free. Install-
        # WindowsUpdate is not wrapped the same way: it actually applies updates, and
        # force-killing the job would not necessarily cancel the in-flight WU agent
        # call, leaving system state that a stand run cannot verify without a live
        # reproduction. Deferred - see MyAI-dtx8.
        $results = Install-WindowsUpdate @installParams

        # Handle null/empty results (possible silent error)
        if (-not $results) {
            Write-Log "Windows Update returned no results (possible error)" -Level WARNING
            $script:Stats.WarningsCount++
            return
        }

        # Count installed updates.
        # v2.16: 'Downloaded' means fetched but NOT applied, so counting it as installed
        # produced "All N updates installed successfully" for updates still pending.
        $installed = @($results | Where-Object { $_.Result -eq 'Installed' }).Count
        $downloaded = @($results | Where-Object { $_.Result -eq 'Downloaded' }).Count
        $failed = @($results | Where-Object { $_.Result -eq 'Failed' }).Count

        $script:Stats.WindowsUpdatesCount = $installed

        if ($failed -gt 0) {
            Write-Log "Installed: $installed, Failed: $failed" -Level WARNING
            $script:Stats.WarningsCount += $failed
        } elseif ($installed -gt 0) {
            Write-Log "All $installed updates installed successfully" -Level SUCCESS
        }

        if ($downloaded -gt 0) {
            Write-Log "$downloaded update(s) downloaded but not yet applied - a reboot is needed" -Level DETAIL
            $script:Stats.RebootRequired = $true
        }

        # Check reboot status
        if (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue) {
            $script:Stats.RebootRequired = $true
            Write-Log "Reboot required to complete updates" -Level WARNING
        }

    } catch {
        Write-Log "Windows Update error: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    }
}

function Update-Applications {
    <#
    .SYNOPSIS
        Updates applications via winget
    #>
    Write-Log "APPLICATION UPDATES (WINGET)" -Level TITLE
    Update-Progress -Activity "Application Updates" -Status "Checking winget..."

    if ($SkipUpdates) {
        Write-Log "Application updates skipped (parameter)" -Level INFO
        $script:Stats.AppUpdatesStatus = 'skipped-parameter'
        return
    }

    if (-not (Test-InternetConnection)) {
        # v2.21: warning, matching Update-WindowsSystem above - see the reasoning there.
        # Both halves read the same memoised connectivity check, so this status describes
        # the whole Updates phase, not only the winget half.
        Write-Log "No internet connection - skipping app updates" -Level WARNING
        $script:Stats.AppUpdatesStatus = 'skipped-offline'
        $script:Stats.WarningsCount++
        return
    }

    # Find winget
    $wingetPath = $null

    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $wingetPath = $wingetCmd.Source
    }

    if (-not $wingetPath) {
        $standardPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        if (Test-Path $standardPath) {
            $wingetPath = $standardPath
        }
    }

    if (-not $wingetPath) {
        # v2.21: a warning, not an error. The absence of an optional third-party tool is a
        # property of the machine, not a failure of this run - by the same rule that makes
        # a machine without Docker or Visual Studio a normal machine here.
        # It mattered because the exit code is computed from ErrorsCount alone: every run
        # on a machine without App Installer ended with code 1 while all nine phases
        # completed, so any scheduler, CI job or test harness reading that code saw a
        # failed run forever. A winget that IS present and then fails is still reported;
        # its severity depends on whether the run can carry on - the upgrade check failing
        # outright and an unhandled exception are errors, while a stale source, a timeout
        # or a partly failed batch are warnings.
        Write-Log "Winget not found - skipping application updates (install App Installer from Microsoft Store to enable them)" -Level WARNING
        $script:Stats.AppUpdatesStatus = 'skipped-no-winget'
        $script:Stats.WarningsCount++
        return
    }

    # From here winget exists and is about to be asked, but the status is only raised to
    # 'checked' once the check actually returns a list (raised in review): setting it here
    # meant a timed-out or failing check still reported 'checked' with AppUpdatesOffered = 0
    # - precisely the ambiguity this field was added to remove.
    $script:Stats.AppUpdatesStatus = 'check-failed'

    try {
        # Update sources only if not in ReportOnly mode (source update modifies state)
        if (-not $ReportOnly) {
            Write-Log "Updating winget sources..." -Level INFO
            # Run with timeout to prevent hanging
            # v2.20: the job's own exit code is returned as well. Only completion was
            # checked before, and a completed job is not a successful winget: a corrupt
            # source fails, the job still reaches Completed, and the upgrade list below
            # was then built from stale data without a word in the log.
            $job = Start-Job -ScriptBlock {
                param($path)
                & $path source update 2>&1 | Out-String
                $LASTEXITCODE
            } -ArgumentList $wingetPath
            $completed = $job | Wait-Job -Timeout 120  # 2 minutes timeout
            if (-not $completed) {
                $job | Stop-Job
                Write-Log "Winget source update timed out - package list may be stale" -Level WARNING
                $script:Stats.WarningsCount++
            } else {
                # v2.20, corrected in review: "no usable result" is a failure in its own
                # right. When the winget entry is a WindowsApps AppExecLink stub - passes
                # Test-Path, but will not start once App Installer is deregistered - the
                # job still reaches Completed, Receive-Job swallows the error and
                # $LASTEXITCODE is never set, so the last output element is $null. The old
                # guard short-circuited on exactly that and said nothing, which made an
                # unusable winget the one silent path left in this block. Measured by the
                # reviewer: one output element, and it was $null.
                # [int] on a non-numeric last line would also have thrown; TryParse cannot.
                $jobState = $job.State
                $jobOutput = @($job | Receive-Job -ErrorAction SilentlyContinue)
                $sourceExit = if ($jobOutput.Count -gt 0) { $jobOutput[-1] } else { $null }
                $exitValue = 0
                $exitKnown = $null -ne $sourceExit -and [int]::TryParse([string]$sourceExit, [ref]$exitValue)

                if ($jobState -ne 'Completed' -or -not $exitKnown) {
                    Write-Log "Winget source update produced no usable exit code (job state: $jobState) - package list may be stale" -Level WARNING
                    $script:Stats.WarningsCount++
                } elseif ($exitValue -ne 0) {
                    Write-Log "Winget source update failed (exit code $exitValue) - package list may be stale" -Level WARNING
                    $script:Stats.WarningsCount++
                }
            }
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
        }

        # Get available updates (use --include-unknown to match actual upgrade behavior)
        Write-Log "Checking for app updates..." -Level INFO

        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempErrorFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $wingetPath `
            -ArgumentList "upgrade", "--include-unknown", "--accept-source-agreements", "--disable-interactivity" `
            -NoNewWindow -RedirectStandardOutput $tempFile -RedirectStandardError $tempErrorFile -PassThru

        # Wait with timeout (5 minutes for check operation)
        $timeoutMs = 300000
        if (-not $process.WaitForExit($timeoutMs)) {
            $process.Kill($true)
            Write-Log "Winget upgrade check timed out after 5 minutes" -Level WARNING
            $script:Stats.WarningsCount++
            Remove-Item $tempFile, $tempErrorFile -Force -ErrorAction SilentlyContinue
            return
        }

        $output = Get-Content $tempFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errorOutput = Get-Content $tempErrorFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue

        # Check if winget command failed (any non-zero exit code is an error)
        if ($process.ExitCode -ne 0) {
            Write-Log "Winget upgrade check failed (exit code: $($process.ExitCode))" -Level ERROR
            if ($errorOutput) {
                Write-Log "Error: $errorOutput" -Level ERROR
            }
            $script:Stats.ErrorsCount++
            return
        }

        # The check returned a usable list, so its count now means something
        $script:Stats.AppUpdatesStatus = 'checked'

        # Parse output for update count (language-independent approach)
        # Uses table separator "---" as marker, then counts all data lines
        $updateCount = 0
        $lines = $output -split "`n"
        $foundSeparator = $false

        foreach ($line in $lines) {
            # Look for table separator line (works in any language)
            if ($line -match "^-{10,}") {
                $foundSeparator = $true
                continue
            }

            # Count lines after separator that look like package entries
            # Must have multiple columns (name, id, version, available, source)
            if ($foundSeparator) {
                $trimmed = $line.Trim()
                # First table ends at the first blank line - stop there to avoid counting
                # the second "require explicit targeting" table (not covered by --all)
                if (-not $trimmed) { break }
                # Skip footer text ("X upgrades available") and lines with too few columns
                if ($trimmed -notmatch "^\d+\s+(upgrade|обновлен)" -and
                    $trimmed -notmatch "^(No |Нет )" -and
                    ($trimmed -split '\s{2,}').Count -ge 3) {
                    $updateCount++
                }
            }
        }

        # v2.19: record what winget offered as soon as we know it - in every path,
        # including ReportOnly and a later failed upgrade. This is the honest figure;
        # the actual installed count is not knowable from `winget upgrade --all`.
        $script:Stats.AppUpdatesOffered = $updateCount

        if ($updateCount -eq 0) {
            Write-Log "All applications are up to date" -Level SUCCESS
            return
        }

        Write-Log "Available Updates" -Level SECTION
        Write-Host $output

        if ($ReportOnly) {
            Write-Log "Report mode - $updateCount updates available but not installed" -Level INFO
            return
        }

        Write-Log "Installing $updateCount application updates..." -Level INFO
        Write-Log "This may take several minutes..." -Level INFO

        # Run upgrade (--include-unknown matches the check above)
        $upgradeArgs = @(
            "upgrade", "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--disable-interactivity",
            "--include-unknown"
        )

        $upgradeProcess = Start-Process -FilePath $wingetPath -ArgumentList $upgradeArgs `
            -NoNewWindow -PassThru

        # Wait with timeout (20 minutes for upgrade operation - can take long with many updates)
        $timeoutMs = 1200000
        if (-not $upgradeProcess.WaitForExit($timeoutMs)) {
            $upgradeProcess.Kill($true)   # $true: kill spawned installers too (v2.17)
            Write-Log "Winget upgrade timed out after 20 minutes" -Level WARNING
            $script:Stats.WarningsCount++
            return
        }

        if ($upgradeProcess.ExitCode -eq 0) {
            # AppUpdatesOffered was already recorded above; a zero exit means the command
            # succeeded, not that every offered package installed, so nothing to add here.
            Write-Log "Application updates completed successfully" -Level SUCCESS
        } else {
            # v2.16: decode the exit code. A bare number ("code: -1978335188") tells the
            # user nothing, and adjacent codes mean opposite things - 0x8A15002B is not
            # an error at all, while 0x8A15002C means some upgrades genuinely failed.
            # Values verified against the documented winget error list - do not edit
            # from memory, adjacent codes have unrelated meanings.
            $wingetErrors = @{
                -1978335189 = '0x8A15002B - no applicable update found'
                -1978335188 = '0x8A15002C - some applications failed to upgrade'
                -1978335224 = '0x8A150008 - downloading installer failed'
                -1978335225 = '0x8A150007 - manifest version newer than this winget client'
                -1978335221 = '0x8A15000B - configured source information is corrupt'
                -1978334967 = '0x8A150109 - restart required to finish installation'
            }
            $code = $upgradeProcess.ExitCode
            $meaning = if ($wingetErrors.ContainsKey($code)) {
                $wingetErrors[$code]
            } else {
                '0x{0:X8} - unrecognized winget exit code' -f $code
            }

            if ($code -eq -1978335189) {
                # Nothing to upgrade is a normal outcome, not a warning. AppUpdatesOffered
                # reflects the parsed table above; the summary reports it as "offered", not
                # "installed", so there is nothing to correct here.
                Write-Log "Application updates: $meaning" -Level DETAIL
            } else {
                if ($code -eq -1978334967) {
                    # Installation finished but needs a reboot to take effect
                    $script:Stats.RebootRequired = $true
                }
                Write-Log "Application updates finished with $meaning" -Level WARNING
                $script:Stats.WarningsCount++
            }
        }

    } catch {
        Write-Log "Application update error: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              CLEANUP FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Clear-TempFiles {
    <#
    .SYNOPSIS
        Cleans temporary files and system caches
    #>
    Write-Log "Temporary Files" -Level SECTION

    # Define temp paths and remove duplicates (e.g., $env:TEMP often equals $env:LOCALAPPDATA\Temp).
    # v2.17: entries built from an empty environment variable are dropped. Under SYSTEM or
    # a stripped scheduled-task environment "$env:LOCALAPPDATA\Temp" collapses to "\Temp",
    # which GetFullPath roots at the CURRENT DRIVE - so the script would wipe D:\Temp.
    # An empty $env:TEMP made GetFullPath throw outright and killed the whole function.
    $tempPaths = @(
        @{ Path = $env:TEMP; Desc = "User Temp"; Base = $env:TEMP }
        @{ Path = "$env:SystemRoot\Temp"; Desc = "Windows Temp"; Base = $env:SystemRoot }
        @{ Path = "$env:LOCALAPPDATA\Temp"; Desc = "Local Temp"; Base = $env:LOCALAPPDATA }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Base) } | ForEach-Object {
        try {
            $_.Path = [System.IO.Path]::GetFullPath($_.Path)
            $_
        } catch {
            Write-Log "Skipping temp path '$($_.Desc)': $_" -Level DETAIL
        }
    } | Group-Object Path | ForEach-Object { $_.Group[0] }

    foreach ($item in $tempPaths) {
        # Exclude the active log file - it lives in $env:TEMP by default and would
        # otherwise be deleted mid-run, losing everything logged so far.
        # MinAgeDays (v2.16): TEMP holds working files of running installers and
        # applications; deleting today's entries can break them mid-operation.
        Remove-FolderContent -Path $item.Path -Category "Temp" -Description $item.Desc `
            -ExcludeFile $script:LogPath -MinAgeDays 1
    }
}

function Clear-BrowserCaches {
    <#
    .SYNOPSIS
        Cleans browser caches (Edge, Chrome, Brave, Yandex, Opera, Opera GX, Firefox).
        All profiles are cleaned for Chrome, Edge and Firefox; the default profile for the rest
    #>
    Write-Log "Browser Caches" -Level SECTION

    # Define browser cache paths
    $browsers = @{
        "Edge" = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage"
        )
        "Chrome" = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage"
        )
        "Yandex" = @(
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Code Cache"
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\GPUCache"
        )
        "Opera" = @(
            # Chromium disk caches live under LOCALAPPDATA; APPDATA kept for older layouts
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache"
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\Code Cache"
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\GPUCache"
            "$env:APPDATA\Opera Software\Opera Stable\Cache"
            "$env:APPDATA\Opera Software\Opera Stable\Code Cache"
            "$env:APPDATA\Opera Software\Opera Stable\GPUCache"
        )
        "Opera GX" = @(
            "$env:LOCALAPPDATA\Opera Software\Opera GX Stable\Cache"
            "$env:LOCALAPPDATA\Opera Software\Opera GX Stable\Code Cache"
            "$env:LOCALAPPDATA\Opera Software\Opera GX Stable\GPUCache"
            "$env:APPDATA\Opera Software\Opera GX Stable\Cache"
            "$env:APPDATA\Opera Software\Opera GX Stable\Code Cache"
            "$env:APPDATA\Opera Software\Opera GX Stable\GPUCache"
        )
        "Brave" = @(
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache"
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\GPUCache"
        )
    }

    # Clean standard browsers in parallel
    $allPaths = @()
    foreach ($browser in $browsers.Keys) {
        foreach ($path in $browsers[$browser]) {
            if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
                $allPaths += @{ Browser = $browser; Path = $path }
            }
        }
    }

    # Also check for additional Chrome/Edge profiles (with full cache set)
    foreach ($browser in @("Chrome", "Edge")) {
        $basePath = if ($browser -eq "Chrome") {
            "$env:LOCALAPPDATA\Google\Chrome\User Data"
        } else {
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        }

        if (Test-Path $basePath) {
            Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "Profile *" } | ForEach-Object {
                    # Add same cache types as Default profile (fixed in v2.1)
                    $profileCacheTypes = @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage")
                    foreach ($cacheType in $profileCacheTypes) {
                        $profileCache = Join-Path $_.FullName $cacheType
                        if (Test-Path $profileCache) {
                            $allPaths += @{ Browser = "$browser $($_.Name)"; Path = $profileCache }
                        }
                    }
                }
        }
    }

    # Clean in parallel (with ReportOnly check)
    if ($allPaths.Count -gt 0) {
        # Get browser names for logging
        $browserNames = ($allPaths | Select-Object -ExpandProperty Browser -Unique) -join ', '

        if ($ReportOnly) {
            # v2.18: $sizeBefore comes from Get-FolderSize, which returns 0 for BOTH an
            # empty cache and an unreadable one, so "Would clean ... - 0 B" announced a
            # cleanup that would free nothing. Re-measure with the checked variant to tell
            # "empty" (confirmed 0) from "could not measure" ($null) and word it honestly.
            $checked = @($allPaths | ForEach-Object { Get-FolderSizeChecked -Path $_.Path })
            if ($checked -contains $null) {
                Write-Log "Browser caches ($browserNames): present, size could not be fully measured" -Level DETAIL
            } else {
                $checkedSum = [long](($checked | Measure-Object -Sum).Sum ?? 0)
                if ($checkedSum -gt 0) {
                    Write-Log "Would clean browser caches ($browserNames) - $(Format-FileSize $checkedSum)" -Level DETAIL
                } else {
                    Write-Log "Browser cache folders found ($browserNames), but they are empty" -Level DETAIL
                }
            }
        } else {
            # v2.20, corrected in review: both sides are now measured PER PATH with the
            # SAME function. "Before" used Get-FolderSize (raw enumerator, inaccessible
            # files silently skipped, reparse points excluded) while "after" used
            # Get-FolderSizeChecked, so the two numbers did not describe the same set of
            # files and a genuine deletion could be subtracted into the "nothing freed"
            # branch. Measuring before only in this branch also stops ReportOnly from
            # walking every cache twice.
            $beforeMeasurements = @($allPaths | ForEach-Object { Get-FolderSizeChecked -Path $_.Path })

            # Actual cleanup
            $allPaths | ForEach-Object -Parallel {
                $item = $_
                $path = $item.Path

                if (Test-Path -LiteralPath $path) {
                    try {
                        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    } catch { }
                }
            } -ThrottleLimit 8

            # Measure size after cleanup to get actual freed space.
            #
            # v2.20: checked measurement. Get-FolderSize returns 0 both for "empty" and for
            # "could not read", so an after-walk that lost access - the cache folder is
            # being recreated by a browser that just started, ACLs changed mid-run - turned
            # into "freed everything we measured before". The delta is only computed when
            # every folder answered; otherwise the bytes stay unattributed instead of being
            # invented.
            $afterMeasurements = @($allPaths | ForEach-Object { Get-FolderSizeChecked -Path $_.Path })

            # Pair the two sides path by path. The previous rule discarded the delta for
            # ALL caches when a single one of ~30 could not be measured; only the paths
            # that actually failed are dropped now.
            $measuredBefore = [long]0
            $measuredAfter = [long]0
            $afterUnmeasured = 0
            for ($i = 0; $i -lt $allPaths.Count; $i++) {
                $beforeOne = $beforeMeasurements[$i]
                $afterOne = $afterMeasurements[$i]
                if ($null -eq $beforeOne -or $null -eq $afterOne) {
                    $afterUnmeasured++
                    continue
                }
                $measuredBefore += $beforeOne
                $measuredAfter += $afterOne
            }

            # Clamped once over the total, not per path (raised in review). TotalFreedBytes
            # means net space reclaimed, so clamping each path separately would report
            # 100 MB when one cache shrank by 100 MB while another was recreated and grew
            # by 80 MB - inventing 80 MB of "freed" space the disk never got back.
            $freedSpace = [math]::Max(0, $measuredBefore - $measuredAfter)

            # Update statistics with actual freed space (not estimated)
            if ($freedSpace -gt 0) {
                $script:Stats.TotalFreedBytes += $freedSpace
                if (-not $script:Stats.FreedByCategory.ContainsKey("Browser")) {
                    $script:Stats.FreedByCategory["Browser"] = 0
                }
                $script:Stats.FreedByCategory["Browser"] += $freedSpace
                Write-Log "Browser caches cleaned ($browserNames) - $(Format-FileSize $freedSpace)" -Level SUCCESS
                if ($afterUnmeasured -gt 0) {
                    Write-Log "Browser caches: $afterUnmeasured folder(s) could not be measured - their share is not included above" -Level DETAIL
                }
            } elseif ($afterUnmeasured -gt 0) {
                Write-Log "Browser caches ($browserNames): cleaned, but $afterUnmeasured folder(s) could not be measured - freed space not counted" -Level DETAIL
            } else {
                # v2.16: was logged as SUCCESS. A running browser locks its cache, so
                # "cleaned" with zero freed was a plain lie to the user
                Write-Log "Browser caches: nothing freed ($browserNames) - close the browsers and retry" -Level DETAIL
            }
        }
    }

    # Handle Firefox profiles separately
    # Note: cache2/startupCache live under LOCALAPPDATA (the APPDATA profile only
    # holds roaming data like bookmarks/prefs) - fixed in v2.14
    $firefoxProfileRoots = @(
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
        "$env:APPDATA\Mozilla\Firefox\Profiles"
    )
    foreach ($firefoxProfiles in $firefoxProfileRoots) {
        if (Test-Path $firefoxProfiles) {
            Get-ChildItem -Path $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-FolderContent -Path "$($_.FullName)\cache2" -Category "Browser" -Description "Firefox cache"
                Remove-FolderContent -Path "$($_.FullName)\startupCache" -Category "Browser"
            }
        }
    }
}

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Cleans Windows Update download cache
    #>
    Write-Log "Windows Update Cache" -Level SECTION

    # v2.17: if the update phase left payloads waiting for a reboot, this folder holds
    # them. Deleting it here means gigabytes get downloaded again after the restart,
    # while the run proudly reports the freed space.
    if ($script:Stats.RebootRequired) {
        Write-Log "Updates are pending a reboot - keeping the cache (it holds their payloads)" -Level DETAIL
        return
    }

    if ($ReportOnly) {
        $size = Get-FolderSize -Path "$env:SystemRoot\SoftwareDistribution\Download"
        Write-Log "Would clean: Windows Update cache - $(Format-FileSize $size)" -Level DETAIL
        return
    }

    # Restart only what WE stopped (v2.17). Starting every stopped service afterwards
    # would silently re-enable one an administrator had disabled on purpose - and the
    # recovery path would repeat that mistake on the next run.
    $toRestart = @(
        foreach ($svcName in @('wuauserv', 'bits')) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { $svcName }
        }
    )

    if ($toRestart.Count -eq 0) {
        # Nothing of ours to stop or restore: no marker, no service juggling
        Write-Log "Windows Update services are not running - cleaning the cache directly" -Level DETAIL -NoLog
        Remove-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\Download" -Category "WinUpdate" -Description "Windows Update cache"
        return
    }

    # Stop services with try/finally to ensure they restart. v2.17 (p.13 of the audit):
    # a hard kill of this process skips that finally too, leaving wuauserv/bits
    # stopped forever - the marker lets the NEXT run detect and recover that, and it
    # names the exact services so recovery cannot overreach either.
    Write-Log "Stopping Windows Update services..." -Level DETAIL -NoLog
    Set-RunMarker -Phase 'WUServiceStop' -Data @{ ServicesToRestart = $toRestart }
    try {
        Stop-Service -Name $toRestart -Force -ErrorAction SilentlyContinue

        # v2.16: Stop-Service returns before the service has actually reached Stopped,
        # and its failure was swallowed by -ErrorAction SilentlyContinue. Cleaning while
        # the service still holds the files silently leaves the cache in place.
        $stillRunning = @()
        foreach ($svcName in $toRestart) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) { continue }
            try {
                $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [timespan]::FromSeconds(30))
            } catch {
                $stillRunning += $svcName
            }
        }
        if ($stillRunning.Count -gt 0) {
            # Skip entirely rather than half-delete: with the service holding the files,
            # cleanup would remove an arbitrary subset and report a misleading number
            Write-Log "Service(s) still running after 30s: $($stillRunning -join ', ') - skipping cache cleanup" -Level WARNING
            $script:Stats.WarningsCount++
        } else {
            # Clean
            Remove-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\Download" -Category "WinUpdate" -Description "Windows Update cache"
        }
    } finally {
        # Restart exactly what was running before, and keep the marker if any of them
        # refused - the next run then retries instead of leaving them down silently
        $restartFailed = $false
        foreach ($svcName in $toRestart) {
            try {
                Start-Service -Name $svcName -ErrorAction Stop
            } catch {
                Write-Log "Could not restart $svcName : $_" -Level WARNING
                $script:Stats.WarningsCount++
                $restartFailed = $true
            }
        }
        if (-not $restartFailed) { Clear-RunMarker }
    }
}

function Get-RecycleBinSize {
    <#
    .SYNOPSIS
        Gets the total size of items in the Recycle Bin
    #>
    $totalSize = [long]0
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.Namespace(0xA)
        foreach ($item in $recycleBin.Items()) {
            try {
                # ExtendedProperty is exact and works for folders too (verified on 25H2:
                # a deleted folder reports the total size of its contents)
                $itemSize = $item.ExtendedProperty("System.Size")
                if ($itemSize) {
                    $totalSize += [long]$itemSize
                } else {
                    # Fallback for shells that do not expose the property.
                    # v2.17: column index 3 is Size. Index 2 is "Date deleted" - the old
                    # code parsed a date as a size, which quietly contributed zero.
                    $sizeStr = $recycleBin.GetDetailsOf($item, 3)
                    # Guard against a column-order change: a size always has a digit
                    # followed by a unit, a date does not
                    if ($sizeStr -and $sizeStr -match '\d.*[A-Za-zА-Яа-я]') {
                        $totalSize += ConvertFrom-HumanReadableSize $sizeStr
                    }
                }
            } catch {
                # Ignore errors for individual items
            }
        }
    } catch {
        # Return 0 if we can't access recycle bin
    }
    return $totalSize
}

function Get-RecycleBinItemCount {
    <#
    .SYNOPSIS
        Number of items in the Recycle Bin (v2.17)
    .DESCRIPTION
        Emptiness must be decided by count, not by size: a size of zero can also mean
        "the shell would not tell us", and skipping the cleanup in that case leaves the
        bin full while reporting it as already empty.
    #>
    try {
        $shell = New-Object -ComObject Shell.Application
        return @($shell.Namespace(0xA).Items()).Count
    } catch {
        return -1   # unknown
    }
}

function Clear-WinCleanRecycleBin {
    <#
    .SYNOPSIS
        Empties the Recycle Bin with size tracking
    #>
    Write-Log "Recycle Bin" -Level SECTION

    # Measure size and count before cleanup. v2.17: emptiness is decided by the item
    # count - a zero size can also mean the shell refused to report one, and skipping
    # on that basis would leave a full bin described as already empty.
    $sizeBefore = Get-RecycleBinSize
    $itemCount = Get-RecycleBinItemCount

    if ($ReportOnly) {
        if ($itemCount -eq 0) {
            Write-Log "Recycle Bin is empty" -Level DETAIL
        } elseif ($sizeBefore -gt 0) {
            Write-Log "Would clean: Recycle Bin - $(Format-FileSize $sizeBefore)" -Level DETAIL
        } else {
            Write-Log "Would clean: Recycle Bin - $itemCount item(s), size unavailable" -Level DETAIL
        }
        return
    }

    if ($itemCount -eq 0) {
        Write-Log "Recycle Bin is already empty" -Level INFO
        return
    }

    try {
        # Use full cmdlet path to explicitly call the built-in cmdlet
        Microsoft.PowerShell.Management\Clear-RecycleBin -Force -ErrorAction Stop

        # Update statistics
        $script:Stats.TotalFreedBytes += $sizeBefore
        if (-not $script:Stats.FreedByCategory.ContainsKey("Recycle Bin")) {
            $script:Stats.FreedByCategory["Recycle Bin"] = 0
        }
        $script:Stats.FreedByCategory["Recycle Bin"] += $sizeBefore

        if ($sizeBefore -gt 0) {
            Write-Log "Recycle Bin emptied - $(Format-FileSize $sizeBefore)" -Level SUCCESS
        } else {
            # Emptied, but the shell never told us how much it held (v2.17)
            Write-Log "Recycle Bin emptied ($itemCount item(s), size was unavailable)" -Level SUCCESS
        }
    } catch {
        # Fallback to COM method
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            $items = $recycleBin.Items()
            $count = $items.Count

            $items | ForEach-Object {
                Remove-Item -LiteralPath $_.Path -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Measure what was actually freed - some items may have failed to
            # delete silently (v2.14; previously the full size was always counted)
            $freed = [math]::Max(0, $sizeBefore - (Get-RecycleBinSize))
            if ($freed -gt 0) {
                $script:Stats.TotalFreedBytes += $freed
                if (-not $script:Stats.FreedByCategory.ContainsKey("Recycle Bin")) {
                    $script:Stats.FreedByCategory["Recycle Bin"] = 0
                }
                $script:Stats.FreedByCategory["Recycle Bin"] += $freed
            }

            if ($freed -gt 0) {
                Write-Log "Recycle Bin emptied ($count items) - $(Format-FileSize $freed)" -Level SUCCESS
            } else {
                # v2.17: was SUCCESS regardless - a bin that refused to empty looked identical
                Write-Log "Recycle Bin: $count item(s) processed, nothing freed - some items may be locked" -Level WARNING
                $script:Stats.WarningsCount++
            }
        } catch {
            Write-Log "Could not empty Recycle Bin: $_" -Level WARNING
            $script:Stats.WarningsCount++
        }
    }
}

function Clear-SystemCaches {
    <#
    .SYNOPSIS
        Cleans various Windows system caches
    #>
    Write-Log "System Caches" -Level SECTION

    $systemPaths = @(
        @{ Path = "$env:SystemRoot\Prefetch"; Desc = "Prefetch" }
        @{ Path = "$env:LOCALAPPDATA\IconCache.db"; Desc = "Icon cache"; File = $true }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Desc = "Thumbnail cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\WER"; Desc = "Error reports (local)" }
        @{ Path = "$env:ProgramData\Microsoft\Windows\WER"; Desc = "Error reports (system)" }
        @{ Path = "$env:ProgramData\USOShared\Logs"; Desc = "Update logs" }
        @{ Path = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"; Desc = "Windows Store cache" }
    )

    foreach ($item in $systemPaths) {
        if ($item.File) {
            if (Test-Path -LiteralPath $item.Path -ErrorAction SilentlyContinue) {
                $fileSize = (Get-Item -LiteralPath $item.Path -ErrorAction SilentlyContinue).Length
                $fileSize = [long]($fileSize ?? 0)

                if ($ReportOnly) {
                    Write-Log "Would clean: $($item.Desc) - $(Format-FileSize $fileSize)" -Level DETAIL
                } else {
                    Remove-Item -LiteralPath $item.Path -Force -ErrorAction SilentlyContinue

                    if (Test-Path -LiteralPath $item.Path -ErrorAction SilentlyContinue) {
                        # File is locked (e.g. IconCache.db held by Explorer) -
                        # don't count it as freed (v2.14)
                        Write-Log "$($item.Desc) is in use - skipped" -Level DETAIL
                    } else {
                        if ($fileSize -gt 0) {
                            $script:Stats.TotalFreedBytes += $fileSize
                            if (-not $script:Stats.FreedByCategory.ContainsKey("System")) {
                                $script:Stats.FreedByCategory["System"] = 0
                            }
                            $script:Stats.FreedByCategory["System"] += $fileSize
                        }

                        Write-Log "$($item.Desc) cleaned" -Level DETAIL
                    }
                }
            }
        } else {
            Remove-FolderContent -Path $item.Path -Category "System" -Description $item.Desc
        }
    }

    # Delivery Optimization cache: files are owned by the DO service, so raw folder
    # deletion usually fails silently - use the supported cmdlet instead (v2.14)
    #
    # v2.16: the cache lives under the NetworkService profile, not in ProgramData.
    # The old ProgramData path does not exist on Windows 11 (verified on 25H2), so
    # every size measurement returned 0 and multi-gigabyte cleanups were reported as
    # "0 B". Both locations are probed - the ProgramData one is kept for older builds.
    # Note: Get-DeliveryOptimizationPerfSnap.CacheSizeBytes is NOT usable here - it
    # reflects recent transfer activity (490 MB) rather than cache size on disk (7.5 GB).
    $doPaths = @(
        "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization"
        "$env:ProgramData\Microsoft\Windows\DeliveryOptimization"
    ) | Where-Object { Test-Path $_ -ErrorAction SilentlyContinue }

    $doSizeOf = {
        $total = 0
        foreach ($p in $doPaths) { $total += Get-FolderSize -Path $p }
        $total
    }

    if ($ReportOnly) {
        $doSize = & $doSizeOf
        if ($doSize -gt 0) {
            Write-Log "Would clean: Delivery Optimization - $(Format-FileSize $doSize)" -Level DETAIL
        }
    } elseif (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        try {
            $doSizeBefore = & $doSizeOf
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
            $doFreed = [math]::Max(0, $doSizeBefore - (& $doSizeOf))
            if ($doFreed -gt 0) {
                $script:Stats.TotalFreedBytes += $doFreed
                if (-not $script:Stats.FreedByCategory.ContainsKey("System")) {
                    $script:Stats.FreedByCategory["System"] = 0
                }
                $script:Stats.FreedByCategory["System"] += $doFreed
                Write-Log "Delivery Optimization cache - $(Format-FileSize $doFreed)" -Level SUCCESS
            } elseif ($doPaths.Count -eq 0) {
                # Nothing to measure: say so instead of claiming a clean-up happened (v2.16)
                Write-Log "Delivery Optimization: cmdlet ran, cache location not found - freed size unknown" -Level DETAIL
            } elseif ($doSizeBefore -gt 0) {
                # v2.20: this was a WARNING and fired on healthy systems. The measurement
                # covers the WHOLE Delivery Optimization folder, but the supported cmdlet
                # only removes cached content - the service's own logs and state files stay
                # and are not ours to delete. So "size did not change" after a cmdlet that
                # reported success is not evidence of failure, it is evidence that the
                # remainder was never cache. Reproduced on the EN stand VM twice in a row
                # (2 MB left behind), where it pushed the run over its warning budget.
                #
                # A genuine failure still surfaces: the cmdlet runs with -ErrorAction Stop,
                # so an actual error lands in the catch below as a warning.
                # Deliberately does NOT claim the cache was cleared: an unchanged folder
                # size cannot prove that every remaining byte is non-cache. It states what
                # is actually known - the cmdlet reported success and this much is still
                # on disk - and leaves the reader to judge (tightened in review; the first
                # wording asserted "cache cleared", which is the opposite failure of the
                # warning it replaced).
                Write-Log "Delivery Optimization: cmdlet reported success, $(Format-FileSize $doSizeBefore) still on disk (the folder also holds service logs and state, which it does not remove)" -Level DETAIL
            } else {
                Write-Log "Delivery Optimization cache was already empty" -Level DETAIL
            }
        } catch {
            Write-Log "Delete-DeliveryOptimizationCache failed: $_" -Level WARNING
            $script:Stats.WarningsCount++
            foreach ($p in $doPaths) {
                Remove-FolderContent -Path $p -Category "System" -Description "Delivery Optimization"
            }
        }
    } else {
        foreach ($p in $doPaths) {
            Remove-FolderContent -Path $p -Category "System" -Description "Delivery Optimization"
        }
    }
}

function Clear-EventLogs {
    <#
    .SYNOPSIS
        Clears Windows Event Logs (excluding critical ones)
    .DESCRIPTION
        v2.17 (p.3 of the audit): each log used to be cleared via a separate `wevtutil`
        process (30-80ms each, and a run can see 100-300 eligible logs). Replaced with
        EventLogSession.ClearLog, the in-process .NET API wevtutil itself calls - same
        underlying WinAPI, no process-spawn overhead per log.
    #>
    Write-Log "Event Logs" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would clean: Windows Event Logs" -Level DETAIL
        return
    }

    try {
        # Enumerate only logs worth clearing: enabled, non-empty, Administrative/Operational.
        # This skips ~1000 Analytic/Debug/empty channels - much faster and avoids
        # chronic partial-failure warnings (v2.14; was: wevtutil el over all channels)
        # v2.20: keep the enumeration errors. A wholesale failure (Event Log service down,
        # WMI broken) produced an empty list, zero failed clears and therefore the success
        # branch: "Event logs cleared (0 logs)" while nothing was touched.
        # v2.20, corrected in review: the enumeration result is kept BEFORE filtering.
        # Deciding on the filtered list meant that 40 readable channels out of 510 with
        # 470 enumeration errors produced a plain "Event logs cleared (40 logs)" SUCCESS,
        # and that an empty filter result on a perfectly healthy machine was reported as
        # a failed enumeration. Those are different states and now read differently.
        $enumErrors = $null
        $allLogs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue -ErrorVariable enumErrors)
        $logs = $allLogs | Where-Object {
            $_.RecordCount -gt 0 -and
            $_.IsEnabled -and
            $_.LogName -ne 'Security' -and  # Keep the main Security log (exact match)
            $_.LogType -in @('Administrative', 'Operational')
        }

        $clearedCount = 0
        $failedCount = 0
        foreach ($log in $logs) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
                $clearedCount++
            } catch {
                $failedCount++
            }
        }

        $enumErrorCount = @($enumErrors).Count

        if ($allLogs.Count -eq 0) {
            # Nothing could be listed at all - the Event Log service is down or the API
            # is broken. Clearing zero channels is not a clean system.
            Write-Log "Event logs: channels could not be enumerated ($enumErrorCount error(s)) - nothing was cleared" -Level WARNING
            $script:Stats.WarningsCount++
        } else {
            # Partial loss is reported separately from the clearing result, because the
            # channels that failed to list were never even candidates and their records
            # are still on disk.
            #
            # DETAIL, not WARNING (raised in review): a listing error is a gap in coverage,
            # not the failure of an operation we claimed to perform, and this machine is
            # not evidence about anyone else's - measured here on 25H2 it is 510 channels
            # with zero errors, but third-party or protected channels can error out
            # routinely elsewhere, and a warning that fires every run teaches people to
            # ignore warnings. Total failure below stays a warning. Worded as errors rather
            # than channels because that is what was counted.
            if ($enumErrorCount -gt 0) {
                Write-Log "Event logs: $enumErrorCount error(s) while listing channels - whatever they refer to was never considered for clearing" -Level DETAIL
            }

            if ($failedCount -gt 0) {
                Write-Log "Event logs cleared: $clearedCount, failed: $failedCount" -Level WARNING
                $script:Stats.WarningsCount++
            } elseif ($clearedCount -eq 0) {
                Write-Log "Event logs: no channel needed clearing" -Level DETAIL
            } else {
                Write-Log "Event logs cleared ($clearedCount logs)" -Level SUCCESS
            }
        }
    } catch {
        Write-Log "Error clearing event logs: $_" -Level WARNING
        $script:Stats.WarningsCount++
    }
}

function Clear-DNSCache {
    <#
    .SYNOPSIS
        Flushes DNS resolver cache
    .DESCRIPTION
        Clears the DNS client cache to resolve potential DNS issues
        and free up memory used by cached DNS entries
    #>
    Write-Log "DNS Cache" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would flush: DNS resolver cache" -Level DETAIL
        return
    }

    try {
        # v2.17: prefer the cmdlet - it is locale-independent and raises real errors.
        # ipconfig was doing the same work a second time, and its success was matched
        # against English/Russian text that depends on the console code page.
        if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
            Clear-DnsClientCache -ErrorAction Stop
            Write-Log "DNS cache flushed successfully" -Level SUCCESS
        } else {
            $null = ipconfig /flushdns 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                Write-Log "DNS cache flushed successfully" -Level SUCCESS
            } else {
                Write-Log "DNS cache flush failed (ipconfig exit code: $exitCode)" -Level WARNING
                $script:Stats.WarningsCount++
            }
        }
    } catch {
        Write-Log "Error flushing DNS cache: $_" -Level WARNING
        $script:Stats.WarningsCount++
    }
}

function Clear-PrivacyTraces {
    <#
    .SYNOPSIS
        Clears privacy-related traces (Run history, recent files, etc.)
    .DESCRIPTION
        Removes various Windows usage traces including:
        - Run dialog history (Win+R)
        - Recent documents MRU
        - Explorer search history
    #>
    Write-Log "Privacy Traces" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would clean: Run dialog history, Recent documents MRU" -Level DETAIL
        return
    }

    $clearedItems = @()

    # v2.20: success is now confirmed by looking, not by the absence of an exception.
    # Remove-Item with -ErrorAction SilentlyContinue cannot throw, so the catch blocks
    # here were dead code and "$clearedItems += ..." ran unconditionally: the log said
    # "Privacy traces cleared: Explorer typed paths" even when policy or permissions had
    # rejected the deletion and the key was still sitting there, fully populated.
    # RunMRU joins this list rather than keeping its own copy of the same logic: it used
    # the pre-count as proof of success in exactly the way the others did (caught in
    # review before release, when the first version of this fix left it behind).
    $historyKeys = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU";         Label = 'Run history' }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths";     Label = 'Explorer typed paths' }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"; Label = 'Explorer search history' }
    )
    foreach ($entry in $historyKeys) {
        if (-not (Test-Path $entry.Path)) { continue }

        $before = Get-RegistryValueCount -Key $entry.Path
        if ($null -eq $before) {
            # Present but unreadable: we cannot tell whether there is anything to clear,
            # and silently moving on would look identical to "there was nothing"
            Write-Log "$($entry.Label): key could not be read - left untouched" -Level WARNING
            $script:Stats.WarningsCount++
            continue
        }
        # An empty key is not a trace that was cleared - it is a trace that was not there
        if ($before -eq 0) { continue }

        Remove-Item -Path $entry.Path -Force -ErrorAction SilentlyContinue
        New-Item -Path $entry.Path -Force -ErrorAction SilentlyContinue | Out-Null

        $after = Get-RegistryValueCount -Key $entry.Path
        if ($null -eq $after) {
            Write-Log "$($entry.Label): result could not be verified - not counted as cleared" -Level WARNING
            $script:Stats.WarningsCount++
        } elseif ($after -eq 0) {
            $clearedItems += $entry.Label
        } else {
            Write-Log "$($entry.Label): $after of $before entries remain - not cleared" -Level WARNING
            $script:Stats.WarningsCount++
        }
    }

    # Clear Recent documents folder
    $recentFolder = [Environment]::GetFolderPath('Recent')
    if (-not [string]::IsNullOrWhiteSpace($recentFolder) -and (Test-Path $recentFolder)) {
        $recentBefore = @(Get-ChildItem -LiteralPath $recentFolder -Force -ErrorAction SilentlyContinue).Count
        if ($recentBefore -gt 0) {
            Get-ChildItem -LiteralPath $recentFolder -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            # Report what actually went, not what was there before the attempt
            $recentAfter = @(Get-ChildItem -LiteralPath $recentFolder -Force -ErrorAction SilentlyContinue).Count
            $removed = $recentBefore - $recentAfter
            if ($removed -gt 0) {
                $clearedItems += "Recent documents ($removed items)"
            }
            if ($recentAfter -gt 0) {
                Write-Log "Recent documents: $recentAfter of $recentBefore items could not be removed (in use?)" -Level WARNING
                $script:Stats.WarningsCount++
            }
        }
    }

    if ($clearedItems.Count -gt 0) {
        Write-Log "Privacy traces cleared: $($clearedItems -join ', ')" -Level SUCCESS
    } else {
        Write-Log "No privacy traces found to clear" -Level INFO
    }
}

function Set-WindowsTelemetry {
    <#
    .SYNOPSIS
        Configures Windows telemetry settings
    .DESCRIPTION
        Disables or minimizes Windows telemetry data collection
        by setting appropriate registry values and group policies
    #>
    param(
        [switch]$Disable
    )

    if (-not $Disable) {
        return
    }

    Write-Log "WINDOWS TELEMETRY CONFIGURATION" -Level TITLE

    if ($ReportOnly) {
        Write-Log "Would configure: Disable Windows telemetry" -Level DETAIL
        return
    }

    $changesApplied = @()

    try {
        # Set telemetry level to Security (0 = Security, 1 = Basic, 2 = Enhanced, 3 = Full)
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) {
            New-Item -Path $dataCollectionKey -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # AllowTelemetry = 0 (Security - minimum telemetry, only for Enterprise/Education)
        # For other editions, setting to 1 (Basic) is the minimum allowed
        # Use EditionID from registry (language-independent, fixed in v2.1)
        $editionId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name EditionID -ErrorAction SilentlyContinue).EditionID
        $telemetryLevel = if ($editionId -match "Enterprise|Education") { 0 } else { 1 }

        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value $telemetryLevel -Type DWord -Force
        $changesApplied += "Telemetry level set to $telemetryLevel"

        # Disable Customer Experience Improvement Program
        Set-ItemProperty -Path $dataCollectionKey -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force
        $changesApplied += "Feedback notifications disabled"

        # Disable Application Telemetry
        $appCompatKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
        if (-not (Test-Path $appCompatKey)) {
            New-Item -Path $appCompatKey -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $appCompatKey -Name "AITEnable" -Value 0 -Type DWord -Force
        $changesApplied += "Application telemetry disabled"

        # Disable Advertising ID
        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) {
            New-Item -Path $advertisingKey -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force
        $changesApplied += "Advertising ID disabled"

        # Disable Windows Error Reporting
        $werKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
        if (-not (Test-Path $werKey)) {
            New-Item -Path $werKey -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $werKey -Name "Disabled" -Value 1 -Type DWord -Force
        $changesApplied += "Windows Error Reporting disabled"

        Write-Log "Telemetry settings applied:" -Level SUCCESS
        foreach ($change in $changesApplied) {
            Write-Log "  - $change" -Level DETAIL
        }

        Write-Log "Note: Some changes may require a system restart to take effect" -Level INFO

    } catch {
        Write-Log "Error configuring telemetry: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    }
}

function Clear-WindowsOld {
    <#
    .SYNOPSIS
        Removes Windows.old folder with user confirmation
    #>
    $windowsOldPath = "$env:SystemDrive\Windows.old"

    if (-not (Test-Path $windowsOldPath)) {
        return
    }

    Write-Log "Previous Windows Installation" -Level SECTION

    $size = Get-FolderSize -Path $windowsOldPath
    $sizeFormatted = Format-FileSize $size

    Write-Log "Found Windows.old folder ($sizeFormatted)" -Level WARNING

    if ($ReportOnly) {
        Write-Log "Would clean: Windows.old - $sizeFormatted" -Level DETAIL
        return
    }

    # Check if running in interactive console (fixed in v2.1)
    if (-not (Test-InteractiveConsole)) {
        # Non-interactive: skip with safe default (don't delete without confirmation)
        Write-Log "Non-interactive mode - skipping Windows.old deletion (requires user confirmation)" -Level INFO
        return
    }

    # Interactive prompt with timeout
    Write-Host ""
    Write-Host "  This folder contains files from a previous Windows installation." -ForegroundColor DarkGray
    Write-Host "  Delete Windows.old? (" -NoNewline -ForegroundColor Yellow
    Write-Host "Y" -NoNewline -ForegroundColor Green
    Write-Host "/n, default " -NoNewline -ForegroundColor Yellow
    Write-Host "Y" -NoNewline -ForegroundColor Green
    Write-Host " in 15 sec): " -NoNewline -ForegroundColor Yellow

    $timeout = 15
    $startTime = Get-Date
    $response = ""

    # Clear keyboard buffer
    while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }

    while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Enter" -or $key.KeyChar -match "[YyДд]") {
                $response = "Y"
                Write-Host "Y" -ForegroundColor Green
                break
            } elseif ($key.KeyChar -match "[NnНн]") {
                $response = "N"
                Write-Host "N" -ForegroundColor Red
                break
            }
        }

        $remaining = $timeout - [int]((Get-Date) - $startTime).TotalSeconds
        # {0,2} keeps the line length constant so no ghost chars remain when the
        # countdown drops from 2 digits to 1 (v2.14)
        Write-Host ("`r  Delete Windows.old? (Y/n, default Y in {0,2} sec): " -f $remaining) -NoNewline -ForegroundColor Yellow
        Start-Sleep -Milliseconds 100
    }

    if ($response -eq "" -or $response -eq "Y") {
        if ($response -eq "") { Write-Host "Y" -ForegroundColor Green }

        Write-Log "Removing Windows.old..." -Level INFO

        try {
            # Take ownership and remove
            # Use the well-known SID for the Administrators group - the literal name
            # is localized (e.g. "Администраторы") and fails on non-English Windows (v2.14)
            $null = takeown /F $windowsOldPath /A /R /D Y 2>&1
            $null = icacls $windowsOldPath /grant "*S-1-5-32-544:F" /T /C /Q 2>&1
            Remove-Item -Path $windowsOldPath -Recurse -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path $windowsOldPath)) {
                Write-Log "Windows.old removed - $sizeFormatted freed" -Level SUCCESS
                $script:Stats.TotalFreedBytes += $size
                $script:Stats.FreedByCategory["Windows.old"] = $size
            } else {
                Write-Log "Could not fully remove Windows.old" -Level WARNING
                $script:Stats.WarningsCount++
            }
        } catch {
            Write-Log "Error removing Windows.old: $_" -Level ERROR
            $script:Stats.ErrorsCount++
        }
    } else {
        Write-Log "Windows.old removal cancelled by user" -Level INFO
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                         DEVELOPER CLEANUP FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Clear-DeveloperCaches {
    <#
    .SYNOPSIS
        Cleans developer tool caches (npm, pip, nuget, composer, etc.)
    #>
    # v2.20: matches the contract the dispatcher enforces (-SkipCleanup suppresses the
    # whole cleanup group). Unreachable through Start-WinClean, which already gates the
    # phase - this is the guard a direct caller of the dot-sourced function gets, and it
    # disagreed with the documented meaning of -SkipCleanup.
    if ($SkipCleanup -or $SkipDevCleanup) {
        Write-Log "Developer cache cleanup skipped (parameter)" -Level INFO
        return
    }

    Write-Log "DEVELOPER CACHES" -Level TITLE
    Update-Progress -Activity "Developer Cleanup" -Status "Cleaning caches..."

    # NPM Cache (npm v7+ uses LOCALAPPDATA; older versions used APPDATA - fixed in v2.14)
    Write-Log "npm Cache" -Level SECTION
    $npmCachePaths = @("$env:LOCALAPPDATA\npm-cache", "$env:APPDATA\npm-cache")
    $npmCache = $npmCachePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($npmCache) {
        if ($ReportOnly) {
            $size = Get-FolderSize $npmCache
            Write-Log "Would clean: npm cache - $(Format-FileSize $size)" -Level DETAIL
        } else {
            # Use npm cache clean if available
            $npm = Get-Command npm -ErrorAction SilentlyContinue
            if ($npm) {
                try {
                    # v2.20, corrected in review: both sides are measured with the checked
                    # variant. Get-FolderSize answers 0 for "empty" and for "could not
                    # read" alike, so a cache that became unreadable after the clean - npm
                    # recreating it, ACLs changing mid-run - produced "freed everything we
                    # measured before" and put invented bytes into TotalFreedBytes. The
                    # same defect was fixed for browser caches in this release; npm kept it.
                    $sizeBefore = Get-FolderSizeChecked -Path $npmCache
                    & npm cache clean --force 2>&1 | Out-Null
                    # v2.20: npm fails without throwing (EPERM on a locked cache is the
                    # common case). The exit code was never read, so a failed clean that
                    # freed nothing landed in the "else" branch below and was logged as
                    # SUCCESS - the same lie fixed for browser caches in v2.16.
                    $npmExit = $LASTEXITCODE
                    $sizeAfter = Get-FolderSizeChecked -Path $npmCache
                    $npmMeasured = ($null -ne $sizeBefore -and $null -ne $sizeAfter)
                    $freed = if ($npmMeasured) { [math]::Max(0, $sizeBefore - $sizeAfter) } else { 0 }

                    # Credit whatever really went, whether or not npm then failed
                    if ($freed -gt 0) {
                        $script:Stats.TotalFreedBytes += $freed
                        if (-not $script:Stats.FreedByCategory.ContainsKey("Developer")) {
                            $script:Stats.FreedByCategory["Developer"] = 0
                        }
                        $script:Stats.FreedByCategory["Developer"] += $freed
                    }

                    # v2.20, corrected in review: the exit code is checked FIRST. Testing
                    # "$freed -gt 0" first meant a partial failure (npm removes 400 MB, then
                    # hits EPERM on a locked file and exits 1) reported plain success and
                    # skipped the fallback - the exit code was read and then ignored in
                    # exactly the case where it mattered.
                    if ($npmExit -ne 0) {
                        Write-Log "npm cache clean failed (exit code $npmExit)$(if ($freed -gt 0) { " after freeing $(Format-FileSize $freed)" }) - removing the cache directly" -Level WARNING
                        $script:Stats.WarningsCount++
                        Remove-FolderContent -Path $npmCache -Category "Developer" -Description "npm cache"
                    } elseif ($freed -gt 0) {
                        Write-Log "npm cache cleaned - $(Format-FileSize $freed)" -Level SUCCESS
                    } elseif (-not $npmMeasured) {
                        # Cleaned, but "how much" has no honest answer - say that instead
                        # of calling an unreadable cache an empty one.
                        Write-Log "npm cache cleaned, but its size could not be measured - freed space not counted" -Level DETAIL
                    } else {
                        # npm succeeded and there was nothing to reclaim. Not a cleanup
                        # success worth announcing, and definitely not freed bytes.
                        Write-Log "npm cache was already empty" -Level DETAIL
                    }
                } catch {
                    Remove-FolderContent -Path $npmCache -Category "Developer" -Description "npm cache"
                }
            } else {
                Remove-FolderContent -Path $npmCache -Category "Developer" -Description "npm cache"
            }
        }

        # Clean any remaining legacy cache location as well (both may exist after npm upgrades)
        foreach ($stalePath in ($npmCachePaths | Where-Object { $_ -ne $npmCache })) {
            Remove-FolderContent -Path $stalePath -Category "Developer" -Description "npm cache (legacy)"
        }
    }

    # pip Cache
    Write-Log "pip Cache" -Level SECTION
    $pipCaches = @(
        "$env:LOCALAPPDATA\pip\Cache"
        "$env:APPDATA\pip\cache"
        "$env:USERPROFILE\.cache\pip"
    )
    foreach ($pipCache in $pipCaches) {
        Remove-FolderContent -Path $pipCache -Category "Developer" -Description "pip cache"
    }

    # NuGet Cache (only metadata caches, not packages!)
    Write-Log "NuGet Cache" -Level SECTION
    $nugetCaches = @(
        "$env:LOCALAPPDATA\NuGet\v3-cache"      # Metadata cache
        "$env:LOCALAPPDATA\NuGet\plugins-cache" # Plugin cache
        "$env:LOCALAPPDATA\NuGet\http-cache"    # HTTP cache
        # Note: $env:USERPROFILE\.nuget\packages is NOT cache - it's the global packages folder
    )
    foreach ($cache in $nugetCaches) {
        Remove-FolderContent -Path $cache -Category "Developer" -Description "NuGet cache"
    }

    # Composer Cache
    Write-Log "Composer Cache" -Level SECTION
    $composerCache = "$env:LOCALAPPDATA\Composer\cache"
    Remove-FolderContent -Path $composerCache -Category "Developer" -Description "Composer cache"

    # Gradle (only safe cache directories, not full repositories!)
    Write-Log "Gradle Cache" -Level SECTION
    $gradleCaches = @(
        "$env:USERPROFILE\.gradle\caches\build-cache-1"       # Build cache
        "$env:USERPROFILE\.gradle\caches\transforms-*"         # Transform cache
        "$env:USERPROFILE\.gradle\daemon"                      # Daemon logs
        # Note: .gradle\caches\modules-* contains downloaded dependencies - dangerous to delete!
        # Note: .m2\repository is Maven local repo - do NOT delete!
    )
    foreach ($pattern in $gradleCaches) {
        Get-ChildItem -Path (Split-Path $pattern -Parent) -Filter (Split-Path $pattern -Leaf) -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-FolderContent -Path $_.FullName -Category "Developer" -Description "Gradle cache"
        }
    }

    # yarn Cache
    Write-Log "yarn Cache" -Level SECTION
    $yarnCaches = @(
        "$env:LOCALAPPDATA\Yarn\Cache"
        "$env:USERPROFILE\.cache\yarn"
    )
    foreach ($cache in $yarnCaches) {
        Remove-FolderContent -Path $cache -Category "Developer" -Description "yarn cache"
    }

    # pnpm Cache
    Write-Log "pnpm Cache" -Level SECTION
    $pnpmCache = "$env:LOCALAPPDATA\pnpm-cache"
    Remove-FolderContent -Path $pnpmCache -Category "Developer" -Description "pnpm cache"

    # Go Cache
    Write-Log "Go Cache" -Level SECTION
    $goCache = "$env:LOCALAPPDATA\go-build"
    Remove-FolderContent -Path $goCache -Category "Developer" -Description "Go build cache"

    # Rust/Cargo Cache
    Write-Log "Cargo Cache" -Level SECTION
    $cargoCaches = @(
        "$env:USERPROFILE\.cargo\registry\cache"
        "$env:USERPROFILE\.cargo\git\db"
    )
    foreach ($cache in $cargoCaches) {
        Remove-FolderContent -Path $cache -Category "Developer" -Description "Cargo cache"
    }

    # uv Cache (Python package/project manager)
    Write-Log "uv Cache" -Level SECTION
    $uvCache = "$env:LOCALAPPDATA\uv\cache"
    Remove-FolderContent -Path $uvCache -Category "Developer" -Description "uv cache"
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                          DOCKER/WSL CLEANUP FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Test-DiskpartCompactionFailed {
    <#
    .SYNOPSIS
        Decides whether a diskpart "compact vdisk" run failed - pure logic, no I/O
    .DESCRIPTION
        Split out (v2.18) so the failure decision is unit-testable without a real VHDX.
        diskpart is unreliable at signalling a sub-command failure through its exit code
        (it can exit 0 after "compact vdisk" errored), so a non-zero exit OR a known error
        marker in the output both count as failure. The output is localized, so this only
        catches English error text; on a non-English console a failure may surface only as
        a non-zero exit, or as the file not shrinking (the caller treats "no shrink" as a
        neutral "no space saved", not a failure, so a silent localized error can still be
        missed - a limitation of the diskpart text interface, noted deliberately).
    .PARAMETER Output
        The combined stdout/stderr text diskpart produced.
    .PARAMETER ExitCode
        diskpart's process exit code.
    #>
    param([string]$Output, [int]$ExitCode)

    if ($ExitCode -ne 0) { return $true }
    if ([string]::IsNullOrWhiteSpace($Output)) { return $false }
    return [bool]($Output -match ('DiskPart has encountered an error|Virtual Disk Service error|' +
        'DiskPart failed|The arguments specified for this command are not valid|' +
        'There is no virtual disk selected|Access is denied|The system cannot find'))
}

function Clear-DockerWSL {
    <#
    .SYNOPSIS
        Cleans Docker images, containers, and WSL2 disk
    #>
    # v2.20: see Clear-DeveloperCaches - same contract, same reason
    if ($SkipCleanup -or $SkipDockerCleanup) {
        Write-Log "Docker/WSL cleanup skipped (parameter)" -Level INFO
        return
    }

    Write-Log "DOCKER & WSL CLEANUP" -Level TITLE
    Update-Progress -Activity "Docker/WSL Cleanup" -Status "Checking Docker..."

    # Docker Cleanup
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        Write-Log "Docker Cleanup" -Level SECTION

        # Check if Docker is running
        $dockerRunning = $false
        try {
            $null = docker info 2>&1
            $exitCode = $LASTEXITCODE  # Capture immediately after command
            $dockerRunning = $exitCode -eq 0
        } catch {
            # Docker command failed to execute (not installed or path issue)
        }

        if ($dockerRunning) {
            if ($ReportOnly) {
                Write-Log "Would run: docker system prune" -Level DETAIL
            } else {
                try {
                    # Remove unused data (stopped containers, unused networks, dangling images, build cache)
                    Write-Log "Running docker system prune..." -Level INFO
                    $result = docker system prune -f 2>&1
                    $pruneExitCode = $LASTEXITCODE

                    # Join output into a single string: -match against an array does not
                    # populate $Matches reliably (v2.14)
                    $resultText = $result | Out-String

                    if ($pruneExitCode -ne 0) {
                        Write-Log "Docker prune failed (exit code: $pruneExitCode)" -Level WARNING
                        $script:Stats.WarningsCount++
                    }
                    # Parse reclaimed space and add to statistics
                    # Supports both "reclaimed 1.23GB" and "Total reclaimed space: 1.23GB" formats
                    elseif ($resultText -match "reclaimed\s+(?:space:\s*)?([\d.,]+\s*[KMGT]?B)") {
                        $reclaimedStr = $Matches[1]
                        $reclaimedBytes = ConvertFrom-HumanReadableSize $reclaimedStr

                        Write-Log "Docker cleanup: $reclaimedStr reclaimed" -Level SUCCESS

                        if ($reclaimedBytes -gt 0) {
                            $script:Stats.TotalFreedBytes += $reclaimedBytes
                            if (-not $script:Stats.FreedByCategory.ContainsKey("Docker")) {
                                $script:Stats.FreedByCategory["Docker"] = 0
                            }
                            $script:Stats.FreedByCategory["Docker"] += $reclaimedBytes
                        }
                    } else {
                        Write-Log "Docker cleanup completed" -Level SUCCESS
                    }

                    # Note: docker system prune -f already includes build cache cleanup

                } catch {
                    Write-Log "Docker cleanup error: $_" -Level WARNING
                    $script:Stats.WarningsCount++
                }
            }
        } else {
            Write-Log "Docker is not running - skipping cleanup" -Level INFO
        }
    } else {
        Write-Log "Docker not installed" -Level INFO
    }

    # WSL2 Disk Compaction
    Write-Log "WSL2 Disk Optimization" -Level SECTION

    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wsl) {
        try {
            # Define all possible VHDX locations (including Docker)
            $wslPaths = @(
                "$env:LOCALAPPDATA\Packages\*CanonicalGroupLimited*\LocalState"
                "$env:LOCALAPPDATA\Packages\*MicrosoftCorporationII.WindowsSubsystemForLinux*\LocalState"
                "$env:LOCALAPPDATA\Docker\wsl\data"
                "$env:LOCALAPPDATA\Docker\wsl\distro"
            )

            # Find all VHDX files first (don't depend on WSL distro list)
            $vhdxFiles = @()
            foreach ($pattern in $wslPaths) {
                $vhdxFiles += Get-ChildItem -Path $pattern -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue
            }

            if ($vhdxFiles.Count -gt 0) {
                if ($ReportOnly) {
                    $totalSize = ($vhdxFiles | Measure-Object -Property Length -Sum).Sum
                    Write-Log "Would optimize $($vhdxFiles.Count) WSL2/Docker disk(s) - Total: $(Format-FileSize $totalSize)" -Level DETAIL
                } else {
                    # Shutdown WSL first (this also stops Docker WSL backends)
                    Write-Log "Shutting down WSL..." -Level INFO
                    wsl --shutdown
                    $wslShutdownExit = $LASTEXITCODE
                    if ($wslShutdownExit -ne 0) {
                        # v2.18: compacting a VHDX WSL may still hold open is unsafe and
                        # pointless, so a failed shutdown skips compaction (emptying the
                        # list) with a warning instead of touching a live disk.
                        Write-Log "wsl --shutdown exit $wslShutdownExit - skipping VHDX compaction to avoid touching a live disk" -Level WARNING
                        $script:Stats.WarningsCount++
                        $vhdxFiles = @()
                    }
                    Start-Sleep -Seconds 2

                    # Compact each VHDX file
                    foreach ($vhdxFile in $vhdxFiles) {
                        $vhdx = $vhdxFile.FullName
                        $sizeBefore = $vhdxFile.Length

                        Write-Log "Compacting $($vhdxFile.Name)..." -Level DETAIL

                        try {
                            # Use diskpart to compact
                            $diskpartScript = @"
select vdisk file="$vhdx"
compact vdisk
exit
"@
                            # v2.18: capture output AND exit code. The old "| Out-Null"
                            # discarded both, so a diskpart failure fell straight through to
                            # "no space saved" (INFO) and read as success to the stand/CI.
                            $diskpartOutput = $diskpartScript | diskpart 2>&1
                            $diskpartExit = $LASTEXITCODE
                            $diskpartText = ($diskpartOutput | Out-String)

                            if (Test-DiskpartCompactionFailed -Output $diskpartText -ExitCode $diskpartExit) {
                                Write-Log "Could not compact $($vhdxFile.Name): diskpart reported an error (exit $diskpartExit)" -Level WARNING
                                $tail = (($diskpartText -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 2) -join ' | '
                                if ($tail) { Write-Log "diskpart: $tail" -Level DETAIL }
                                $script:Stats.WarningsCount++
                            } else {
                                $sizeAfter = (Get-Item $vhdx).Length
                                $saved = $sizeBefore - $sizeAfter

                                if ($saved -gt 0) {
                                    Write-Log "Compacted $($vhdxFile.Name): $(Format-FileSize $saved) saved" -Level SUCCESS
                                    $script:Stats.TotalFreedBytes += $saved
                                    if (-not $script:Stats.FreedByCategory.ContainsKey("WSL")) {
                                        $script:Stats.FreedByCategory["WSL"] = 0
                                    }
                                    $script:Stats.FreedByCategory["WSL"] += $saved
                                } else {
                                    Write-Log "Compacted $($vhdxFile.Name): no space saved" -Level INFO
                                }
                            }
                        } catch {
                            # v2.18: the outer catch bumps WarningsCount but this per-VHDX
                            # one did not, so a real compaction failure could leave the JSON
                            # WarningsCount at 0 and read as a clean run to the stand/CI.
                            Write-Log "Could not compact $($vhdxFile.Name): $_" -Level WARNING
                            $script:Stats.WarningsCount++
                        }
                    }
                }
            } else {
                Write-Log "No WSL2/Docker VHDX files found" -Level INFO
            }
        } catch {
            Write-Log "WSL optimization error: $_" -Level WARNING
            $script:Stats.WarningsCount++
        }
    } else {
        Write-Log "WSL not installed" -Level INFO
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                       VISUAL STUDIO CLEANUP FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Clear-VisualStudio {
    <#
    .SYNOPSIS
        Cleans Visual Studio caches and temporary files
    #>
    # v2.20: see Clear-DeveloperCaches - same contract, same reason
    if ($SkipCleanup -or $SkipVSCleanup) {
        Write-Log "Visual Studio cleanup skipped (parameter)" -Level INFO
        return
    }

    Write-Log "VISUAL STUDIO CLEANUP" -Level TITLE
    Update-Progress -Activity "Visual Studio Cleanup" -Status "Cleaning caches..."

    # VS 2019/2022 caches (directories)
    $vsCacheDirs = @(
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache"; Desc = "Component Model Cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ImageCacheRoot"; Desc = "Image Cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\DesignTimeBuild"; Desc = "Design Time Build" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VSCommon\*\SQM"; Desc = "SQM Data" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\Packages\_Instances"; Desc = "Package Instances" }
    )

    # VS file patterns (handled separately, fixed in v2.1)
    $vsFilePatterns = @(
        @{ Pattern = "$env:APPDATA\Microsoft\VisualStudio\*\*.roslynobjectin"; Desc = "Roslyn Temp" }
    )

    Write-Log "Visual Studio Caches" -Level SECTION

    # Process directory caches
    foreach ($item in $vsCacheDirs) {
        $paths = Resolve-Path -Path $item.Path -ErrorAction SilentlyContinue
        foreach ($path in $paths) {
            Remove-FolderContent -Path $path.Path -Category "VS" -Description $item.Desc
        }
    }

    # Process file patterns (fixed in v2.1 - files were not being deleted before)
    foreach ($item in $vsFilePatterns) {
        Remove-FilesByPattern -Pattern $item.Pattern -Category "VS" -Description $item.Desc
    }

    # MEF cache: no separate section - the real one is ComponentModelCache, already
    # covered by the VS cache list above. "MEFCacheAssembly" (v2.16 and earlier) is a
    # folder Visual Studio never creates, so the section only ever printed a heading.

# VS Code caches
    Write-Log "VS Code Caches" -Level SECTION
    $vscodeCaches = @(
        "$env:APPDATA\Code\Cache"
        "$env:APPDATA\Code\CachedData"
        "$env:APPDATA\Code\CachedExtensions"
        "$env:APPDATA\Code\CachedExtensionVSIXs"
        "$env:APPDATA\Code\Code Cache"
        "$env:APPDATA\Code\GPUCache"
        "$env:APPDATA\Code - Insiders\Cache"
        "$env:APPDATA\Code - Insiders\CachedData"
    )

    foreach ($cache in $vscodeCaches) {
        Remove-FolderContent -Path $cache -Category "VS Code" -Description "VS Code cache"
    }

    # JetBrains IDEs
    Write-Log "JetBrains IDE Caches" -Level SECTION
    $jetbrainsBase = "$env:LOCALAPPDATA\JetBrains"
    if (Test-Path $jetbrainsBase) {
        Get-ChildItem -Path $jetbrainsBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cacheDirs = @("caches", "index", "tmp", "log")
            foreach ($cacheDir in $cacheDirs) {
                $fullPath = Join-Path $_.FullName $cacheDir
                Remove-FolderContent -Path $fullPath -Category "JetBrains" -Description "JetBrains $cacheDir"
            }
        }
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                          SYSTEM CLEANUP FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

function Clear-KernelDumps {
    <#
    .SYNOPSIS
        Removes stale kernel live-dump reports (v2.16)
    .DESCRIPTION
        LiveKernelReports accumulates multi-gigabyte .dmp files that nothing ever
        cleans up - a single watchdog dump of 9 GB was found sitting for 18 months on
        the author's machine. Only files older than $MinAgeDays are touched, so a dump
        from a crash that is being investigated right now survives.
    #>
    param([int]$MinAgeDays = 30)

    $dumpPath = Join-Path $env:SystemRoot 'LiveKernelReports'
    if (-not (Test-Path -LiteralPath $dumpPath)) { return }

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $stale = @(Get-ChildItem -LiteralPath $dumpPath -Recurse -File -Force -Filter '*.dmp' -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -lt $cutoff })
    if ($stale.Count -eq 0) { return }

    $size = ($stale | Measure-Object -Property Length -Sum).Sum

    if ($ReportOnly) {
        Write-Log "Would clean: kernel dumps older than $MinAgeDays days ($($stale.Count) file(s)) - $(Format-FileSize $size)" -Level DETAIL
        return
    }

    $freed = 0
    $failed = 0
    $firstError = $null
    foreach ($file in $stale) {
        try {
            $len = $file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $freed += $len
        } catch {
            $failed++
            if (-not $firstError) { $firstError = $_.Exception.Message }
        }
    }

    if ($freed -gt 0) {
        $script:Stats.TotalFreedBytes += $freed
        if (-not $script:Stats.FreedByCategory.ContainsKey("System")) {
            $script:Stats.FreedByCategory["System"] = 0
        }
        $script:Stats.FreedByCategory["System"] += $freed
        Write-Log "Kernel dumps older than $MinAgeDays days - $(Format-FileSize $freed)" -Level SUCCESS
    }

    # Report failures explicitly: ReportOnly promised these gigabytes, and staying
    # silent would make a blocked deletion look like "there was nothing to clean"
    if ($failed -gt 0) {
        Write-Log "Kernel dumps: $failed of $($stale.Count) file(s) could not be deleted ($(Format-FileSize ($size - $freed)) left) - $firstError" -Level WARNING
        $script:Stats.WarningsCount++
    }
}

function Show-DiskSpaceReport {
    <#
    .SYNOPSIS
        Reports where disk space went, including areas this script never deletes (v2.16)
    .DESCRIPTION
        Several of the largest consumers on a Windows workstation are things a cleanup
        script must not touch: C:\Windows\Installer holds the data needed to uninstall
        or repair applications, hiberfil.sys is sized by the OS, and the search index is
        held open by its service. Reporting them is still valuable - without it the user
        has no idea where tens of gigabytes went.
    #>
    Write-Log "Disk Space Report" -Level SECTION

    $targets = [ordered]@{
        'Kernel live dumps'     = Join-Path $env:SystemRoot 'LiveKernelReports'
        'MSI cache (keep)'      = Join-Path $env:SystemRoot 'Installer'
        'Search index'          = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'
        'VS package cache'      = Join-Path $env:ProgramData 'Package Cache'
        'Windows logs'          = Join-Path $env:SystemRoot 'Logs'
        'Crash dumps (user)'    = Join-Path $env:LOCALAPPDATA 'CrashDumps'
    }

    $rows = @()
    $unmeasured = @()
    foreach ($name in $targets.Keys) {
        $size = Get-FolderSizeChecked -Path $targets[$name]
        if ($null -eq $size) {
            $unmeasured += $name
            continue
        }
        if ($size -gt 100MB) { $rows += [pscustomobject]@{ Item = $name; Bytes = $size } }
    }

    foreach ($file in @('hiberfil.sys', 'pagefile.sys', 'swapfile.sys', 'MEMORY.DMP')) {
        $path = if ($file -eq 'MEMORY.DMP') { Join-Path $env:SystemRoot $file } else { Join-Path $env:SystemDrive $file }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 100MB) { $rows += [pscustomobject]@{ Item = $file; Bytes = $item.Length } }
    }

    # Shadow copies: CIM returns bytes, unlike vssadmin which prints them using the
    # system decimal separator and would need locale-aware parsing
    $shadow = Get-CimInstance Win32_ShadowStorage -ErrorAction SilentlyContinue
    if ($shadow) {
        $used = ($shadow | Measure-Object -Property UsedSpace -Sum).Sum
        if ($used -gt 100MB) { $rows += [pscustomobject]@{ Item = 'Restore points / shadow copies'; Bytes = $used } }
    }

    if ($unmeasured.Count -gt 0) {
        Write-Log "Could not fully measure: $($unmeasured -join ', ') (access denied on some items)" -Level DETAIL
    }

    if ($rows.Count -eq 0) {
        if ($unmeasured.Count -eq 0) {
            Write-Log "Nothing above 100 MB outside the cleaned areas" -Level DETAIL
        }
        return
    }

    foreach ($row in ($rows | Sort-Object Bytes -Descending)) {
        Write-Log "$($row.Item): $(Format-FileSize $row.Bytes)" -Level DETAIL
    }
}

function Get-SupersededDriverCandidate {
    <#
    .SYNOPSIS
        Decides which parsed driver packages are superseded - pure logic, no I/O
    .DESCRIPTION
        Split out of Get-RedundantDriverPackage (v2.17, p.6/p.23 of the audit) so the
        decision logic can be unit-tested against hand-built package arrays instead of
        needing a real pnputil.exe and a real FileRepository to exercise it.

        A package is a candidate only when BOTH conditions hold:
          1. pnputil reports no device bound to it, and
          2. a package with a STRICTLY newer version and the same OriginalName exists
             (a mere newer date at an equal version does not count - v2.18).
        Packages without a newer sibling are left alone even when unused - they serve
        devices that are merely unplugged right now (docks, printers, external storage).
        That distinction is what separates this from the aggressive "driver cleaners"
        that break machines.

        Grouped by INF *and* vendor/class. Generic names (usbaudio.inf, hidusb.inf) are
        shipped by several vendors, and grouping on the name alone could declare one
        vendor's package "superseded" by another's - then delete a working driver whose
        device merely happens to be unplugged right now.
    .PARAMETER Packages
        Parsed pnputil packages: objects with Oem, Inf, Provider, Class, Version, Date,
        InUse (the shape Get-RedundantDriverPackage builds from pnputil's XML).
    .OUTPUTS
        Candidate objects (a subset of the input, decorated with Bytes=0 and
        KeptVersion). Bytes is filled in later by the caller once a FileRepository
        folder is matched - this function never touches the filesystem.
    #>
    param([object[]]$Packages)

    $Packages | Group-Object { "$($_.Inf)|$($_.Provider)|$($_.Class)" } | ForEach-Object {
        $newest = $_.Group | Sort-Object Version, Date -Descending | Select-Object -First 1
        foreach ($pkg in $_.Group) {
            # v2.18: "superseded" means a STRICTLY NEWER version exists. A package tied at
            # the newest version is kept even when unused - same-version duplicates are not
            # proof of obsolescence, and removing one would be wider than the documented
            # safety contract (older code deleted a same-version package that merely had an
            # older date). Date is no longer a selection tie-breaker: every package at the
            # max version is retained; it only decides which object represents $newest.
            if ($pkg.InUse -or $pkg.Version -ge $newest.Version) { continue }
            $pkg | Add-Member -NotePropertyName Bytes -NotePropertyValue ([long]0) -PassThru |
                   Add-Member -NotePropertyName KeptVersion -NotePropertyValue $newest.Version -PassThru
        }
    }
}

function Get-RedundantDriverPackage {
    <#
    .SYNOPSIS
        Finds superseded third-party driver packages in the driver store (v2.16)
    .DESCRIPTION
        Candidate selection itself lives in Get-SupersededDriverCandidate; this function
        handles the I/O around it - running pnputil, parsing its XML, and matching each
        candidate to a FileRepository folder for size reporting.

        Output is machine-readable XML on purpose: the plain text output of pnputil
        switches between English and the system language depending on the console code
        page, so it cannot be parsed reliably.
    #>
    $repo = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'

    # v2.17: stderr is kept OUT of the XML. Merging it with 2>&1 meant a single
    # warning line from pnputil produced invalid XML, the cast threw, and the driver
    # store was skipped silently every week.
    $stdOutFile = [System.IO.Path]::GetTempFileName()
    $stdErrFile = [System.IO.Path]::GetTempFileName()
    try {
        $pnp = Start-Process -FilePath "$env:SystemRoot\System32\pnputil.exe" `
            -ArgumentList '/enum-drivers', '/devices', '/format', 'xml' `
            -NoNewWindow -PassThru -Wait `
            -RedirectStandardOutput $stdOutFile -RedirectStandardError $stdErrFile

        if ($pnp.ExitCode -ne 0) {
            # Without this the failure looked exactly like "nothing to clean"
            $err = (Get-Content $stdErrFile -Raw -ErrorAction SilentlyContinue)
            Write-Log "pnputil /enum-drivers returned $($pnp.ExitCode) - driver store skipped" -Level WARNING
            if ($err) { Write-Log "pnputil: $($err.Trim())" -Level DETAIL }
            $script:Stats.WarningsCount++
            return @()
        }

        $rawXml = Get-Content $stdOutFile -Raw -ErrorAction Stop
        [xml]$doc = $rawXml
    } catch {
        Write-Log "Could not enumerate driver packages: $_" -Level WARNING
        # Make diagnosis possible instead of leaving a bare exception
        $head = if ($rawXml) { $rawXml.Substring(0, [Math]::Min(200, $rawXml.Length)) } else { '(no output)' }
        Write-Log "pnputil output began with: $head" -Level DETAIL
        $script:Stats.WarningsCount++
        return @()
    } finally {
        Remove-Item $stdOutFile, $stdErrFile -Force -ErrorAction SilentlyContinue
    }
    if (-not $doc.PnpUtil.Driver) {
        Write-Log "pnputil returned no driver packages - unexpected, driver store skipped" -Level WARNING
        $script:Stats.WarningsCount++
        return @()
    }

    $skipped = 0
    $packages = foreach ($d in $doc.PnpUtil.Driver) {
        $parts = $d.DriverVersion -split '\s+', 2      # "MM/dd/yyyy x.y.z.w"
        if ($parts.Count -lt 2) { $skipped++; continue }
        try {
            # The date is only a tie-breaker for sorting, so an unparseable one must not
            # discard the whole package - otherwise a date format change would silently
            # empty the candidate list and report "nothing found" forever
            $driverDate = [datetime]::MinValue
            [void][datetime]::TryParse($parts[0], [cultureinfo]::InvariantCulture,
                                       [System.Globalization.DateTimeStyles]::None, [ref]$driverDate)
            [pscustomobject]@{
                Oem      = $d.DriverName
                Inf      = $d.OriginalName
                Provider = $d.ProviderName
                Class    = $d.ClassName
                Version  = [version]$parts[1]
                Date     = $driverDate
                InUse    = [bool]$d.Devices
            }
        } catch { $skipped++; continue }
    }

    if ($skipped -gt 0) {
        Write-Log "Driver store: $skipped package(s) could not be parsed and were ignored" -Level DETAIL
    }
    if (-not $packages) {
        Write-Log "Driver store: no package could be parsed - skipping cleanup" -Level WARNING
        $script:Stats.WarningsCount++
        return @()
    }

    # p.6 of the audit: figure out WHICH packages are superseded first, from pnputil's
    # own metadata alone (Get-SupersededDriverCandidate - no filesystem access needed
    # for that). Only once there is at least one candidate do we pay for hashing
    # FileRepository folders (700-1500 on a typical machine), and that walk stops as
    # soon as every candidate is matched instead of always hashing every folder.
    $candidates = @(Get-SupersededDriverCandidate -Packages $packages)

    if (-not $candidates) {
        return @()
    }

    # Hash each candidate's live INF once, up front: version strings are not unique
    # (ibtusb.inf ships several packages carrying an identical DriverVer), so hashing
    # the actual INF is the only exact oem*.inf -> FileRepository folder mapping.
    $neededHashes = @{}   # SHA256 -> candidate object
    foreach ($pkg in $candidates) {
        $infFile = Join-Path $env:SystemRoot "INF\$($pkg.Oem)"
        if (-not (Test-Path -LiteralPath $infFile)) { continue }
        try {
            $hash = (Get-FileHash $infFile -Algorithm SHA256).Hash
            $neededHashes[$hash] = $pkg
        } catch { }
    }

    foreach ($dir in (Get-ChildItem -LiteralPath $repo -Directory -ErrorAction SilentlyContinue)) {
        if ($neededHashes.Count -eq 0) { break }

        $infName = ($dir.Name -split '\.inf_')[0] + '.inf'
        $infPath = Join-Path $dir.FullName $infName
        if (-not (Test-Path -LiteralPath $infPath)) { continue }

        try {
            $hash = (Get-FileHash $infPath -Algorithm SHA256).Hash
            if ($neededHashes.ContainsKey($hash)) {
                $pkg = $neededHashes[$hash]
                $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum
                $pkg.Bytes = [long]($size ?? 0)
                $neededHashes.Remove($hash)
            }
        } catch { }
    }

    return $candidates
}

function Clear-DriverStore {
    <#
    .SYNOPSIS
        Removes superseded driver packages from the driver store (v2.16)
    #>
    Write-Log "Driver Store" -Level SECTION

    $candidates = @(Get-RedundantDriverPackage)
    if ($candidates.Count -eq 0) {
        Write-Log "No superseded driver packages found" -Level DETAIL
        return
    }

    $totalBytes = ($candidates | Measure-Object -Property Bytes -Sum).Sum

    if ($ReportOnly) {
        Write-Log "Would clean: $($candidates.Count) superseded driver package(s) - $(Format-FileSize $totalBytes)" -Level DETAIL
        foreach ($group in ($candidates | Group-Object Inf | Sort-Object Count -Descending | Select-Object -First 5)) {
            Write-Log "  $($group.Name): $($group.Count) old version(s)" -Level DETAIL
        }
        return
    }

    # Repository size before removal, used as the authoritative freed total whenever any
    # removed package lacks a trustworthy per-package size (see the accounting below).
    $repoPath = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    $repoBefore = Get-FolderSize -Path $repoPath

    $perPackageBytes = 0
    $removed = 0
    $failed = 0
    $allMeasured = $true
    foreach ($pkg in $candidates) {
        # No /force here: it deletes packages even when a device is using them, which is
        # exactly how driver cleaners break systems. Exit code is the verdict - the text
        # output is localized.
        $null = & pnputil.exe /delete-driver $pkg.Oem 2>&1
        if ($LASTEXITCODE -eq 0) {
            $removed++
            # v2.18: a candidate whose FileRepository folder was never matched (unmatched
            # INF hash, or a shared hash that overwrote another candidate in the lookup)
            # keeps Bytes=0. Summing those as-is understates the total, so remember that at
            # least one removed package had no trustworthy size.
            if ($pkg.Bytes -gt 0) { $perPackageBytes += $pkg.Bytes } else { $allMeasured = $false }
        } else {
            $failed++
            Write-Log "Skipped $($pkg.Oem) ($($pkg.Inf)): pnputil exit $LASTEXITCODE" -Level DETAIL
        }
    }

    if ($removed -gt 0) {
        if ($allMeasured) {
            # Every removed package had a matched, measured size - use the precise sum.
            $freed = $perPackageBytes
        } else {
            # At least one removed package had no per-package size, so the sum would
            # understate even when it is non-zero (the old "only fall back when total==0"
            # missed exactly this partial case). The repository delta captures every
            # removal at once and is authoritative here.
            $freed = [math]::Max(0, $repoBefore - (Get-FolderSize -Path $repoPath))
            Write-Log "Removed $removed package(s); per-package size incomplete, driver store shrank by $(Format-FileSize $freed)" -Level WARNING
            $script:Stats.WarningsCount++
        }

        $script:Stats.TotalFreedBytes += $freed
        if (-not $script:Stats.FreedByCategory.ContainsKey("DriverStore")) {
            $script:Stats.FreedByCategory["DriverStore"] = 0
        }
        $script:Stats.FreedByCategory["DriverStore"] += $freed
        Write-Log "Removed $removed superseded driver package(s) - $(Format-FileSize $freed)" -Level SUCCESS
    } else {
        Write-Log "No driver packages were removed" -Level DETAIL
    }

    if ($failed -gt 0) {
        Write-Log "Driver store: $failed of $($candidates.Count) package(s) refused removal" -Level WARNING
        $script:Stats.WarningsCount++
    }
}

function Measure-FreeSpaceGain {
    <#
    .SYNOPSIS
        Runs an operation and attributes the freed disk space to a category (v2.17)
    .DESCRIPTION
        DISM component cleanup and Disk Cleanup are usually the two most productive
        steps of a run, and neither reports how much it freed. Without this their
        gigabytes were missing from "Space freed" entirely, so the summary understated
        the result while looking complete.

        The measurement is deliberately coarse: it is the difference in free space on
        the system drive, so unrelated activity during the operation adds noise, and a
        negative delta is discarded rather than reported.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][string]$Category
    )

    $driveLetter = ($env:SystemDrive).TrimEnd(':')
    $before = try { (Get-PSDrive -Name $driveLetter -ErrorAction Stop).Free } catch { $null }

    & $Operation

    if ($null -eq $before -or $ReportOnly) { return }
    $after = try { (Get-PSDrive -Name $driveLetter -ErrorAction Stop).Free } catch { $null }
    if ($null -eq $after) { return }

    $gain = $after - $before
    if ($gain -le 0) { return }

    $script:Stats.TotalFreedBytes += $gain
    if (-not $script:Stats.FreedByCategory.ContainsKey($Category)) {
        $script:Stats.FreedByCategory[$Category] = 0
    }
    $script:Stats.FreedByCategory[$Category] += $gain
    Write-Log "$Category freed approximately $(Format-FileSize $gain)" -Level DETAIL
}

function Invoke-DISMCleanup {
    <#
    .SYNOPSIS
        Runs DISM component cleanup
    #>
    # Clear any existing progress bar before DISM outputs to console
    Clear-AllProgress

    Write-Log "Windows Component Cleanup (DISM)" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would run: DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase" -Level DETAIL
        Write-Log "Note: /ResetBase removes ability to uninstall updates" -Level WARNING
        return
    }

    # Analyze first: skip the expensive cleanup when DISM says it is not needed (v2.14).
    # /English forces English output so the recommendation line is parseable on any locale.
    # On analyze failure/timeout fall back to running the cleanup unconditionally.
    Write-Log "Analyzing component store..." -Level INFO

    $runCleanup = $true
    $analyzeFile = [System.IO.Path]::GetTempFileName()
    try {
        $analyzeProcess = Start-Process -FilePath "$env:SystemRoot\System32\Dism.exe" `
            -ArgumentList "/Online", "/English", "/Cleanup-Image", "/AnalyzeComponentStore" `
            -NoNewWindow -PassThru -RedirectStandardOutput $analyzeFile

        if ($analyzeProcess.WaitForExit(300000)) {
            $analyzeOutput = Get-Content $analyzeFile -Raw -ErrorAction SilentlyContinue
            if ($analyzeProcess.ExitCode -eq 0 -and
                $analyzeOutput -match 'Component Store Cleanup Recommended\s*:\s*No') {
                $runCleanup = $false
                Write-Log "Component store is clean - cleanup not needed" -Level SUCCESS
            }
        } else {
            $analyzeProcess.Kill($true)
        }
    } catch {
        # Analyze failed - run the cleanup unconditionally (previous behavior)
    } finally {
        Remove-Item $analyzeFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $runCleanup) {
        return
    }

    Write-Log "Running DISM cleanup (this may take several minutes)..." -Level INFO

    # Redirect DISM output to a file - its progress bar corrupts the script's console UI
    $dismOutFile = [System.IO.Path]::GetTempFileName()
    try {
        $dismProcess = Start-Process -FilePath "$env:SystemRoot\System32\Dism.exe" `
            -ArgumentList "/Online", "/Cleanup-Image", "/StartComponentCleanup", "/ResetBase" `
            -NoNewWindow -PassThru -RedirectStandardOutput $dismOutFile

        # Wait with timeout (15 minutes for DISM operation)
        $timeoutMs = 900000
        if (-not $dismProcess.WaitForExit($timeoutMs)) {
            $dismProcess.Kill($true)
            Write-Log "DISM cleanup timed out after 15 minutes" -Level WARNING
            $script:Stats.WarningsCount++
            return
        }

        # v2.17: 3010 is the documented "success, reboot required" code that DISM returns
        # routinely after /StartComponentCleanup - it used to fall through to the warning
        # branch, painting every successful run yellow while never setting RebootRequired.
        # Code 87 is ERROR_INVALID_PARAMETER (an unsupported switch combination), not
        # "cleanup not needed" - reporting it as INFO hid a real failure completely.
        switch ($dismProcess.ExitCode) {
            0    { Write-Log "DISM cleanup completed successfully" -Level SUCCESS }
            3010 {
                Write-Log "DISM cleanup completed - a reboot is required to finish" -Level SUCCESS
                $script:Stats.RebootRequired = $true
            }
            default {
                $tail = (Get-Content $dismOutFile -Tail 3 -ErrorAction SilentlyContinue) -join ' '
                Write-Log "DISM failed with code $($dismProcess.ExitCode)$(if ($tail) { " - $tail" })" -Level WARNING
                $script:Stats.WarningsCount++
            }
        }
    } catch {
        Write-Log "DISM error: $_" -Level WARNING
        $script:Stats.WarningsCount++
    } finally {
        Remove-Item $dismOutFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProcessActivityFingerprint {
    <#
    .SYNOPSIS
        A comparable snapshot of how much work a process has actually done
    .DESCRIPTION
        v2.22. CPU time plus the three I/O operation counters, as one comparable string.
        Two identical fingerprints taken far enough apart mean the process did literally
        nothing in between.

        Win32_Process rather than System.Diagnostics.Process, established by measurement:
        the .NET object exposes the processor times but leaves ReadOperationCount,
        WriteOperationCount and OtherOperationCount empty, so a fingerprint built from it
        would compare CPU alone.

        Returns $null when the counters cannot be read (WMI unavailable, the process gone,
        access denied). The caller must treat $null as "cannot tell", never as "idle" -
        otherwise a broken WMI would look exactly like a finished cleanup.
    #>
    param([int]$ProcessId)

    try {
        $p = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" `
                             -Property KernelModeTime, UserModeTime, ReadOperationCount,
                                       WriteOperationCount, OtherOperationCount `
                             -ErrorAction Stop
        if (-not $p) { return $null }
        return '{0}|{1}|{2}|{3}|{4}' -f $p.KernelModeTime, $p.UserModeTime,
                                        $p.ReadOperationCount, $p.WriteOperationCount, $p.OtherOperationCount
    } catch {
        return $null
    }
}

function Update-IdleStreak {
    <#
    .SYNOPSIS
        Counts consecutive checks in which a process did nothing at all
    .DESCRIPTION
        v2.22, pure so the rule is testable without a process. Returns the new streak
        length: one longer when the two fingerprints match, zero otherwise.

        An unreadable fingerprint on either side resets the streak. That is the whole
        safety property: "I could not measure it" must never accumulate towards "it has
        finished", or a machine with broken WMI would cut every Disk Cleanup short.
    #>
    param(
        [AllowNull()][string]$Previous,
        [AllowNull()][string]$Current,
        [int]$Streak
    )

    if ([string]::IsNullOrEmpty($Previous) -or [string]::IsNullOrEmpty($Current)) { return 0 }
    if ($Current -ceq $Previous) { return $Streak + 1 }
    return 0
}

function Wait-CleanmgrCompletion {
    <#
    .SYNOPSIS
        Waits for Disk Cleanup to finish its work, which is not the same as exiting
    .DESCRIPTION
        v2.22, split out in the style of Wait-StorageSenseTask so the wait can be tested
        without a process and without waiting fifteen minutes: the caller injects how to
        tell whether the process exited, how to read its activity, and how to wait.

        Two completion signals, because HasExited alone was the wrong model of "done".
        Measured on a live workstation: cleanmgr /sagerun did its work in about ten
        seconds, closed its window, then stayed resident with CPU and all three I/O
        counters frozen and every thread in Wait. The run sat out the remaining ~890
        seconds and then published the finished cleanup as partial.

        Returns Outcome ('exited' | 'idle-resident' | 'timeout') and Elapsed seconds.
        'idle-resident' means the work is over and nothing is pending; only the process
        outstayed it. 'timeout' means it was still genuinely working when time ran out.
    #>
    param(
        [scriptblock]$HasExited,
        [scriptblock]$GetFingerprint,
        [int]$MaxWaitSeconds = 900,
        [int]$CheckInterval = 10,
        [int]$IdleChecksRequired = 12,
        [scriptblock]$OnProgress = { param($seconds) },
        [scriptblock]$Wait = { param($seconds) Start-Sleep -Seconds $seconds }
    )

    $elapsed = 0
    $idleStreak = 0
    $fingerprint = & $GetFingerprint

    while (-not (& $HasExited) -and $elapsed -lt $MaxWaitSeconds) {
        & $Wait $CheckInterval
        $elapsed += $CheckInterval

        $previousFingerprint = $fingerprint
        $fingerprint = & $GetFingerprint
        $idleStreak = Update-IdleStreak -Previous $previousFingerprint -Current $fingerprint -Streak $idleStreak

        if ($idleStreak -ge $IdleChecksRequired) {
            return @{ Outcome = 'idle-resident'; Elapsed = $elapsed }
        }

        if ($elapsed % 60 -eq 0) { & $OnProgress $elapsed }
    }

    # Re-read rather than assume: the process may have exited during the last interval,
    # and that is a cleaner answer than "timeout" for the same instant.
    if (& $HasExited) { return @{ Outcome = 'exited'; Elapsed = $elapsed } }
    return @{ Outcome = 'timeout'; Elapsed = $elapsed }
}

function Select-StorageSenseTask {
    <#
    .SYNOPSIS
        Picks the single Storage Sense task out of a lookup result
    .DESCRIPTION
        Pure decision, split out in v2.20 so the rule can be tested without a scheduler.
        Windows ships exactly one task with this name; silently taking the first of
        several means starting something nobody identified, so ambiguity yields no task
        and says why.
        Returns Task (the task or $null) and Reason ('ok' | 'none' | 'ambiguous').
    #>
    param([object[]]$Tasks)

    $found = @($Tasks | Where-Object { $null -ne $_ })
    if ($found.Count -eq 0) { return @{ Task = $null; Reason = 'none' } }
    if ($found.Count -gt 1) { return @{ Task = $null; Reason = 'ambiguous' } }
    return @{ Task = $found[0]; Reason = 'ok' }
}

function Get-StorageSenseVerdict {
    <#
    .SYNOPSIS
        Decides whether a Storage Sense run counts as a cleanup that actually happened
    .DESCRIPTION
        Pure decision, split out in v2.20 so the rule can be tested. Two things must both
        hold before Disk Cleanup is skipped: the task reported success, AND free space
        actually grew.
        A result of 0 on its own is not evidence. Storage Sense obeys its own settings;
        switched off in Settings, the task still starts, does nothing it is not allowed to
        do, and exits 0. Skipping all 23 cleanmgr handlers on that basis would free
        nothing and report success - the defect this release exists to remove, and one
        that only became reachable once this branch stopped being dead code.
        $null TaskResult means "could not be read" and $null FreedBytes means "could not
        be measured"; neither may be read as success.
        Returns Done ($true only when cleanmgr may be skipped) and Reason
        ('unreadable' | 'failed' | 'not-measured' | 'nothing-freed' | 'success').
    #>
    param(
        [AllowNull()][object]$TaskResult,
        [AllowNull()][object]$FreedBytes
    )

    if ($null -eq $TaskResult) { return @{ Done = $false; Reason = 'unreadable' } }

    # [int] would THROW here, and precisely on the codes this function exists to catch.
    # LastTaskResult is a UInt32 and every HRESULT failure has the high bit set, so its
    # unsigned value exceeds Int32.MaxValue: the 0x80040154 cited above arrives as
    # 2147746132. The exception escaped Invoke-StorageSense, Invoke-Phase recorded
    # DeepSystemCleanup as failed, and Clear-WindowsOld never ran.
    # The first test written for this passed the PowerShell literal 0x80040154, which the
    # parser types as Int32 -2147221164 - so the cast succeeded and the test was green
    # BECAUSE of the defect. Tests for this function must use the production type.
    $resultValue = [long]0
    if (-not [long]::TryParse([string]$TaskResult, [ref]$resultValue)) {
        return @{ Done = $false; Reason = 'unreadable' }
    }
    if ($resultValue -ne 0) { return @{ Done = $false; Reason = 'failed' } }
    if ($null -eq $FreedBytes) { return @{ Done = $false; Reason = 'not-measured' } }
    if ([long]$FreedBytes -le 0) { return @{ Done = $false; Reason = 'nothing-freed' } }
    return @{ Done = $true; Reason = 'success' }
}

function Wait-StorageSenseTask {
    <#
    .SYNOPSIS
        Waits for the Storage Sense task to stop running
    .DESCRIPTION
        Split out in v2.20 so the wait can be tested without a scheduler and without
        actually waiting two minutes: the caller injects how to read the task, how to
        read its info, and how to wait.

        'vanished' is a distinct outcome because the loop used to break on a task that
        disappeared while leaving its finished flag false, so the caller announced "did
        not finish within 120 seconds" after five - a number that never happened.

        Returns Outcome ('finished' | 'vanished' | 'timeout' | 'unverifiable'), Elapsed
        seconds and the last Task seen. 'unverifiable' means the task was never observed
        running AND its previous run time could not be read before the start, so there is
        nothing to compare against - it is not a failure, but it is not evidence of a run
        either, and the caller must not treat it as one.
    #>
    param(
        [scriptblock]$GetTask,
        [scriptblock]$GetTaskInfo,
        [AllowNull()][object]$LastRunBefore,
        [int]$TimeoutSeconds = 120,
        [int]$CheckInterval = 5,
        [scriptblock]$Wait = { param($seconds) Start-Sleep -Seconds $seconds }
    )

    $elapsed = 0
    $wasRunning = $false
    $task = $null

    while ($elapsed -lt $TimeoutSeconds) {
        & $Wait $CheckInterval
        $elapsed += $CheckInterval

        # Task states are language-independent: Ready, Running, Disabled
        $task = & $GetTask
        if (-not $task) {
            return @{ Outcome = 'vanished'; Elapsed = $elapsed; Task = $null }
        }

        if ($task.State -eq 'Running') {
            $wasRunning = $true
            continue
        }

        if ($wasRunning) {
            # Was running and is not any more
            return @{ Outcome = 'finished'; Elapsed = $elapsed; Task = $task }
        }

        if ($elapsed -ge 10) {
            # Never observed as Running - it may simply have been quicker than the poll
            # interval. The task's own LastRunTime moving is the evidence.
            #
            # Raised in review: without a baseline there is no evidence to weigh, and the
            # old disjunction let the MISSING baseline satisfy the test, because -not $null
            # is true. Any readable task info then returned "finished" for a task that may
            # never have started - a false success that goes on to skip all 23 cleanmgr
            # handlers.
            #
            # Corrected again in the next review round: the first repair returned here at
            # once, which gave a slow-starting task no chance to be seen and let cleanmgr
            # start alongside it. Keep watching instead - being observed Running is direct
            # evidence and needs no baseline - and only answer "unverifiable" if the whole
            # window passes without ever seeing it.
            if ($null -ne $LastRunBefore) {
                $infoNow = & $GetTaskInfo $task
                if ($infoNow -and $infoNow.LastRunTime -ne $LastRunBefore) {
                    return @{ Outcome = 'finished'; Elapsed = $elapsed; Task = $task }
                }
            }
        }
    }

    # Never seen running, and there was no previous run time to compare against: the window
    # is over and nothing about this invocation was ever observed. That is not a timeout in
    # the useful sense - there is simply no evidence either way, and the caller must not
    # read it as one.
    if (-not $wasRunning -and $null -eq $LastRunBefore) {
        return @{ Outcome = 'unverifiable'; Elapsed = $elapsed; Task = $task }
    }

    return @{ Outcome = 'timeout'; Elapsed = $elapsed; Task = $task }
}

function Invoke-StorageSense {
    <#
    .SYNOPSIS
        Runs Storage Sense cleanup
    #>
    Write-Log "Storage Sense" -Level SECTION

    # v2.20: the one step users asked to be able to switch off on its own. Until now the
    # only way was -SkipCleanup, which also suppresses temp files, browsers, dev caches,
    # Docker/WSL, Visual Studio and the driver store - everything, to avoid one step.
    if ($ReportOnly) {
        Write-Log "Would run: Storage Sense" -Level DETAIL
        return
    }

    # cleanmgr's saved selection lives under this sageset. Both are needed up front: the
    # sweep below runs on every path that is allowed to change the system, not only when
    # cleanmgr is reached. (-ReportOnly returns above because it promises to change
    # nothing at all; -SkipDiskCleanup returns AFTER the sweep, see below.)
    $sageset = 9999
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

    # Sweep leftovers from a previous run before doing anything else. The cleanmgr branch
    # deliberately skips its own sweep while cleanmgr is still running (it would pull the
    # configuration out from under it), and Storage Sense returns before that branch is
    # reached - so a timed-out run followed only by successful Storage Sense runs would
    # otherwise leave these flags in the registry forever. Caught in review before release.
    #
    # Gated on cleanmgr not running: a previous run's cleanmgr may still be working in the
    # background, and sweeping now would pull its configuration out from under it - which
    # is precisely what the finally below refuses to do (also raised in review).
    if (-not (Get-Process -Name 'cleanmgr' -ErrorAction SilentlyContinue)) {
        Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-ItemProperty -Path $_.PSPath -Name "StateFlags$sageset" -Force -ErrorAction SilentlyContinue
        }
    }

    # After the sweep, deliberately (raised in review). The flag means "do not run this
    # step", not "do not touch anything": returning before the sweep left a timed-out
    # previous run's StateFlags in the registry forever, which is the exact case the sweep
    # was added for.
    if ($SkipDiskCleanup) {
        Write-Log "Storage Sense / Disk Cleanup skipped (parameter)" -Level INFO
        $script:Stats.DiskCleanupStatus = 'skipped-parameter'
        return
    }

    # Try Storage Sense first (Windows 11)
    #
    # v2.20: the task was looked up at "\Microsoft\Windows\DiskCleanup\", where it does not
    # exist - that folder holds SilentCleanup. The real one lives under
    # "\Microsoft\Windows\DiskFootprint\". So this branch was UNREACHABLE on every machine
    # and every run fell through to the legacy cleanmgr path: 10 seconds on a fresh VM,
    # 15 minutes on a real workstation (measured: 901s of a 1101s run, and it did not even
    # finish). Searching by name instead of by a hardcoded path also survives the folder
    # moving again.
    $ssTaskName = "StorageSense"
    $ssTasks = @(Get-ScheduledTask -TaskName $ssTaskName -ErrorAction SilentlyContinue)
    # Windows ships exactly one. If a machine somehow has more, say so and take none:
    # silently picking the first of several tasks with the same name means starting
    # something nobody identified (raised in review).
    $ssSelection = Select-StorageSenseTask -Tasks $ssTasks

    # Set by every branch that has already said why cleanmgr is being used, so the
    # fallback below cannot contradict it. Raised in review: an ambiguous lookup logged
    # both "2 tasks with that name - not guessing" and, two lines later, "task not found".
    $ssExplained = $false

    if ($ssSelection.Reason -eq 'ambiguous') {
        $ssExplained = $true
        Write-Log "Storage Sense: $($ssTasks.Count) tasks with that name ($(($ssTasks | ForEach-Object { $_.TaskPath }) -join ', ')) - not guessing, using Disk Cleanup" -Level INFO
    }
    $task = $ssSelection.Task

    # v2.20, corrected in review: pin the exact task. Later lookups searched by name only
    # and took the first hit, which quietly undid the refusal-to-guess rule above the
    # moment a second same-named task appeared while we were waiting.
    $ssTaskPath = if ($task) { $task.TaskPath } else { $null }

    # Raised in review, then measured: -TaskPath rejects $null with a binding error that
    # -ErrorAction SilentlyContinue does NOT suppress, so a task object without a path
    # would turn every later lookup into an exception - and the wait would read that as
    # "the task vanished". The path is only passed when there is one.
    $ssLookup = @{ TaskName = $ssTaskName; ErrorAction = 'SilentlyContinue' }
    if ($ssTaskPath) { $ssLookup['TaskPath'] = $ssTaskPath }

    # Verified below; only a task that demonstrably ran successfully skips cleanmgr
    $storageSenseDone = $false

    # A disabled task cannot be started - fall back to cleanmgr instead of
    # waiting the full timeout for a task that never runs (v2.14)
    if ($task -and $task.State -ne 'Disabled') {
        Write-Log "Running Storage Sense..." -Level INFO

        # v2.20: compare against the task's OWN previous run time, not wall-clock. The old
        # code compared LastRunTime with $startTime taken in this process, which is a
        # different clock granularity and rounds the wrong way.
        $infoBefore = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $lastRunBefore = if ($infoBefore) { $infoBefore.LastRunTime } else { $null }

        # Free space before the task, so its success can be judged on evidence rather than
        # on an exit code (see the verification below)
        $sysDriveLetter = ($env:SystemDrive).TrimEnd(':')
        $freeBefore = $null
        try { $freeBefore = (Get-PSDrive -Name $sysDriveLetter -ErrorAction Stop).Free } catch { $freeBefore = $null }

        $started = $false
        try {
            $task | Start-ScheduledTask -ErrorAction Stop
            $started = $true
        } catch {
            # v2.20: the start used to be -ErrorAction SilentlyContinue with the result
            # ignored, so a task that never started still cost the full 120s wait before
            # anything was reported
            Write-Log "Storage Sense could not be started ($($_.Exception.Message)) - using Disk Cleanup" -Level INFO
            $ssExplained = $true
        }

        if ($started) {
            $timeout = 120  # 2 minutes max
            $waitResult = Wait-StorageSenseTask `
                -GetTask { @(Get-ScheduledTask @ssLookup) | Select-Object -First 1 } `
                -GetTaskInfo { param($t) $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue } `
                -LastRunBefore $lastRunBefore `
                -TimeoutSeconds $timeout `
                -CheckInterval 5
            # Only overwrite when the wait actually saw a task: on 'vanished' the original
            # selection is kept, so the fallback below does not also announce "task not
            # found" for something that was found and then disappeared.
            if ($waitResult.Task) { $task = $waitResult.Task }

            if ($waitResult.Outcome -eq 'finished') {
                # v2.20 fail-closed: a task that ran and FAILED used to be logged as
                # "Storage Sense completed" and cleanmgr was skipped - a silent failure that
                # would have left the machine uncleaned while the run reported success.
                # Verified on a live machine where this task returns 0x80040154.
                $infoAfter = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                $taskResult = if ($infoAfter) { $infoAfter.LastTaskResult } else { $null }

                # $null means "could not be measured", which is not the same answer as
                # "freed nothing" - the old code collapsed both into 0.
                $freedBySense = $null
                try {
                    $freeAfter = (Get-PSDrive -Name $sysDriveLetter -ErrorAction Stop).Free
                    if ($null -ne $freeBefore) { $freedBySense = $freeAfter - $freeBefore }
                } catch { $freedBySense = $null }

                $verdict = Get-StorageSenseVerdict -TaskResult $taskResult -FreedBytes $freedBySense
                $storageSenseDone = $verdict.Done

                switch ($verdict.Reason) {
                    'success'      { Write-Log "Storage Sense completed - $(Format-FileSize $freedBySense)" -Level SUCCESS }
                    'unreadable'   { Write-Log "Storage Sense ran but its result could not be read - using Disk Cleanup as well" -Level INFO }
                    'failed'       { Write-Log ("Storage Sense failed (task result 0x{0:X8}) - using Disk Cleanup instead" -f $taskResult) -Level INFO }
                    'not-measured' { Write-Log "Storage Sense reported success but free space could not be measured - running Disk Cleanup as well" -Level INFO }
                    'nothing-freed' { Write-Log "Storage Sense reported success but freed nothing measurable - running Disk Cleanup as well" -Level INFO }
                    default        { Write-Log "Storage Sense verdict '$($verdict.Reason)' not recognised - running Disk Cleanup as well" -Level INFO }
                }
            } elseif ($waitResult.Outcome -eq 'vanished') {
                # v2.20, corrected in review: this path used to fall into the timeout
                # message below, so a task that disappeared after five seconds was
                # reported as having failed to finish within 120 - a number that never
                # happened on that run.
                Write-Log "Storage Sense task disappeared while being watched - using Disk Cleanup instead" -Level INFO
            } elseif ($waitResult.Outcome -eq 'unverifiable') {
                Write-Log "Storage Sense: its previous run time could not be read, so there is no way to tell whether this run happened - using Disk Cleanup instead" -Level INFO
            } else {
                # WARNING, not INFO (restored in review): falling back to cleanmgr is a
                # fine outcome, but this particular one leaves a task we asked for and
                # could not account for, and cleanmgr is about to start alongside it. The
                # v2.20 draft downgraded this to INFO and dropped the counter, so a run
                # where Storage Sense hung for two minutes printed COMPLETED SUCCESSFULLY
                # in green.
                Write-Log "Storage Sense did not finish within $timeout seconds - using Disk Cleanup instead" -Level WARNING
                $script:Stats.WarningsCount++

                $task = @(Get-ScheduledTask @ssLookup) | Select-Object -First 1
                if ($task -and $task.State -eq 'Running') {
                    # The stop used to be fire-and-forget with an unconditional "stopped"
                    # line after it (raised in review). Two cleaners deleting at once is
                    # exactly the state the free-space accounting cannot describe, so the
                    # claim is now made only when the task actually stopped.
                    $task | Stop-ScheduledTask -ErrorAction SilentlyContinue
                    $taskAfterStop = @(Get-ScheduledTask @ssLookup) | Select-Object -First 1
                    if ($taskAfterStop -and $taskAfterStop.State -eq 'Running') {
                        Write-Log "Storage Sense task could not be stopped and is still running - Disk Cleanup will run alongside it, so the freed figures below cover both" -Level WARNING
                        $script:Stats.WarningsCount++
                    } else {
                        Write-Log "Storage Sense task stopped" -Level INFO
                    }
                }
            }

            # Every branch above has stated its own reason
            $ssExplained = $true
        }
    }

    if ($storageSenseDone) {
        # Storage Sense demonstrably did the work, so cleanmgr is not run at all. Recorded
        # so the JSON distinguishes this from "Disk Cleanup ran and completed" - they free
        # different things, and a consumer comparing runs needs to know which one happened.
        $script:Stats.DiskCleanupStatus = 'storage-sense'
    }

    if (-not $storageSenseDone) {
        # Fallback to cleanmgr. Every other reason for landing here (ambiguous lookup,
        # start failed, task failed, timed out, vanished, unverifiable) has already said
        # so in its own words and set $ssExplained, so only the two states that produce no
        # message of their own are reported here.
        if (-not $ssExplained) {
            if (-not $task) {
                Write-Log "Storage Sense task not found, using Disk Cleanup..." -Level INFO
            } elseif ($task.State -eq 'Disabled') {
                Write-Log "Storage Sense task is disabled, using Disk Cleanup..." -Level INFO
            }
        }

        # Configure cleanup categories ($sageset / $regPath are set at the top of the
        # function, because the leftover sweep needs them on every path)

        # Note (v2.14): "Previous Installations" removed - Windows.old deletion must go
        # through Clear-WindowsOld which asks for user confirmation.
        # "Windows ESD installation files" removed - ESD files are needed for "Reset this PC".
        #
        # v2.16: list reconciled with the actual registry on Windows 11 25H2.
        # Removed (no such handler exists, they were silently skipped by Test-Path):
        #   "Memory Dump Files", "Windows Error Reporting Archive Files",
        #   "Windows Error Reporting Queue Files"
        # Added: "Windows Error Reporting Files" (the real handler name),
        #   "D3D Shader Cache", "Language Pack", "Windows Reset Log Files",
        #   "Feedback Hub Archive log files", "Diagnostic Data Viewer database files",
        #   "RetailDemo Offline Content".
        # Deliberately NOT added, despite existing in the registry:
        #   "DownloadsFolder"       - that is the user's Downloads folder
        #   "Device Driver Packages" - cleanmgr picks driver packages by its own closed
        #                             heuristic, which would bypass the conservative rule
        #                             in Clear-DriverStore (unused AND superseded) and is
        #                             neither previewable nor measurable
        #   "Delivery Optimization Files" - handled by Clear-SystemCaches via the
        #                             supported cmdlet, with measurable statistics
        #   "Windows Defender", "Content Indexer Cleaner", "Offline Pages Files"
        #                           - security/search state, no meaningful gain
        $categories = @(
            "Active Setup Temp Folders", "BranchCache", "D3D Shader Cache",
            "Diagnostic Data Viewer database files",
            "Downloaded Program Files", "Feedback Hub Archive log files",
            "Internet Cache Files", "Language Pack", "Old ChkDsk Files",
            "Recycle Bin", "RetailDemo Offline Content", "Setup Log Files",
            "System error memory dump files", "System error minidump files",
            "Temporary Files", "Temporary Setup Files", "Thumbnail Cache",
            "Update Cleanup", "Upgrade Discarded Files", "User file versions",
            "Windows Error Reporting Files", "Windows Reset Log Files",
            "Windows Upgrade Log Files"
        )

        # Defined before the try so the finally can always ask whether it exists
        $cleanmgr = $null
        try {
            # Set StateFlags for cleanup categories.
            # v2.16: count what was actually armed. Previously a failed write was
            # swallowed, and cleanmgr would run with an empty category set, exit 0 and
            # get logged as a success while doing nothing at all.
            $armed = 0
            foreach ($category in $categories) {
                $categoryPath = Join-Path $regPath $category
                if (-not (Test-Path $categoryPath)) {
                    Write-Log "Disk Cleanup handler not present: $category" -Level DETAIL
                    continue
                }
                try {
                    Set-ItemProperty -Path $categoryPath -Name "StateFlags$sageset" -Value 2 -Type DWord -Force -ErrorAction Stop
                    $armed++
                } catch {
                    Write-Log "Could not arm Disk Cleanup handler '$category': $_" -Level WARNING
                    $script:Stats.WarningsCount++
                }
            }

            if ($armed -eq 0) {
                Write-Log "No Disk Cleanup handlers could be armed - skipping cleanmgr" -Level WARNING
                $script:Stats.WarningsCount++
                $script:Stats.DiskCleanupStatus = 'failed'
                return
            }

            # Run cleanmgr with progress feedback and reasonable timeout.
            #
            # Raised in review, then measured: Start-Process on a missing or blocked
            # executable leaves the variable $null, and $null.HasExited is also $null - so
            # "-not $cleanmgr.HasExited" is TRUE and the loop below reported progress every
            # minute for the full fifteen, then set DiskCleanupPending and warned that an
            # elevated process was still deleting. All for a process that never started.
            # Reachable on Server SKUs without Desktop Experience and under AppLocker/WDAC.
            $cleanmgr = $null
            try {
                $cleanmgr = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" `
                    -WindowStyle Hidden -PassThru -ErrorAction Stop
            } catch {
                $cleanmgr = $null
            }

            if (-not $cleanmgr) {
                Write-Log "Disk Cleanup could not be started (cleanmgr.exe is missing or blocked) - it cleaned nothing" -Level WARNING
                $script:Stats.WarningsCount++
                $script:Stats.DiskCleanupStatus = 'failed'
                return
            }

            # v2.16: raised from 420s. cleanmgr regularly needs longer on a workstation
            # with a large component store, and killing it produced a warning on every
            # single run while cleanmgr kept working in the background anyway.
            #
            # v2.22: waiting on HasExited alone was the wrong model of "the work is done".
            # Measured on a live workstation: cleanmgr /sagerun finished in about ten
            # seconds, closed its window and then simply stayed resident - CPU, all three
            # I/O counters and its six threads frozen, every thread in Wait. The run then
            # sat here for the remaining ~890 seconds and finally declared the FINISHED
            # cleanup partial. Both halves of that are wrong, and the second is the worse
            # one: it is the same class of dishonest report v2.20 and v2.21 were spent
            # removing, only inverted - not success that never happened, but incompleteness
            # that never happened.
            #
            # So a second, independent completion signal: total stillness. If the process
            # has done no CPU work and no I/O at all across $idleChecksRequired consecutive
            # checks, its work is over whether or not it bothered to exit.
            $maxWait = 900  # 15 minutes
            $checkInterval = 10
            # Two full minutes of absolute stillness. Deliberately far longer than needed
            # to observe the measured case: a process mid-delete moves at least the "other
            # operations" counter, so this is not a race with slow work - it is a margin
            # against a pause nobody has observed yet. The cost of being wrong is bounded
            # anyway: the registry sweep below still refuses to touch a process that has
            # not exited, so a premature verdict cannot pull configuration out from under
            # a cleanmgr that turns out to be working after all.
            $idleChecksRequired = 12

            $waitOutcome = Wait-CleanmgrCompletion `
                -HasExited { $cleanmgr.HasExited } `
                -GetFingerprint { Get-ProcessActivityFingerprint -ProcessId $cleanmgr.Id } `
                -MaxWaitSeconds $maxWait -CheckInterval $checkInterval -IdleChecksRequired $idleChecksRequired `
                -OnProgress { param($seconds) Write-Log "Disk Cleanup still running... ($seconds seconds)" -Level INFO }

            $elapsed = $waitOutcome.Elapsed
            $finishedWhileResident = $waitOutcome.Outcome -eq 'idle-resident'

            if ($cleanmgr.HasExited -and $cleanmgr.ExitCode -ne 0) {
                # v2.16: the exit code used to be ignored entirely, so a crash one second
                # in was still logged as a success
                Write-Log "Disk Cleanup exited with code $($cleanmgr.ExitCode) - results unverified" -Level WARNING
                $script:Stats.WarningsCount++
                $script:Stats.DiskCleanupStatus = 'failed'
            } elseif ($cleanmgr.HasExited) {
                Write-Log "Disk Cleanup completed ($armed categories)" -Level SUCCESS
                $script:Stats.DiskCleanupStatus = 'completed'
            } elseif ($finishedWhileResident) {
                # The work is done; only the process is still here. Not a warning: nothing
                # went wrong and nothing is pending, so DiskCleanupPending stays false and
                # the figures below are final.
                Write-Log "Disk Cleanup completed ($armed categories) - finished after $elapsed seconds, then stayed resident without doing anything further" -Level SUCCESS
                Write-Log "cleanmgr.exe is still in the process list but has been completely idle for $($idleChecksRequired * $checkInterval) seconds - not waiting out the remaining $($maxWait - $elapsed) seconds" -Level DETAIL
                $script:Stats.DiskCleanupStatus = 'completed-resident'
            } else {
                # Genuinely still working when the timeout expired. Killing it would be
                # worse - cleanmgr keeps working after a kill and the deletion is
                # mid-flight (v2.16). But this is not an informational event either:
                # everything measured after this point is partial, the run is about to
                # print a total and write its JSON while an elevated process is still
                # deleting, and the freed bytes it goes on to reclaim are counted by nobody.
                $script:Stats.DiskCleanupPending = $true
                Write-Log "Disk Cleanup exceeded $maxWait seconds and is still running - it continues in the background, so the freed figures below are partial" -Level WARNING
                $script:Stats.WarningsCount++
                $script:Stats.DiskCleanupStatus = 'timeout'
            }
        } finally {
            # Remove StateFlags to avoid leaving traces in the registry.
            # v2.16: sweep every handler, not just the ones from $categories - flags left
            # by an interrupted run or by an older version of this list stayed forever
            # (four such leftovers were found on a live machine).
            #
            # v2.20: but NOT while cleanmgr is still running. The timeout branch above
            # deliberately leaves it working in the background, and this sweep then pulled
            # its configuration out from under it. Whether cleanmgr re-reads the flags per
            # handler or only once at startup is not something to guess at while it holds
            # an elevated deletion loop. The flags are swept by the next run's own sweep,
            # which is exactly the leftover case v2.16 added it for.
            if ($cleanmgr -and -not $cleanmgr.HasExited) {
                Write-Log "Disk Cleanup is still running - its registry configuration will be swept by the next run" -Level DETAIL
            } else {
                Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-ItemProperty -Path $_.PSPath -Name "StateFlags$sageset" -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              MAIN EXECUTION
#═══════════════════════════════════════════════════════════════════════════════

function Show-Banner {
    try { Clear-Host } catch { }

    $banner = @"

  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                      ║
  ║      ██████╗██╗     ███████╗ █████╗ ███╗   ██╗                       ║
  ║     ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║                       ║
  ║     ██║     ██║     █████╗  ███████║██╔██╗ ██║                       ║
  ║     ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║                       ║
  ║     ╚██████╗███████╗███████╗██║  ██║██║ ╚████║                       ║
  ║      ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝                       ║
  ║                                                                      ║
  ║            Ultimate Windows 11 Maintenance Script v$($script:Version)              ║
  ║                                                                      ║
  ╚══════════════════════════════════════════════════════════════════════╝

"@

    Write-Host $banner -ForegroundColor Cyan

    # System info
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $osVersion = $os.Caption
    $osBuild = $os.BuildNumber

    Write-Host "  System: $osVersion (Build $osBuild)" -ForegroundColor DarkGray
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
    Write-Host "  Started: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host "  Log: $script:LogPath" -ForegroundColor DarkGray

    if ($ReportOnly) {
        Write-Host ""
        Write-Host "  >>> REPORT MODE - No changes will be made <<<" -ForegroundColor Yellow
    }

    Write-Host ""
}

function Show-FinalStatistics {
    <#
    .DESCRIPTION
        v2.17 (p.21 of the audit): this runs from Start-WinClean's finally block, so any
        exception here (a Get-PSDrive provider returning 0 for both Used and Free, for
        instance, dividing by zero below) would REPLACE whatever exception the try block
        was already reporting - the one the user actually needs to see. The whole body
        is wrapped so this function can never mask that.
    #>
    try {
        Show-FinalStatisticsBody
    } catch {
        Write-Host ""
        Write-Host "  Could not display the final summary: $_" -ForegroundColor Yellow
        Write-Host "  Log: $script:LogPath" -ForegroundColor DarkGray
    }
}

function Show-FinalStatisticsBody {
    $elapsed = (Get-Date) - $script:Stats.StartTime
    $elapsedStr = "{0:D2}:{1:D2}:{2:D2}" -f [int]$elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds

    # Get disk info
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeSpace = [math]::Round($drive.Free / 1GB, 2)
    $totalSize = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $capacity = $drive.Used + $drive.Free
    $freePercent = if ($capacity -gt 0) { [math]::Round(($drive.Free / $capacity) * 100, 1) } else { 0 }

    Clear-AllProgress

    # Box dimensions
    $boxWidth = 70    # Inner width (matches banner)
    $labelWidth = 18  # Width for label column (e.g., "Space freed:")

    # Determine overall status
    $hasErrors = $script:Stats.ErrorsCount -gt 0
    $hasWarnings = $script:Stats.WarningsCount -gt 0
    $statusText = if ($hasErrors) { "COMPLETED WITH ERRORS" } elseif ($hasWarnings) { "COMPLETED WITH WARNINGS" } else { "COMPLETED SUCCESSFULLY" }
    $headerColor = if ($hasErrors) { "Red" } elseif ($hasWarnings) { "Yellow" } else { "Green" }

    Write-Host ""

    # Header with Cyan frame, status-colored text
    $titlePadding = [math]::Max(0, $boxWidth - $statusText.Length)
    $leftPad = [math]::Floor($titlePadding / 2)
    $rightPad = $titlePadding - $leftPad

    Write-Host "  ╔$("═" * $boxWidth)╗" -ForegroundColor Cyan
    Write-Host "  ║" -NoNewline -ForegroundColor Cyan
    Write-Host (" " * $leftPad) -NoNewline
    Write-Host $statusText -NoNewline -ForegroundColor $headerColor
    Write-Host (" " * $rightPad) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "  ╠$("═" * $boxWidth)╣" -ForegroundColor Cyan

    # Helper function for consistent line formatting with icons
    function Write-StatLine {
        param(
            [string]$Icon,
            [string]$Label,
            [string]$Value,
            [string]$IconColor = "Cyan",
            [string]$ValueColor = "Green"
        )
        # $labelWidth is inherited from parent scope (18)
        # Layout: space(1) + icon(1) + space(1) + label(18) + gap(2) + value(47) = 70
        $valueWidth = $boxWidth - $labelWidth - 5  # 5 = icon(1) + spaces(2) + gap(2)

        $labelPadded = $Label.PadRight($labelWidth)
        $valuePadded = $Value.PadRight($valueWidth)

        Write-Host "  ║ " -NoNewline -ForegroundColor Cyan
        Write-Host "$Icon " -NoNewline -ForegroundColor $IconColor
        Write-Host "$labelPadded  " -NoNewline -ForegroundColor White  # 2 spaces after label
        Write-Host $valuePadded -NoNewline -ForegroundColor $ValueColor
        Write-Host "║" -ForegroundColor Cyan
    }

    # Duration
    Write-StatLine -Icon ">" -Label "Duration:" -Value $elapsedStr -IconColor "DarkGray" -ValueColor "White"

    # Updates. v2.19: Windows updates are genuinely installed (PSWindowsUpdate reports
    # per-update results), but the app number is what winget OFFERED - it silently skips
    # pinned/manifest-less/UAC-cancelled packages, so claiming it as "installed" overstated
    # the result. Label each honestly. Value stays <= 47 chars so the box border aligns.
    $winInstalled = $script:Stats.WindowsUpdatesCount
    $appsOffered  = $script:Stats.AppUpdatesOffered
    if (($winInstalled + $appsOffered) -gt 0) {
        $updatesStr = "Windows: $winInstalled installed, Apps: $appsOffered offered"
        # ASCII "^" instead of "↑" (v2.17, p.20 of the audit): same ambiguous-width
        # box-alignment issue as "⚠" below, just not caught the first time around
        Write-StatLine -Icon "^" -Label "Updates:" -Value $updatesStr -IconColor "Green" -ValueColor "Green"
    }

    # Space freed (highlight if significant)
    $freedStr = Format-FileSize $script:Stats.TotalFreedBytes
    $freedColor = if ($script:Stats.TotalFreedBytes -gt 1GB) { "Green" } elseif ($script:Stats.TotalFreedBytes -gt 100MB) { "Yellow" } else { "White" }
    Write-StatLine -Icon ">" -Label "Space freed:" -Value $freedStr -IconColor $freedColor -ValueColor $freedColor

    # Freed by category (if any)
    if ($script:Stats.FreedByCategory.Count -gt 0) {
        Write-Host "  ╟$("─" * $boxWidth)╢" -ForegroundColor Cyan
        $sortedCats = @($script:Stats.FreedByCategory.GetEnumerator() |
                        Where-Object { $_.Value -gt 0 } | Sort-Object -Property Value -Descending)
        foreach ($cat in ($sortedCats | Select-Object -First 5)) {
            # Right-align category name so its colon lines up with the labels above
            $catLabel = "$($cat.Key):".PadLeft($labelWidth)
            $catValue = Format-FileSize $cat.Value
            Write-StatLine -Icon " " -Label $catLabel -Value $catValue -ValueColor "DarkGray"
        }
        # v2.17: account for the remainder. With 12 possible categories the listed rows
        # did not add up to "Space freed", which read as an arithmetic error.
        if ($sortedCats.Count -gt 5) {
            $rest = ($sortedCats | Select-Object -Skip 5 | Measure-Object -Property Value -Sum).Sum
            $restLabel = "Other ($($sortedCats.Count - 5)):".PadLeft($labelWidth)
            Write-StatLine -Icon " " -Label $restLabel -Value (Format-FileSize $rest) -ValueColor "DarkGray"
        }
    }

    Write-Host "  ╠$("═" * $boxWidth)╣" -ForegroundColor Cyan

    # Disk space
    $diskStr = "$freeSpace GB / $totalSize GB ($freePercent% free)"
    $diskColor = if ($freePercent -lt 10) { "Red" } elseif ($freePercent -lt 20) { "Yellow" } else { "White" }
    Write-StatLine -Icon ">" -Label "Disk space:" -Value $diskStr -IconColor $diskColor -ValueColor $diskColor

    # Warnings/Errors (if any)
    if ($hasWarnings -or $hasErrors) {
        $issueStr = "$($script:Stats.WarningsCount) warnings, $($script:Stats.ErrorsCount) errors"
        # ASCII "!"/"X" instead of "⚠"/"✗": both are ambiguous-width in some
        # terminals and break box alignment (v2.14 / v2.17 p.20 of the audit)
        $issueIcon = if ($hasErrors) { "X" } else { "!" }
        $issueColor = if ($hasErrors) { "Red" } else { "Yellow" }
        Write-StatLine -Icon $issueIcon -Label "Issues:" -Value $issueStr -IconColor $issueColor -ValueColor $issueColor
    }

    Write-Host "  ╚$("═" * $boxWidth)╝" -ForegroundColor Cyan

    # Reboot notification
    if ($script:Stats.RebootRequired) {
        Write-Host ""
        Write-Host "  ! " -NoNewline -ForegroundColor Yellow
        Write-Host "Reboot required to complete Windows updates!" -ForegroundColor Yellow

        if (Test-InteractiveConsole) {
            Write-Host ""
            Write-Host "  Reboot now? (y/N): " -NoNewline -ForegroundColor Yellow

            $response = Read-Host
            if ($response -match "^[YyДд]") {
                Write-Host "  Rebooting in 10 seconds... Press Ctrl+C to cancel" -ForegroundColor Yellow
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            } else {
                Write-Host "  Remember to reboot later!" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Please reboot manually to complete updates." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  Log: $script:LogPath" -ForegroundColor DarkGray
    Write-Host ""

    # Wait for keypress before closing (no timeout - window stays open)
    if (Test-InteractiveConsole) {
        Write-Host "  Press any key to exit..." -ForegroundColor DarkGray

        # Clear keyboard buffer first
        while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }

        # Wait indefinitely for keypress
        [Console]::ReadKey($true) | Out-Null
    } else {
        Write-Host "  Non-interactive mode - exiting automatically." -ForegroundColor DarkGray
    }
}

function Write-ResultJson {
    <#
    .SYNOPSIS
        Writes a machine-readable run summary (JSON) for automated testing/stands
    #>
    param([string]$Path)

    if (-not $Path) { return }

    try {
        $elapsed = (Get-Date) - $script:Stats.StartTime

        $result = [ordered]@{
            Version             = $script:Version
            Timestamp           = (Get-Date).ToString('o')
            DurationSeconds     = [math]::Round($elapsed.TotalSeconds, 1)
            ReportOnly          = [bool]$ReportOnly
            Parameters          = [ordered]@{
                SkipUpdates       = [bool]$SkipUpdates
                SkipCleanup       = [bool]$SkipCleanup
                SkipRestore       = [bool]$SkipRestore
                SkipDevCleanup    = [bool]$SkipDevCleanup
                SkipDockerCleanup = [bool]$SkipDockerCleanup
                SkipVSCleanup     = [bool]$SkipVSCleanup
                SkipDiskCleanup   = [bool]$SkipDiskCleanup
                DisableTelemetry  = [bool]$DisableTelemetry
            }
            TotalFreedBytes     = [long]$script:Stats.TotalFreedBytes
            FreedByCategory     = @{} + $script:Stats.FreedByCategory
            WindowsUpdatesCount = $script:Stats.WindowsUpdatesCount
            # v2.19: renamed from AppUpdatesCount. This is the number of app updates winget
            # OFFERED, not a confirmed install count (winget upgrade --all cannot report the
            # latter). No shipped consumer reads this field; the nightly stand does not.
            AppUpdatesOffered   = $script:Stats.AppUpdatesOffered
            # v2.21: distinguishes "checked, nothing to upgrade" from "could not check".
            # Both are AppUpdatesOffered = 0, and demoting a missing winget to a warning
            # removed the only other signal a consumer had (a non-zero exit code).
            AppUpdatesStatus    = $script:Stats.AppUpdatesStatus
            WarningsCount       = $script:Stats.WarningsCount
            ErrorsCount         = $script:Stats.ErrorsCount
            RebootRequired      = [bool]$script:Stats.RebootRequired
            # v2.20: true when writing the log file failed at some point. The run still
            # completed, but LogPath below points at an incomplete file - an automated
            # consumer must not treat that log as the full record of what happened.
            LoggingDegraded     = [bool]$script:LogWriteFailed
            # v2.20: true when Disk Cleanup outlived its timeout and was left running.
            # TotalFreedBytes is then a lower bound, not the final figure.
            DiskCleanupPending  = [bool]$script:Stats.DiskCleanupPending
            # v2.22: how that step ended, because the boolean above conflated two states.
            # 'completed-resident' is the measured case where cleanmgr does its work, closes
            # its window and then never exits: finished, nothing pending, figures final.
            # 'timeout' is the genuine overrun the boolean was added for.
            DiskCleanupStatus   = [string]$script:Stats.DiskCleanupStatus
            # 'enabled' means cleanup figures are understated (Defender blocked some
            # deletions without reporting an error); 'unknown' means the check itself
            # failed, so the figures are unverified rather than confirmed good
            ControlledFolderAccess = [string]$script:Stats.ControlledFolderAccess
            # null for a normal run; a reason string when the run stopped early (v2.17)
            Aborted             = $script:Stats.Aborted
            # Dispatch status of each top-level phase (v2.17 p.11; tri-state in v2.19).
            # Completed = invoked and returned without an uncaught exception (NOT proof
            # the work succeeded); Skipped = a skip flag suppressed it; Failed = it threw.
            # For a non-aborted run the three are disjoint and their union is the full
            # phase set, so a name missing from all three means the run stopped before it.
            PhasesCompleted     = @($script:Stats.PhasesCompleted)
            PhasesFailed        = @($script:Stats.PhasesFailed)
            PhasesSkipped       = @($script:Stats.PhasesSkipped)
            LogPath             = $script:LogPath
        }

        $resultDir = Split-Path -Path $Path -Parent
        if ($resultDir -and -not (Test-Path -LiteralPath $resultDir)) {
            New-Item -ItemType Directory -Path $resultDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $result | ConvertTo-Json -Depth 4 | Out-File -FilePath $Path -Encoding utf8
        Write-Log "Result JSON written: $Path" -Level INFO
    } catch {
        # v2.20: this comment said "must be loud" while the code raised a warning, and the
        # exit code is decided by ErrorsCount alone - so a run that failed to produce the
        # artefact the user explicitly asked for still exited 0 and printed "completed with
        # warnings". The stand then reads a stale file from the previous run as a fresh
        # result. The user asked for this file: not producing it is a failure of the run.
        Write-Log "Failed to write result JSON: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    }
}

function Complete-WinCleanRun {
    <#
    .SYNOPSIS
        The single end-of-run path: result JSON, final summary, log handle release
    .DESCRIPTION
        v2.22, raised in external review. Three paths ended a run - the normal finally, a
        successful self-update, and a declined pending-reboot prompt - and only the first
        released the log handle or showed a summary. The other two hand-copied whichever
        parts someone had remembered at the time, which is exactly how v2.21 came to ship
        two separate fixes to the same few lines (first a missing result JSON, then an
        unconditional exit 0 over a run that had errors). The defect was never any one
        omission; it was that the list existed in three places. Anything added here from
        now on reaches every exit.

        Latched, so a path that completes the run explicitly and then unwinds through a
        finally does not write the artefacts twice.
    #>
    param([string]$ResultPath)

    if ($script:RunCompleted) { return }
    $script:RunCompleted = $true

    # JSON goes first: Show-FinalStatistics may block on a keypress in interactive
    # mode, and automated runs must get the result regardless.
    Write-ResultJson -Path $ResultPath

    # An aborted run has no maintenance to summarise, and the summary header would
    # announce "COMPLETED SUCCESSFULLY" over a run that deliberately did nothing.
    # Preserved behaviour: neither abort path ever showed it.
    if (-not $script:Stats.Aborted) {
        Show-FinalStatistics
    }

    # Release the log file handle (v2.17, p.7): a stand or the user may want to move or
    # zip the log right after the run finishes.
    # v2.20: guarded. Dispose on a writer whose stream already failed throws, and this
    # used to be the last statement of the outer finally - the exception escaped
    # Start-WinClean and the entry point never reached its exit-code check, so a run with
    # errors could still exit 0 (raised in review).
    if ($script:LogWriter) {
        try { $script:LogWriter.Dispose() } catch { }
        $script:LogWriter = $null
        $script:LogWriterPath = $null
    }
}

function Invoke-Phase {
    <#
    .SYNOPSIS
        Runs one top-level phase of Start-WinClean with its own exception boundary
    .DESCRIPTION
        v2.17 (p.11 of the audit): the 9 phases used to share a single try/catch, so an
        exception in phase 3 meant phases 4-9 never ran at all - silently, with only a
        generic "Critical error" line to show for it. Each phase now gets its own
        boundary and is recorded in $script:Stats.PhasesCompleted/PhasesFailed, which
        Write-ResultJson exposes so an automated stand can tell "everything ran" from
        "phase 6 threw and phases 7-9 are simply missing".

        v2.19: -Skip records a phase the user turned off with a skip flag in a third
        bucket, PhasesSkipped, instead of running an empty body and marking it Completed
        (which conflated "ran and did nothing" with "was skipped"). This also carries the
        "... skipped (parameter)" log line that used to come from each phase's own inner
        guard, now that the skip decision lives at the call site. These three buckets are
        a DISPATCH status, not an outcome - see the $script:Stats comment.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [bool]$Skip = $false
    )

    if ($Skip) {
        Write-Log "Phase '$Name' skipped (parameter)" -Level INFO
        $script:Stats.PhasesSkipped += $Name
        return
    }

    try {
        & $Action
        $script:Stats.PhasesCompleted += $Name
    } catch {
        Write-Log "Phase '$Name' failed: $_" -Level ERROR
        $script:Stats.ErrorsCount++
        $script:Stats.PhasesFailed += $Name
    }
}

function Start-WinClean {
    # v2.17: remove a previous result file up front. An early exit used to leave the
    # old JSON in place, and an automated stand would read last week's success as this
    # run's outcome.
    if ($ResultJsonPath -and (Test-Path -LiteralPath $ResultJsonPath)) {
        Remove-Item -LiteralPath $ResultJsonPath -Force -ErrorAction SilentlyContinue
    }

    # v2.19 reset the phase buckets and the step counter here; v2.20 makes the run
    # genuinely fresh. The partial version left freed bytes, warning/error counts,
    # Aborted and StartTime from a previous call in the same session, so the second
    # run's summary and JSON described both runs at once. See New-RunStats.
    $script:Stats = New-RunStats
    $script:ProgressActivities = @()
    $script:InternetConnectionCache = $null
    $script:LogWriteFailed = $false
    # v2.22: the latch on Complete-WinCleanRun, reset with everything else - a second
    # call in the same session must produce its own artefacts, not silently skip them
    # because the first run already completed.
    $script:RunCompleted = $false

    # Initialize log. v2.22 (raised in external review): these two lines were bare Out-File
    # calls, and this runs BEFORE the main try/finally below. A log path that cannot be
    # opened throws there - measured on six of seven bad paths - and the exception escaped
    # Start-WinClean before any safety net existed: no result JSON, no summary, and none of
    # the maintenance, because of the log. Now they degrade like every other log write.
    Write-LogFileLine -Line "WinClean v$($script:Version) - Started at $(Get-Date)" -StartNewFile
    Write-LogFileLine -Line ("=" * 70)

    # v2.17 (p.13 of the audit): recover from a hard-killed previous run before doing
    # anything else - not in ReportOnly, which promises no changes
    if (-not $ReportOnly) {
        Invoke-StaleMarkerRecovery
    }

    # Enable TLS 1.2 for all HTTPS connections (required by PowerShell Gallery, NuGet, etc.)
    # This must be set before any network operations
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Calculate TotalSteps dynamically based on skip flags
    $script:Stats.TotalSteps = 0
    if (-not $SkipUpdates) { $script:Stats.TotalSteps += 2 }      # Windows Update + App Updates
    # v2.19: -SkipCleanup now suppresses the whole cleanup group (system + deep + the
    # developer/Docker/VS categories), matching the documented "skip all cleanup" /
    # "Updates Only" contract. The per-category flags only subtract further inside it,
    # so the progress denominator must nest them under -not $SkipCleanup too.
    if (-not $SkipCleanup) {
        $script:Stats.TotalSteps += 2                                  # System Cleanup + Deep Cleanup
        if (-not $SkipDevCleanup)    { $script:Stats.TotalSteps += 1 } # Developer Caches
        if (-not $SkipDockerCleanup) { $script:Stats.TotalSteps += 1 } # Docker/WSL
        if (-not $SkipVSCleanup)     { $script:Stats.TotalSteps += 1 } # Visual Studio
    }
    # Ensure at least 1 step to avoid division by zero
    if ($script:Stats.TotalSteps -eq 0) { $script:Stats.TotalSteps = 1 }

    Show-Banner

    # Check for pending reboot before starting
    $pendingReboot = Test-PendingReboot
    if ($pendingReboot.RebootRequired) {
        Write-Host ""
        Write-Host "  " -NoNewline
        Write-Host "WARNING: " -NoNewline -ForegroundColor Red
        Write-Host "Pending reboot detected!" -ForegroundColor Yellow
        Write-Host "  Reasons: $($pendingReboot.Reasons -join ', ')" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "  It is recommended to reboot before running maintenance." -ForegroundColor Gray

        # Check if interactive console available (fixed in v2.1)
        if (Test-InteractiveConsole) {
            Write-Host "  Continue anyway? (y/N): " -NoNewline -ForegroundColor Yellow

            $response = Read-Host
            if ($response -notmatch "^[YyДд]") {
                Write-Host ""
                Write-Host "  Operation cancelled. Please reboot and run again." -ForegroundColor Yellow
                Write-Host ""
                # Record the abort so automation does not mistake it for a completed run
                # v2.22: through the shared end-of-run path. This branch used to write the
                # JSON by hand and return, so it released no log handle - one of the three
                # divergent endings that made the same fix necessary twice (external review).
                $script:Stats.Aborted = 'PendingRebootDeclined'
                Complete-WinCleanRun -ResultPath $ResultJsonPath
                return
            }
        } else {
            Write-Host "  Non-interactive mode - continuing despite pending reboot." -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Check for script updates. v2.17: gated by -SkipUpdates - the flag promises no
    # update activity, and this path costs a PSGallery round trip on every run.
    #
    # Guarded (raised in review): this block runs BEFORE the main try/finally, so anything
    # thrown here escaped Start-WinClean entirely - no result JSON, no phase buckets, no
    # exit-code accounting - and killed the run before its first phase. The update check is
    # optional; the maintenance it precedes is not, and must not be lost to it.
    if (-not $SkipUpdates) {
        try {
            $updateInfo = Test-ScriptUpdate
            if ($updateInfo) {
                # v2.22: Invoke-ScriptUpdate reports whether the run is over instead of
                # calling exit itself. A successful self-update replaced the running file,
                # so continuing would perform maintenance with the old code still loaded -
                # the run ends here, but it ends the same way every other run does.
                if (Invoke-ScriptUpdate -UpdateInfo $updateInfo) {
                    Complete-WinCleanRun -ResultPath $ResultJsonPath
                    return
                }
            }
        } catch {
            Write-Log "Update check could not be completed: $_" -Level WARNING
            $script:Stats.WarningsCount++
        }
    }

    # Controlled Folder Access silently blocks deletions inside protected folders while
    # every delete call still reports success, so cleanup looks fine in the log but frees
    # nothing. Warn once up front instead of leaving the user with a misleading report (v2.16).
    # Tri-state and always a string, so consumers (result JSON, stand assertions) get
    # one stable type: 'enabled' / 'disabled' / 'unknown'
    $script:Stats.ControlledFolderAccess = 'disabled'
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        if ($mp.EnableControlledFolderAccess -eq 1) {
            $script:Stats.ControlledFolderAccess = 'enabled'
            Write-Log "Controlled Folder Access is enabled - some deletions may be blocked silently" -Level WARNING
            Write-Log "Add pwsh.exe to the allowed apps list, or cleanup results will be understated" -Level DETAIL
            $script:Stats.WarningsCount++
        }
    } catch {
        # Defender cmdlets unavailable (third-party AV, stripped image, broken WMI).
        # Record it as "unknown" rather than "disabled": reporting the latter would tell
        # an automated stand the numbers are trustworthy when they were never checked.
        $script:Stats.ControlledFolderAccess = 'unknown'
        Write-Log "Could not query Controlled Folder Access state - cleanup figures are unverified" -Level DETAIL
    }

    # v2.17 (p.11 of the audit): each phase now has its own exception boundary inside
    # Invoke-Phase, so a bug in one no longer skips every phase after it. This outer
    # try/finally is a second, coarser safety net - it guarantees the result JSON, the
    # final summary and the log handle release happen even if something outside a
    # phase (or a bug in Invoke-Phase itself) throws.
    try {
        # v2.19: the skip decision for each phase now lives here, at the call site, via
        # -Skip. A skipped phase is recorded in PhasesSkipped (not run and marked
        # Completed), and -SkipCleanup suppresses the ENTIRE cleanup group - system, deep,
        # and the developer/Docker/VS categories - to match the documented "skip all
        # cleanup" / "Updates Only" contract. The per-category flags stay as finer control
        # inside that group. The inner functions keep their own guards for direct callers.
        Invoke-Phase -Name 'Preparation' -Skip:$SkipRestore -Action {
            $null = New-SystemRestorePoint -Description "WinClean $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        }

        # Recorded here, not inside Update-Applications (raised in review): -SkipUpdates
        # stops the phase from dispatching at all, so the branch that sets this inside the
        # function is unreachable in production and the status stayed 'not-run'.
        if ($SkipUpdates) { $script:Stats.AppUpdatesStatus = 'skipped-parameter' }

        Invoke-Phase -Name 'Updates' -Skip:$SkipUpdates -Action {
            Update-WindowsSystem
            Update-Applications
        }

        Invoke-Phase -Name 'SystemCleanup' -Skip:$SkipCleanup -Action {
            Write-Log "SYSTEM CLEANUP" -Level TITLE
            Update-Progress -Activity "System Cleanup" -Status "Cleaning temporary files..."

            Clear-TempFiles
            Clear-BrowserCaches
            Clear-WindowsUpdateCache
            Clear-WinCleanRecycleBin
            Clear-SystemCaches
            Clear-EventLogs
            Clear-DNSCache
            Clear-PrivacyTraces
        }

        Invoke-Phase -Name 'DeveloperCleanup' -Skip:($SkipCleanup -or $SkipDevCleanup) -Action { Clear-DeveloperCaches }

        Invoke-Phase -Name 'DockerWSLCleanup' -Skip:($SkipCleanup -or $SkipDockerCleanup) -Action { Clear-DockerWSL }

        Invoke-Phase -Name 'VisualStudioCleanup' -Skip:($SkipCleanup -or $SkipVSCleanup) -Action { Clear-VisualStudio }

        Invoke-Phase -Name 'DeepSystemCleanup' -Skip:$SkipCleanup -Action {
            Write-Log "DEEP SYSTEM CLEANUP" -Level TITLE
            Update-Progress -Activity "Deep Cleanup" -Status "Running system cleanup..."

            # Driver store first (v2.17): removing packages leaves referenced
            # components in WinSxS, and running DISM afterwards reclaims them in
            # the same pass instead of a week later.
            Clear-DriverStore
            Clear-KernelDumps
            # Neither of these reports what it freed, so measure the drive around them
            Measure-FreeSpaceGain -Category 'ComponentStore' -Operation { Invoke-DISMCleanup }
            # Raised in review: measuring around a step the user switched off credited it
            # with whatever the drive happened to gain meanwhile - DISM releasing files a
            # moment earlier is enough - and printed "DiskCleanup freed approximately
            # 300.00 MB" for something that executed nothing. Invoke-StorageSense is still
            # called so its registry leftovers get swept; it just is not measured.
            if ($SkipDiskCleanup) {
                Invoke-StorageSense
            } else {
                Measure-FreeSpaceGain -Category 'DiskCleanup' -Operation { Invoke-StorageSense }
            }
            Clear-WindowsOld
        }

        # What is taking up space that cleanup deliberately leaves alone (v2.16).
        # Skipped with -SkipCleanup (v2.17): it walks Windows\Installer and the search
        # index, which is expensive and pointless for a user who asked for no cleanup.
        Invoke-Phase -Name 'DiskSpaceReport' -Skip:$SkipCleanup -Action {
            Show-DiskSpaceReport
        }

        Invoke-Phase -Name 'Telemetry' -Action {
            if ($DisableTelemetry) {
                Set-WindowsTelemetry -Disable
            }
        }
    } catch {
        # Should not normally be reached - Invoke-Phase contains phase-level failures -
        # but something outside any phase (or a bug in Invoke-Phase itself) still must
        # not prevent the result JSON and summary below from being written.
        Write-Log "Critical error outside any phase: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    } finally {
        # v2.22: the whole end-of-run sequence now lives in one function, shared with the
        # two abort paths that used to hand-copy parts of it. Ordering, the aborted-run
        # rule and the guarded Dispose are documented there.
        Complete-WinCleanRun -ResultPath $ResultJsonPath
    }
}

# Entry point
if ($MyInvocation.InvocationName -ne '.') {
    Start-WinClean
    # v2.17 (p.12 of the audit): the script used to always exit 0, even when the run
    # logged errors. A scheduled task or stand cannot tell "clean run" from "ran into
    # trouble" without parsing the log or the result JSON.
    if ($script:Stats.ErrorsCount -gt 0) {
        exit 1
    }
}

#endregion
