<#PSScriptInfo
.VERSION 2.17
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
    WinClean - Ultimate Windows 11 Maintenance Script v2.17
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
    Version: 2.17
    Requires: PowerShell 7.1+, Windows 11, Administrator rights
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
    Пропустить очистку системы
.PARAMETER SkipRestore
    Пропустить создание точки восстановления
.PARAMETER SkipDevCleanup
    Пропустить очистку кэшей разработчика (npm, pip, nuget)
.PARAMETER SkipDockerCleanup
    Пропустить очистку Docker/WSL
.PARAMETER SkipVSCleanup
    Пропустить очистку Visual Studio
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
$script:Stats = [hashtable]::Synchronized(@{
    TotalFreedBytes      = [long]0
    FreedByCategory      = @{}
    WindowsUpdatesCount  = 0
    AppUpdatesCount      = 0
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
    # v2.17 (p.11 of the audit): which top-level phases ran to completion vs threw.
    # Before this, one exception anywhere in the run silently skipped every phase
    # after it - Developer Cleanup, Docker/WSL, Visual Studio, Deep System Cleanup,
    # the disk space report, Telemetry - with only a single generic "Critical error"
    # in the log to show for it.
    PhasesCompleted      = @()
    PhasesFailed         = @()
})

# Progress activities seen so far, so all of them can be closed at the end (v2.16)
$script:ProgressActivities = @()

# Memoized Test-InternetConnection result for the whole run (v2.17, p.5 of the audit):
# the check costs up to ~15s offline and is called from two separate update phases
$script:InternetConnectionCache = $null

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
$script:Version = "2.17"

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

    # Write to log file. v2.17 (p.7 of the audit): Out-File used to open, seek to end,
    # write and close the file on every single call - Write-Log fires hundreds of times
    # per run. A StreamWriter kept open for the run avoids that, with AutoFlush so each
    # line still lands on disk immediately (same durability as before, just cheaper).
    # FileShare.Delete matters for tests: they Remove-Item the log path in AfterAll while
    # this writer may still be the last one that touched it.
    if (-not $NoLog) {
        try {
            if (-not $script:LogWriter -or $script:LogWriterPath -ne $script:LogPath) {
                if ($script:LogWriter) { $script:LogWriter.Dispose() }
                $fileStream = [System.IO.File]::Open(
                    $script:LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write,
                    ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                $script:LogWriter = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8)
                $script:LogWriter.AutoFlush = $true
                $script:LogWriterPath = $script:LogPath
            }
            $script:LogWriter.WriteLine($logMessage)
        } catch { }
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
        Результат кэшируется на весь прогон (v2.17): вызывается из двух фаз
        (Windows Update, Applications Update), до 15 сек на офлайн-машине каждый раз.
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

function Test-ScriptUpdate {
    <#
    .SYNOPSIS
        Проверяет наличие обновлений WinClean в PowerShell Gallery
    .DESCRIPTION
        Сравнивает текущую версию скрипта с последней версией в PowerShell Gallery.
        Проверяет, был ли скрипт установлен через PSGallery (для возможности автообновления).
    .OUTPUTS
        [hashtable] с информацией об обновлении или $null если обновление не требуется
    #>
    # Check if we can reach PSGallery
    if (-not (Test-PSGalleryConnection)) {
        return $null
    }

    try {
        $currentVersion = [Version]$script:Version

        # Query PSGallery for latest version
        $galleryScript = Find-Script -Name "WinClean" -Repository PSGallery -ErrorAction Stop
        $latestVersion = [Version]$galleryScript.Version

        if ($latestVersion -gt $currentVersion) {
            # Check if installed via PSGallery (for auto-update capability)
            $installedScript = Get-InstalledScript -Name "WinClean" -ErrorAction SilentlyContinue

            return @{
                CurrentVersion = $currentVersion.ToString()
                LatestVersion  = $latestVersion.ToString()
                IsInstalled    = $null -ne $installedScript
                ReleaseNotes   = $galleryScript.ReleaseNotes
            }
        }
    } catch {
        # Silently fail - update check is not critical
        Write-Log "Update check failed: $_" -Level WARNING
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

    Write-Log "Update available: v$($UpdateInfo.CurrentVersion) -> v$($UpdateInfo.LatestVersion)" -Level INFO

    # In ReportOnly mode, just inform and continue
    if ($ReportOnly) {
        Write-Host "  ReportOnly mode - skipping update" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Check if interactive console is available
    if (-not (Test-InteractiveConsole)) {
        Write-Host "  Non-interactive mode - skipping update prompt" -ForegroundColor DarkGray
        Write-Host "  To update manually: Update-Script -Name WinClean" -ForegroundColor Gray
        Write-Host ""
        return
    }

    if ($UpdateInfo.IsInstalled) {
        # Installed via PSGallery - can auto-update
        Write-Host "  Update now? (" -NoNewline -ForegroundColor Gray
        Write-Host "Y" -NoNewline -ForegroundColor Green
        Write-Host "/n): " -NoNewline -ForegroundColor Gray

        $response = Read-Host
        if ($response -eq '' -or $response -imatch '^[YyДд]') {
            Write-Host ""
            Write-Host "  Updating WinClean..." -ForegroundColor Cyan

            try {
                Update-Script -Name WinClean -Force -ErrorAction Stop
                Write-Log "Update successful" -Level SUCCESS
                Write-Host ""
                Write-Host "  ✓ Update complete!" -ForegroundColor Green
                Write-Host "  Please run WinClean again to use the new version." -ForegroundColor Gray
                Write-Host ""
                Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                exit 0
            } catch {
                Write-Log "Update failed: $_" -Level ERROR
                Write-Host "  ✗ Update failed: $_" -ForegroundColor Red
                Write-Host "  Continuing with current version..." -ForegroundColor Yellow
                Write-Host ""
            }
        } else {
            Write-Log "Update skipped by user" -Level INFO
            Write-Host "  Update skipped. Continuing with current version..." -ForegroundColor DarkGray
            Write-Host ""
        }
    } else {
        # Not installed via PSGallery - show manual instructions
        Write-Host "  WinClean was not installed via PowerShell Gallery." -ForegroundColor Yellow
        Write-Host "  To enable auto-updates, install with:" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    Install-Script -Name WinClean -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host ""
        Write-Host "  Press any key to continue with current version..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host ""
    }
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

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return 0
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
    .EXAMPLE
        ConvertFrom-HumanReadableSize "2.5 GB"  # Returns 2684354560
        ConvertFrom-HumanReadableSize "512MB"   # Returns 536870912
    #>
    param([string]$SizeString)

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

    # Decimal-separator ambiguity ("1.234,5" EU vs "1,234.5" US vs a lone "," or "."):
    # whichever mark appears LAST is the decimal point; anything earlier was a
    # thousands grouping and is dropped.
    $lastComma = $numberPart.LastIndexOf(',')
    $lastDot = $numberPart.LastIndexOf('.')
    if ($lastComma -gt $lastDot) {
        $numberPart = $numberPart.Replace('.', '').Replace(',', '.')
    } elseif ($lastDot -gt $lastComma) {
        $numberPart = $numberPart.Replace(',', '')
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

function Test-PathProtected {
    <#
    .SYNOPSIS
        Checks whether a path is a protected root itself (v2.17: normalized)
    .DESCRIPTION
        Guards the roots listed in $script:ProtectedPaths against being emptied.
        Paths are resolved with GetFullPath first, otherwise the check is trivially
        bypassed by an 8.3 name (C:\PROGRA~1), a "\\?\" prefix, a relative path or
        a "C:\Windows\..\Windows" round trip.

        Only the roots themselves are protected, not everything below them: the script
        legitimately cleans %SystemRoot%\Temp and other subfolders. Callers that must
        never touch a subtree pass explicit paths instead.
    #>
    param([string]$Path)

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

        if ($item.PSIsContainer) {
            if ($cutoff) {
                # A folder's own LastWriteTime only moves when its direct children
                # change, so a fresh file nested deeper would otherwise be deleted
                # along with its old-looking parent - the age check must be recursive.
                # Fail closed: if the subtree cannot be fully read (ACL, path length,
                # locked folder), staleness cannot be proven, so the directory is kept.
                $walkErrors = $null
                $children = Get-ChildItem -LiteralPath $item.FullName -Recurse -Force `
                                -ErrorAction SilentlyContinue -ErrorVariable walkErrors
                if ($walkErrors) { continue }
                if ($children | Where-Object { $_.LastWriteTime -ge $cutoff } | Select-Object -First 1) { continue }
                # Same walk also gives the size - no second pass needed for it
                $size = ($children | Where-Object { -not $_.PSIsContainer } |
                         Measure-Object -Property Length -Sum).Sum
            } else {
                $size = Get-FolderSize -Path $item.FullName
            }
        } else {
            if ($cutoff -and $item.LastWriteTime -ge $cutoff) { continue }
            $size = $item.Length
        }

        $candidates += [pscustomobject]@{ Item = $item; Size = [long]($size ?? 0) }
    }

    $totalSize = [long](($candidates | Measure-Object -Property Size -Sum).Sum ?? 0)

    if ($ReportOnly) {
        if ($totalSize -gt 0 -and $Description) {
            Write-Log "Would clean: $Description - $(Format-FileSize $totalSize)" -Level DETAIL
        }
        return
    }

    if ($candidates.Count -eq 0) {
        return
    }

    try {
        $freed = 0
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
                # Fully gone - the size measured before deletion is exactly what was freed
                $freed += $c.Size
            } elseif ($item.PSIsContainer) {
                # Partially deleted (some locked file inside) - re-measure only this one
                # subtree, not the whole of $Path
                $remaining = Get-FolderSize -Path $item.FullName
                $freed += [math]::Max(0, $c.Size - $remaining)
            }
            # A file that still exists (locked) contributes 0 - correctly nothing freed
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
        $outFile = [System.IO.Path]::GetTempFileName()
        $errFile = [System.IO.Path]::GetTempFileName()
        try {
            $proc = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-Command', $scriptBlock) `
                -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

            $timeoutMs = 120000  # 2 minutes - a restore point should never legitimately take this long
            if (-not $proc.WaitForExit($timeoutMs)) {
                $proc.Kill($true)
                throw "restore point creation timed out after $($timeoutMs / 1000) seconds"
            }

            $result = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)
        } finally {
            Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
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
        Write-Log "No internet connection - skipping Windows Update" -Level ERROR
        $script:Stats.ErrorsCount++
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
        return
    }

    if (-not (Test-InternetConnection)) {
        Write-Log "No internet connection - skipping app updates" -Level ERROR
        $script:Stats.ErrorsCount++
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
        Write-Log "Winget not found - install App Installer from Microsoft Store" -Level ERROR
        $script:Stats.ErrorsCount++
        return
    }

    try {
        # Update sources only if not in ReportOnly mode (source update modifies state)
        if (-not $ReportOnly) {
            Write-Log "Updating winget sources..." -Level INFO
            # Run with timeout to prevent hanging
            $job = Start-Job -ScriptBlock { param($path) & $path source update 2>&1 } -ArgumentList $wingetPath
            $completed = $job | Wait-Job -Timeout 120  # 2 minutes timeout
            if (-not $completed) {
                $job | Stop-Job
                Write-Log "Winget source update timed out - package list may be stale" -Level WARNING
                $script:Stats.WarningsCount++
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
            $script:Stats.AppUpdatesCount = $updateCount
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
                # Nothing to upgrade is a normal outcome, not a warning. AppUpdatesCount
                # stays at zero: nothing was installed, and counting it would show up as
                # "Updates installed" in the summary.
                Write-Log "Application updates: $meaning" -Level DETAIL
            } else {
                if ($code -eq -1978334967) {
                    # Installation finished but needs a reboot to take effect
                    $script:Stats.AppUpdatesCount = $updateCount
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
        Cleans browser caches (Edge, Chrome, Firefox, Yandex)
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

        # Measure size before cleanup
        $sizeBefore = ($allPaths | ForEach-Object { Get-FolderSize -Path $_.Path } | Measure-Object -Sum).Sum

        if ($ReportOnly) {
            # In ReportOnly mode, just show what would be cleaned
            Write-Log "Would clean browser caches ($browserNames) - $(Format-FileSize $sizeBefore)" -Level DETAIL
        } else {
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

            # Measure size after cleanup to get actual freed space
            $sizeAfter = ($allPaths | ForEach-Object { Get-FolderSize -Path $_.Path } | Measure-Object -Sum).Sum
            $sizeAfter = [long]($sizeAfter ?? 0)  # Ensure non-null value
            # Protect against negative values (can happen if browser recreates files during cleanup)
            $freedSpace = [math]::Max(0, $sizeBefore - $sizeAfter)

            # Update statistics with actual freed space (not estimated)
            if ($freedSpace -gt 0) {
                $script:Stats.TotalFreedBytes += $freedSpace
                if (-not $script:Stats.FreedByCategory.ContainsKey("Browser")) {
                    $script:Stats.FreedByCategory["Browser"] = 0
                }
                $script:Stats.FreedByCategory["Browser"] += $freedSpace
                Write-Log "Browser caches cleaned ($browserNames) - $(Format-FileSize $freedSpace)" -Level SUCCESS
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

    # Stop services with try/finally to ensure they restart
    Write-Log "Stopping Windows Update services..." -Level DETAIL -NoLog
    $servicesStopped = $false
    try {
        Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
        $servicesStopped = $true

        # v2.16: Stop-Service returns before the service has actually reached Stopped,
        # and its failure was swallowed by -ErrorAction SilentlyContinue. Cleaning while
        # the service still holds the files silently leaves the cache in place.
        $stillRunning = @()
        foreach ($svcName in @('wuauserv', 'bits')) {
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
        # Always restart services
        if ($servicesStopped) {
            Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
        }
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
                Write-Log "Delivery Optimization: nothing freed, $(Format-FileSize $doSizeBefore) still present" -Level WARNING
                $script:Stats.WarningsCount++
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
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object {
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

        if ($failedCount -gt 0) {
            Write-Log "Event logs cleared: $clearedCount, failed: $failedCount" -Level WARNING
            $script:Stats.WarningsCount++
        } else {
            Write-Log "Event logs cleared ($clearedCount logs)" -Level SUCCESS
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

    # Clear Run dialog history (RunMRU)
    $runMruKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"
    if (Test-Path $runMruKey) {
        try {
            # Get current values before clearing
            $mruValues = Get-ItemProperty -Path $runMruKey -ErrorAction SilentlyContinue
            $valueCount = ($mruValues.PSObject.Properties | Where-Object { $_.Name -match '^[a-z]$' }).Count

            # Remove the key and recreate it empty
            Remove-Item -Path $runMruKey -Force -ErrorAction SilentlyContinue
            New-Item -Path $runMruKey -Force -ErrorAction SilentlyContinue | Out-Null

            if ($valueCount -gt 0) {
                $clearedItems += "Run history ($valueCount entries)"
            }
        } catch {
            Write-Log "Could not clear Run history: $_" -Level WARNING
        }
    }

    # Clear TypedPaths (Explorer address bar history)
    $typedPathsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
    if (Test-Path $typedPathsKey) {
        try {
            Remove-Item -Path $typedPathsKey -Force -ErrorAction SilentlyContinue
            New-Item -Path $typedPathsKey -Force -ErrorAction SilentlyContinue | Out-Null
            $clearedItems += "Explorer typed paths"
        } catch { }
    }

    # Clear WordWheelQuery (Explorer search history)
    $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"
    if (Test-Path $searchKey) {
        try {
            Remove-Item -Path $searchKey -Force -ErrorAction SilentlyContinue
            New-Item -Path $searchKey -Force -ErrorAction SilentlyContinue | Out-Null
            $clearedItems += "Explorer search history"
        } catch { }
    }

    # Clear Recent documents folder
    $recentFolder = [Environment]::GetFolderPath('Recent')
    if (Test-Path $recentFolder) {
        try {
            $recentCount = (Get-ChildItem -Path $recentFolder -Force -ErrorAction SilentlyContinue).Count
            Get-ChildItem -Path $recentFolder -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($recentCount -gt 0) {
                $clearedItems += "Recent documents ($recentCount items)"
            }
        } catch { }
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
    if ($SkipDevCleanup) {
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
                    $sizeBefore = Get-FolderSize $npmCache
                    & npm cache clean --force 2>&1 | Out-Null
                    $sizeAfter = Get-FolderSize $npmCache
                    $freed = $sizeBefore - $sizeAfter

                    if ($freed -gt 0) {
                        $script:Stats.TotalFreedBytes += $freed
                        if (-not $script:Stats.FreedByCategory.ContainsKey("Developer")) {
                            $script:Stats.FreedByCategory["Developer"] = 0
                        }
                        $script:Stats.FreedByCategory["Developer"] += $freed
                        Write-Log "npm cache cleaned - $(Format-FileSize $freed)" -Level SUCCESS
                    } else {
                        Write-Log "npm cache cleaned (via npm)" -Level SUCCESS
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

function Clear-DockerWSL {
    <#
    .SYNOPSIS
        Cleans Docker images, containers, and WSL2 disk
    #>
    if ($SkipDockerCleanup) {
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
                            $diskpartScript | diskpart | Out-Null

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
                        } catch {
                            Write-Log "Could not compact $($vhdxFile.Name): $_" -Level WARNING
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
    if ($SkipVSCleanup) {
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
          2. a newer package with the same OriginalName exists.
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
            if ($pkg.Oem -eq $newest.Oem -or $pkg.InUse) { continue }
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

    # Measured as a fallback: per-package sizes come from matching INF hashes, and if
    # that matching fails the packages still get deleted while the statistics read 0 B
    $repoPath = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    $repoBefore = Get-FolderSize -Path $repoPath

    $freed = 0
    $removed = 0
    $failed = 0
    foreach ($pkg in $candidates) {
        # No /force here: it deletes packages even when a device is using them, which is
        # exactly how driver cleaners break systems. Exit code is the verdict - the text
        # output is localized.
        $null = & pnputil.exe /delete-driver $pkg.Oem 2>&1
        if ($LASTEXITCODE -eq 0) {
            $freed += $pkg.Bytes
            $removed++
        } else {
            $failed++
            Write-Log "Skipped $($pkg.Oem) ($($pkg.Inf)): pnputil exit $LASTEXITCODE" -Level DETAIL
        }
    }

    if ($removed -gt 0) {
        if ($freed -eq 0) {
            # Packages went away but no size could be attributed to them - fall back to
            # the difference in the repository itself rather than reporting a false zero
            $repoDelta = [math]::Max(0, $repoBefore - (Get-FolderSize -Path $repoPath))
            Write-Log "Removed $removed package(s); per-package size unavailable, driver store shrank by $(Format-FileSize $repoDelta)" -Level WARNING
            $script:Stats.WarningsCount++
            $freed = $repoDelta
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

function Invoke-StorageSense {
    <#
    .SYNOPSIS
        Runs Storage Sense cleanup
    #>
    Write-Log "Storage Sense" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would run: Storage Sense" -Level DETAIL
        return
    }

    # Try Storage Sense first (Windows 11)
    # Use Get-ScheduledTask for language-independent status checking
    $ssTaskPath = "\Microsoft\Windows\DiskCleanup\"
    $ssTaskName = "StorageSense"
    $task = Get-ScheduledTask -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue

    # A disabled task cannot be started - fall back to cleanmgr instead of
    # waiting the full timeout for a task that never runs (v2.14)
    if ($task -and $task.State -ne 'Disabled') {
        Write-Log "Running Storage Sense..." -Level INFO

        # Record time before running to compare with LastRunTime
        $startTime = Get-Date
        Start-ScheduledTask -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue

        # Wait for task to complete with timeout
        $timeout = 120  # 2 minutes max
        $elapsed = 0
        $checkInterval = 5
        $wasRunning = $false

        while ($elapsed -lt $timeout) {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval

            # Get current task state (language-independent: Ready, Running, Disabled)
            $task = Get-ScheduledTask -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue
            if ($task) {
                $state = $task.State

                if ($state -eq 'Running') {
                    $wasRunning = $true
                } elseif ($wasRunning -and $state -eq 'Ready') {
                    # Task was running and now finished
                    Write-Log "Storage Sense completed" -Level SUCCESS
                    break
                } elseif (-not $wasRunning -and $elapsed -ge 10) {
                    # Task didn't start running within 10 seconds - check LastRunTime
                    $taskInfo = Get-ScheduledTaskInfo -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue
                    if ($taskInfo -and $taskInfo.LastRunTime -gt $startTime) {
                        Write-Log "Storage Sense completed" -Level SUCCESS
                        break
                    }
                }
            }
        }

        if ($elapsed -ge $timeout) {
            Write-Log "Storage Sense timed out after $timeout seconds" -Level WARNING
            # Force stop the task if still running
            $task = Get-ScheduledTask -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue
            if ($task -and $task.State -eq 'Running') {
                Stop-ScheduledTask -TaskPath $ssTaskPath -TaskName $ssTaskName -ErrorAction SilentlyContinue
                Write-Log "Storage Sense task stopped" -Level INFO
            }
            $script:Stats.WarningsCount++
        }
    } else {
        # Fallback to cleanmgr
        if ($task) {
            Write-Log "Storage Sense task is disabled, using Disk Cleanup..." -Level INFO
        } else {
            Write-Log "Storage Sense task not found, using Disk Cleanup..." -Level INFO
        }

        # Configure cleanup categories
        $sageset = 9999
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

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
                return
            }

            # Run cleanmgr with progress feedback and reasonable timeout
            $cleanmgr = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" `
                -WindowStyle Hidden -PassThru

            # v2.16: raised from 420s. cleanmgr regularly needs longer on a workstation
            # with a large component store, and killing it produced a warning on every
            # single run while cleanmgr kept working in the background anyway.
            $maxWait = 900  # 15 minutes
            $elapsed = 0
            $checkInterval = 10

            while (-not $cleanmgr.HasExited -and $elapsed -lt $maxWait) {
                Start-Sleep -Seconds $checkInterval
                $elapsed += $checkInterval

                # Log progress every minute
                if ($elapsed % 60 -eq 0) {
                    Write-Log "Disk Cleanup still running... ($elapsed seconds)" -Level INFO
                }
            }

            if (-not $cleanmgr.HasExited) {
                # Let it finish in the background instead of killing it. Not a warning
                # either: cleanmgr simply takes longer than we are willing to wait, and
                # killing it mid-delete was both pointless and misreported as "continuing" (v2.16)
                Write-Log "Disk Cleanup exceeded $maxWait seconds - leaving it to finish in the background" -Level INFO
            } elseif ($cleanmgr.ExitCode -ne 0) {
                # v2.16: the exit code used to be ignored entirely, so a crash one second
                # in was still logged as a success
                Write-Log "Disk Cleanup exited with code $($cleanmgr.ExitCode) - results unverified" -Level WARNING
                $script:Stats.WarningsCount++
            } else {
                Write-Log "Disk Cleanup completed ($armed categories)" -Level SUCCESS
            }
        } finally {
            # Remove StateFlags to avoid leaving traces in the registry.
            # v2.16: sweep every handler, not just the ones from $categories - flags left
            # by an interrupted run or by an older version of this list stayed forever
            # (four such leftovers were found on a live machine).
            Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ItemProperty -Path $_.PSPath -Name "StateFlags$sageset" -Force -ErrorAction SilentlyContinue
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
    $labelWidth = 18  # Width for label column (e.g., "Updates installed:")

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

    # Updates
    $totalUpdates = $script:Stats.WindowsUpdatesCount + $script:Stats.AppUpdatesCount
    if ($totalUpdates -gt 0) {
        $updatesStr = "Windows: $($script:Stats.WindowsUpdatesCount), Apps: $($script:Stats.AppUpdatesCount)"
        # ASCII "^" instead of "↑" (v2.17, p.20 of the audit): same ambiguous-width
        # box-alignment issue as "⚠" below, just not caught the first time around
        Write-StatLine -Icon "^" -Label "Updates installed:" -Value $updatesStr -IconColor "Green" -ValueColor "Green"
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
            # Right-align category name so colon aligns with "Updates installed:"
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
                DisableTelemetry  = [bool]$DisableTelemetry
            }
            TotalFreedBytes     = [long]$script:Stats.TotalFreedBytes
            FreedByCategory     = @{} + $script:Stats.FreedByCategory
            WindowsUpdatesCount = $script:Stats.WindowsUpdatesCount
            AppUpdatesCount     = $script:Stats.AppUpdatesCount
            WarningsCount       = $script:Stats.WarningsCount
            ErrorsCount         = $script:Stats.ErrorsCount
            RebootRequired      = [bool]$script:Stats.RebootRequired
            # 'enabled' means cleanup figures are understated (Defender blocked some
            # deletions without reporting an error); 'unknown' means the check itself
            # failed, so the figures are unverified rather than confirmed good
            ControlledFolderAccess = [string]$script:Stats.ControlledFolderAccess
            # null for a normal run; a reason string when the run stopped early (v2.17)
            Aborted             = $script:Stats.Aborted
            # v2.17 (p.11): which top-level phases ran vs threw - lets a stand tell
            # "everything ran" from "phase N threw and phases after it are just missing"
            PhasesCompleted     = @($script:Stats.PhasesCompleted)
            PhasesFailed        = @($script:Stats.PhasesFailed)
            LogPath             = $script:LogPath
        }

        $resultDir = Split-Path -Path $Path -Parent
        if ($resultDir -and -not (Test-Path -LiteralPath $resultDir)) {
            New-Item -ItemType Directory -Path $resultDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $result | ConvertTo-Json -Depth 4 | Out-File -FilePath $Path -Encoding utf8
        Write-Log "Result JSON written: $Path" -Level INFO
    } catch {
        # Must be loud: an automated stand reads this file, and a stale copy from the
        # previous run would be reported as a successful fresh run
        Write-Log "Failed to write result JSON: $_" -Level WARNING
        $script:Stats.WarningsCount++
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
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

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

    # Initialize log
    "WinClean v$($script:Version) - Started at $(Get-Date)" | Out-File -FilePath $script:LogPath -Encoding utf8
    "=" * 70 | Out-File -FilePath $script:LogPath -Append -Encoding utf8

    # Enable TLS 1.2 for all HTTPS connections (required by PowerShell Gallery, NuGet, etc.)
    # This must be set before any network operations
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Calculate TotalSteps dynamically based on skip flags
    $script:Stats.TotalSteps = 0
    if (-not $SkipUpdates) { $script:Stats.TotalSteps += 2 }      # Windows Update + App Updates
    if (-not $SkipCleanup) { $script:Stats.TotalSteps += 2 }      # System Cleanup + Deep Cleanup
    if (-not $SkipDevCleanup) { $script:Stats.TotalSteps += 1 }   # Developer Caches
    if (-not $SkipDockerCleanup) { $script:Stats.TotalSteps += 1 } # Docker/WSL
    if (-not $SkipVSCleanup) { $script:Stats.TotalSteps += 1 }    # Visual Studio
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
                $script:Stats.Aborted = 'PendingRebootDeclined'
                Write-ResultJson -Path $ResultJsonPath
                return
            }
        } else {
            Write-Host "  Non-interactive mode - continuing despite pending reboot." -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Check for script updates. v2.17: gated by -SkipUpdates - the flag promises no
    # update activity, and this path costs a PSGallery round trip on every run.
    if (-not $SkipUpdates) {
        $updateInfo = Test-ScriptUpdate
        if ($updateInfo) {
            Invoke-ScriptUpdate -UpdateInfo $updateInfo
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
        Invoke-Phase -Name 'Preparation' -Action {
            $null = New-SystemRestorePoint -Description "WinClean $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        }

        Invoke-Phase -Name 'Updates' -Action {
            if (-not $SkipUpdates) {
                Update-WindowsSystem
                Update-Applications
            }
        }

        Invoke-Phase -Name 'SystemCleanup' -Action {
            if (-not $SkipCleanup) {
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
        }

        Invoke-Phase -Name 'DeveloperCleanup' -Action { Clear-DeveloperCaches }

        Invoke-Phase -Name 'DockerWSLCleanup' -Action { Clear-DockerWSL }

        Invoke-Phase -Name 'VisualStudioCleanup' -Action { Clear-VisualStudio }

        Invoke-Phase -Name 'DeepSystemCleanup' -Action {
            if (-not $SkipCleanup) {
                Write-Log "DEEP SYSTEM CLEANUP" -Level TITLE
                Update-Progress -Activity "Deep Cleanup" -Status "Running system cleanup..."

                # Driver store first (v2.17): removing packages leaves referenced
                # components in WinSxS, and running DISM afterwards reclaims them in
                # the same pass instead of a week later.
                Clear-DriverStore
                Clear-KernelDumps
                # Neither of these reports what it freed, so measure the drive around them
                Measure-FreeSpaceGain -Category 'ComponentStore' -Operation { Invoke-DISMCleanup }
                Measure-FreeSpaceGain -Category 'DiskCleanup' -Operation { Invoke-StorageSense }
                Clear-WindowsOld
            }
        }

        Invoke-Phase -Name 'DiskSpaceReport' -Action {
            # What is taking up space that cleanup deliberately leaves alone (v2.16).
            # Gated by -SkipCleanup (v2.17): it walks Windows\Installer and the search
            # index, which is expensive and pointless for a user who asked for no cleanup.
            if (-not $SkipCleanup) {
                Show-DiskSpaceReport
            }
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
        # JSON goes first: Show-FinalStatistics may block on a keypress in
        # interactive mode, and automated runs must get the result regardless
        Write-ResultJson -Path $ResultJsonPath
        Show-FinalStatistics
        # Release the log file handle (v2.17, p.7): a stand or the user may want to
        # move/zip the log right after the run finishes.
        if ($script:LogWriter) {
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
            $script:LogWriterPath = $null
        }
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
