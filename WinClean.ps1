<#
.SYNOPSIS
    WinClean - Ultimate Windows 11 Maintenance Script v2.0
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
    Version: 2.0
    Requires: PowerShell 7.1+, Windows 11, Administrator rights
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
#>

#Requires -Version 7.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$SkipUpdates,
    [switch]$SkipCleanup,
    [switch]$SkipRestore,
    [switch]$SkipDevCleanup,
    [switch]$SkipDockerCleanup,
    [switch]$SkipVSCleanup,
    [switch]$DisableTelemetry,
    [switch]$ReportOnly,
    [string]$LogPath
)

#region ═══════════════════════════════════════════════════════════════════════
#                              INITIALIZATION
#region ═══════════════════════════════════════════════════════════════════════

# Ensure UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Thread-safe statistics using synchronized hashtable
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
})

# Initialize log path (script scope for access in functions)
if (-not $LogPath) {
    $script:LogPath = Join-Path $env:TEMP "WinClean_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"
} else {
    $script:LogPath = $LogPath
}

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
#region ═══════════════════════════════════════════════════════════════════════

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

    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to log file
    if (-not $NoLog) {
        try {
            $logMessage | Out-File -FilePath $script:LogPath -Append -Encoding utf8 -ErrorAction SilentlyContinue
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
            Write-Host ""
            Write-Host ("═" * 70) -ForegroundColor $tagColors.Tag
            Write-Host "  $Message" -ForegroundColor $tagColors.Message
            Write-Host ("═" * 70) -ForegroundColor $tagColors.Tag
            Write-Host ""
        }
        'SECTION' {
            Write-Host ""
            Write-Host "┌─ " -NoNewline -ForegroundColor DarkGray
            Write-Host $Message -ForegroundColor $tagColors.Message
            Write-Host "└" -NoNewline -ForegroundColor DarkGray
            Write-Host ("─" * 65) -ForegroundColor DarkGray
        }
        'DETAIL' {
            Write-Host "   │ " -NoNewline -ForegroundColor DarkGray
            Write-Host $Message -ForegroundColor $tagColors.Message -NoNewline:$NoNewLine
            if (-not $NoNewLine) { Write-Host "" }
        }
        default {
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

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $percent
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              HELPER FUNCTIONS
#region ═══════════════════════════════════════════════════════════════════════

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Проверяет доступ к интернету через TCP-соединения с таймаутом
    .DESCRIPTION
        Использует TcpClient с явным таймаутом (3 сек) вместо Test-NetConnection,
        который может зависать на 20-30 секунд при VPN или нестабильном соединении
    #>
    $targets = @(
        @{ Host = 'www.microsoft.com'; Port = 443 }
        @{ Host = 'api.github.com'; Port = 443 }
        @{ Host = 'winget.azureedge.net'; Port = 443 }
    )

    $timeoutMs = 3000  # 3 секунды таймаут на каждое соединение

    foreach ($target in $targets) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($target.Host, $target.Port, $null, $null)
            $success = $connect.AsyncWaitHandle.WaitOne($timeoutMs, $false)

            if ($success -and $tcpClient.Connected) {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            }
            $tcpClient.Close()
        } catch { }
    }

    # Запасной вариант: ICMP (может быть заблокирован в некоторых сетях)
    $dnsServers = @('8.8.8.8', '1.1.1.1', '208.67.222.222')

    foreach ($dns in $dnsServers) {
        if (Test-Connection -ComputerName $dns -Count 1 -Quiet -TimeoutSeconds 2 -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
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
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return 0
    }

    try {
        $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]($size ?? 0)
    } catch {
        return 0
    }
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formats bytes to human-readable size
    #>
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Test-PathProtected {
    <#
    .SYNOPSIS
        Checks if path is in protected list
    #>
    param([string]$Path)

    $normalizedPath = $Path.TrimEnd('\', '/')

    foreach ($protected in $script:ProtectedPaths) {
        $normalizedProtected = $protected.TrimEnd('\', '/')
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
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Category,

        [string]$Description,

        [switch]$RemoveFolder
    )

    # Safety check
    if (Test-PathProtected -Path $Path) {
        Write-Log "Protected path skipped: $Path" -Level WARNING
        return
    }

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return
    }

    if ($ReportOnly) {
        $size = Get-FolderSize -Path $Path
        if ($size -gt 0 -and $Description) {
            Write-Log "Would clean: $Description - $(Format-FileSize $size)" -Level DETAIL
        }
        return
    }

    $sizeBefore = Get-FolderSize -Path $Path

    try {
        if ($RemoveFolder) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    # Handle read-only files
                    if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    }
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        }

        $sizeAfter = Get-FolderSize -Path $Path
        $freed = $sizeBefore - $sizeAfter

        if ($freed -gt 0) {
            # Thread-safe update
            [System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, $freed) | Out-Null

            # Update category (not thread-safe, but acceptable for reporting)
            if (-not $script:Stats.FreedByCategory.ContainsKey($Category)) {
                $script:Stats.FreedByCategory[$Category] = 0
            }
            $script:Stats.FreedByCategory[$Category] += $freed

            if ($Description) {
                Write-Log "$Description - $(Format-FileSize $freed)" -Level SUCCESS
            }
        }
    } catch {
        Write-Log "Error cleaning $Path`: $_" -Level WARNING
        $script:Stats.WarningsCount++
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
        $scriptBlock = @"
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "$Description" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                Write-Output "SUCCESS"
            } catch {
                Write-Output "ERROR: `$_"
            }
"@

        $result = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -NoProfile -NoLogo -ExecutionPolicy Bypass -Command $scriptBlock 2>&1

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
#region ═══════════════════════════════════════════════════════════════════════

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
            Write-Log "Installing PSWindowsUpdate module..." -Level INFO

            # Ensure NuGet provider
            $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nuget -or $nuget.Version -lt [version]"2.8.5.201") {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
            }

            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop
            Write-Log "PSWindowsUpdate installed" -Level SUCCESS
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop
        $moduleVersion = (Get-Module PSWindowsUpdate).Version
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
        $systemUpdates = @(Get-WindowsUpdate -MicrosoftUpdate -NotCategory "Drivers" -ErrorAction SilentlyContinue)

        Write-Log "Driver Updates" -Level SECTION
        $driverUpdates = @(Get-WindowsUpdate -MicrosoftUpdate -Category "Drivers" -ErrorAction SilentlyContinue)

        $totalUpdates = $systemUpdates.Count + $driverUpdates.Count

        if ($totalUpdates -eq 0) {
            Write-Log "Windows is up to date" -Level SUCCESS
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

        # Check module version for parameter compatibility
        if ($moduleVersion -ge [version]"2.3.0") {
            $installParams.Remove('IgnoreReboot')
            $installParams['AutoReboot'] = $false
        }

        $results = Install-WindowsUpdate @installParams

        # Count installed updates
        $installed = @($results | Where-Object { $_.Result -in @('Installed', 'Downloaded') }).Count
        $failed = @($results | Where-Object { $_.Result -eq 'Failed' }).Count

        $script:Stats.WindowsUpdatesCount = $installed

        if ($failed -gt 0) {
            Write-Log "Installed: $installed, Failed: $failed" -Level WARNING
            $script:Stats.WarningsCount += $failed
        } else {
            Write-Log "All $installed updates installed successfully" -Level SUCCESS
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
            & $wingetPath source update 2>&1 | Out-Null
        }

        # Get available updates (use --include-unknown to match actual upgrade behavior)
        Write-Log "Checking for app updates..." -Level INFO

        $tempFile = [System.IO.Path]::GetTempFileName()
        $tempErrorFile = [System.IO.Path]::GetTempFileName()
        $process = Start-Process -FilePath $wingetPath -ArgumentList "upgrade", "--include-unknown" `
            -NoNewWindow -RedirectStandardOutput $tempFile -RedirectStandardError $tempErrorFile -PassThru -Wait

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
        # Uses table separator "---" as marker, then counts package lines
        $updateCount = 0
        $lines = $output -split "`n"
        $foundSeparator = $false

        foreach ($line in $lines) {
            # Look for table separator line (works in any language)
            if ($line -match "^-{10,}") {
                $foundSeparator = $true
                continue
            }

            # Only count lines after separator that look like package entries
            if ($foundSeparator) {
                # Match lines with package data: contains "winget" or "msstore" as source
                if ($line -match "\s+(winget|msstore)\s*$") {
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
            -NoNewWindow -PassThru -Wait

        $script:Stats.AppUpdatesCount = $updateCount

        if ($upgradeProcess.ExitCode -eq 0) {
            Write-Log "Application updates completed successfully" -Level SUCCESS
        } else {
            Write-Log "Application updates completed with code: $($upgradeProcess.ExitCode)" -Level WARNING
            $script:Stats.WarningsCount++
        }

    } catch {
        Write-Log "Application update error: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              CLEANUP FUNCTIONS
#region ═══════════════════════════════════════════════════════════════════════

function Clear-TempFiles {
    <#
    .SYNOPSIS
        Cleans temporary files and system caches
    #>
    Write-Log "Temporary Files" -Level SECTION

    $tempPaths = @(
        @{ Path = $env:TEMP; Desc = "User Temp" }
        @{ Path = "$env:SystemRoot\Temp"; Desc = "Windows Temp" }
        @{ Path = "$env:LOCALAPPDATA\Temp"; Desc = "Local Temp" }
    )

    foreach ($item in $tempPaths) {
        Remove-FolderContent -Path $item.Path -Category "Temp" -Description $item.Desc
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
        "Firefox" = @()  # Handled separately due to profile structure
        "Yandex" = @(
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Code Cache"
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\GPUCache"
        )
        "Opera" = @(
            "$env:APPDATA\Opera Software\Opera Stable\Cache"
            "$env:APPDATA\Opera Software\Opera Stable\Code Cache"
            "$env:APPDATA\Opera Software\Opera Stable\GPUCache"
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

    # Also check for additional Chrome/Edge profiles
    foreach ($browser in @("Chrome", "Edge")) {
        $basePath = if ($browser -eq "Chrome") {
            "$env:LOCALAPPDATA\Google\Chrome\User Data"
        } else {
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        }

        if (Test-Path $basePath) {
            Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "Profile *" } | ForEach-Object {
                    $profileCache = Join-Path $_.FullName "Cache"
                    if (Test-Path $profileCache) {
                        $allPaths += @{ Browser = "$browser Profile"; Path = $profileCache }
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
            $freedSpace = $sizeBefore - $sizeAfter

            # Update statistics with actual freed space (not estimated)
            if ($freedSpace -gt 0) {
                [System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, $freedSpace) | Out-Null
                if (-not $script:Stats.FreedByCategory.ContainsKey("Browser")) {
                    $script:Stats.FreedByCategory["Browser"] = 0
                }
                $script:Stats.FreedByCategory["Browser"] += $freedSpace
            }

            Write-Log "Browser caches cleaned ($browserNames) - $(Format-FileSize $freedSpace)" -Level SUCCESS
        }
    }

    # Handle Firefox profiles separately
    $firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxProfiles) {
        Get-ChildItem -Path $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-FolderContent -Path "$($_.FullName)\cache2" -Category "Browser" -Description "Firefox cache"
            Remove-FolderContent -Path "$($_.FullName)\startupCache" -Category "Browser"
        }
    }
}

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Cleans Windows Update download cache
    #>
    Write-Log "Windows Update Cache" -Level SECTION

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

        # Clean
        Remove-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\Download" -Category "WinUpdate" -Description "Windows Update cache"
    } finally {
        # Always restart services
        if ($servicesStopped) {
            Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
        }
    }
}

function Clear-WinCleanRecycleBin {
    <#
    .SYNOPSIS
        Empties the Recycle Bin
    #>
    Write-Log "Recycle Bin" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would clean: Recycle Bin" -Level DETAIL
        return
    }

    try {
        # Use full cmdlet path to avoid recursion (our function has same name as cmdlet)
        Microsoft.PowerShell.Management\Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log "Recycle Bin emptied" -Level SUCCESS
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

            Write-Log "Recycle Bin emptied ($count items)" -Level SUCCESS
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
        @{ Path = "$env:SystemDrive\ProgramData\Microsoft\Windows\DeliveryOptimization"; Desc = "Delivery Optimization" }
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

                    if ($fileSize -gt 0) {
                        [System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, $fileSize) | Out-Null
                        if (-not $script:Stats.FreedByCategory.ContainsKey("System")) {
                            $script:Stats.FreedByCategory["System"] = 0
                        }
                        $script:Stats.FreedByCategory["System"] += $fileSize
                    }

                    Write-Log "$($item.Desc) cleaned" -Level DETAIL
                }
            }
        } else {
            Remove-FolderContent -Path $item.Path -Category "System" -Description $item.Desc
        }
    }
}

function Clear-EventLogs {
    <#
    .SYNOPSIS
        Clears Windows Event Logs (excluding critical ones)
    #>
    Write-Log "Event Logs" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would clean: Windows Event Logs" -Level DETAIL
        return
    }

    try {
        $logs = wevtutil el 2>$null | Where-Object {
            $_ -notmatch 'Analytic' -and
            $_ -notmatch 'Debug' -and
            $_ -notmatch 'Security'  # Keep Security log
        }

        $clearedCount = 0
        $failedCount = 0
        foreach ($log in $logs) {
            try {
                wevtutil cl $log 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $clearedCount++
                } else {
                    $failedCount++
                }
            } catch {
                $failedCount++
            }
        }

        if ($failedCount -gt 0) {
            Write-Log "Event logs cleared: $clearedCount, failed: $failedCount" -Level WARNING
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
        # Flush DNS cache using ipconfig
        $result = ipconfig /flushdns 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0 -or $result -match "Successfully flushed|успешно") {
            Write-Log "DNS cache flushed successfully" -Level SUCCESS
        } else {
            # Command completed but may have failed - log as warning
            Write-Log "DNS cache flush returned unexpected result (exit code: $exitCode)" -Level WARNING
            $script:Stats.WarningsCount++
        }

        # Also clear DNS client cache via cmdlet if available
        try {
            Clear-DnsClientCache -ErrorAction SilentlyContinue
        } catch { }

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
        $osEdition = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        $telemetryLevel = if ($osEdition -match "Enterprise|Education") { 0 } else { 1 }

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
        Write-Host "`r  Delete Windows.old? (Y/n, default Y in $remaining sec): " -NoNewline -ForegroundColor Yellow
        Start-Sleep -Milliseconds 100
    }

    if ($response -eq "" -or $response -eq "Y") {
        if ($response -eq "") { Write-Host "Y" -ForegroundColor Green }

        Write-Log "Removing Windows.old..." -Level INFO

        try {
            # Take ownership and remove
            $null = takeown /F $windowsOldPath /A /R /D Y 2>&1
            $null = icacls $windowsOldPath /grant Administrators:F /T /C /Q 2>&1
            Remove-Item -Path $windowsOldPath -Recurse -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path $windowsOldPath)) {
                Write-Log "Windows.old removed - $sizeFormatted freed" -Level SUCCESS
                [System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, $size) | Out-Null
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
#region ═══════════════════════════════════════════════════════════════════════

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

    # NPM Cache
    Write-Log "npm Cache" -Level SECTION
    $npmCache = "$env:APPDATA\npm-cache"
    if (Test-Path $npmCache) {
        if ($ReportOnly) {
            $size = Get-FolderSize $npmCache
            Write-Log "Would clean: npm cache - $(Format-FileSize $size)" -Level DETAIL
        } else {
            # Use npm cache clean if available
            $npm = Get-Command npm -ErrorAction SilentlyContinue
            if ($npm) {
                try {
                    & npm cache clean --force 2>&1 | Out-Null
                    Write-Log "npm cache cleaned (via npm)" -Level SUCCESS
                } catch {
                    Remove-FolderContent -Path $npmCache -Category "Developer" -Description "npm cache"
                }
            } else {
                Remove-FolderContent -Path $npmCache -Category "Developer" -Description "npm cache"
            }
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
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                          DOCKER/WSL CLEANUP FUNCTIONS
#region ═══════════════════════════════════════════════════════════════════════

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
            $dockerInfo = docker info 2>&1
            $dockerRunning = $LASTEXITCODE -eq 0
        } catch { }

        if ($dockerRunning) {
            if ($ReportOnly) {
                Write-Log "Would run: docker system prune" -Level DETAIL
            } else {
                try {
                    # Remove unused data (stopped containers, unused networks, dangling images, build cache)
                    Write-Log "Running docker system prune..." -Level INFO
                    $result = docker system prune -f 2>&1

                    # Parse reclaimed space
                    if ($result -match "reclaimed\s+([\d.]+\s*[KMGT]?B)") {
                        Write-Log "Docker cleanup: $($Matches[1]) reclaimed" -Level SUCCESS
                    } else {
                        Write-Log "Docker cleanup completed" -Level SUCCESS
                    }

                    # Also clean build cache
                    docker builder prune -f 2>&1 | Out-Null
                    Write-Log "Docker build cache cleaned" -Level SUCCESS

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
                                [System.Threading.Interlocked]::Add([ref]$script:Stats.TotalFreedBytes, $saved) | Out-Null
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
#region ═══════════════════════════════════════════════════════════════════════

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

    # VS 2019/2022 caches
    $vsCaches = @(
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ComponentModelCache"; Desc = "Component Model Cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\ImageCacheRoot"; Desc = "Image Cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\*\DesignTimeBuild"; Desc = "Design Time Build" }
        @{ Path = "$env:APPDATA\Microsoft\VisualStudio\*\*.roslynobjectin"; Desc = "Roslyn Temp" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VSCommon\*\SQM"; Desc = "SQM Data" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\VisualStudio\Packages\_Instances"; Desc = "Package Instances" }
    )

    Write-Log "Visual Studio Caches" -Level SECTION

    foreach ($item in $vsCaches) {
        $paths = Resolve-Path -Path $item.Path -ErrorAction SilentlyContinue
        foreach ($path in $paths) {
            Remove-FolderContent -Path $path.Path -Category "VS" -Description $item.Desc
        }
    }

    # MEF Cache
    Write-Log "MEF Cache" -Level SECTION
    $mefPath = "$env:LOCALAPPDATA\Microsoft\VisualStudio"
    if (Test-Path $mefPath) {
        Get-ChildItem -Path $mefPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $mefCache = Join-Path $_.FullName "MEFCacheAssembly"
            Remove-FolderContent -Path $mefCache -Category "VS" -Description "MEF Cache"
        }
    }

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
#region ═══════════════════════════════════════════════════════════════════════

function Invoke-DISMCleanup {
    <#
    .SYNOPSIS
        Runs DISM component cleanup
    #>
    # Clear any existing progress bar before DISM outputs to console
    Write-Progress -Activity "Cleanup" -Completed

    Write-Log "Windows Component Cleanup (DISM)" -Level SECTION

    if ($ReportOnly) {
        Write-Log "Would run: DISM /Online /Cleanup-Image /StartComponentCleanup" -Level DETAIL
        return
    }

    Write-Log "Running DISM cleanup (this may take several minutes)..." -Level INFO

    try {
        $dismProcess = Start-Process -FilePath "$env:SystemRoot\System32\Dism.exe" `
            -ArgumentList "/Online", "/Cleanup-Image", "/StartComponentCleanup", "/ResetBase" `
            -NoNewWindow -PassThru -Wait

        switch ($dismProcess.ExitCode) {
            0       { Write-Log "DISM cleanup completed successfully" -Level SUCCESS }
            87      { Write-Log "DISM cleanup not needed" -Level INFO }
            default { Write-Log "DISM completed with code: $($dismProcess.ExitCode)" -Level WARNING }
        }
    } catch {
        Write-Log "DISM error: $_" -Level WARNING
        $script:Stats.WarningsCount++
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

    if ($task) {
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
            Write-Log "Storage Sense timed out after $timeout seconds (may still be running)" -Level WARNING
            $script:Stats.WarningsCount++
        }
    } else {
        # Fallback to cleanmgr
        Write-Log "Storage Sense task not found, using Disk Cleanup..." -Level INFO

        # Configure cleanup categories
        $sageset = 9999
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

        $categories = @(
            "Active Setup Temp Folders", "BranchCache", "Downloaded Program Files",
            "Internet Cache Files", "Memory Dump Files", "Old ChkDsk Files",
            "Previous Installations", "Recycle Bin", "Setup Log Files",
            "System error memory dump files", "System error minidump files",
            "Temporary Files", "Temporary Setup Files", "Thumbnail Cache",
            "Update Cleanup", "Upgrade Discarded Files", "User file versions",
            "Windows Error Reporting Archive Files", "Windows Error Reporting Queue Files",
            "Windows Upgrade Log Files", "Windows ESD installation files"
        )

        foreach ($category in $categories) {
            $categoryPath = Join-Path $regPath $category
            if (Test-Path $categoryPath) {
                Set-ItemProperty -Path $categoryPath -Name "StateFlags$sageset" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }

        # Run cleanmgr with timeout
        $cleanmgr = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" `
            -NoNewWindow -PassThru

        $cleanmgr | Wait-Process -Timeout 600 -ErrorAction SilentlyContinue

        if (-not $cleanmgr.HasExited) {
            $cleanmgr | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "Disk Cleanup timed out" -Level WARNING
        } else {
            Write-Log "Disk Cleanup completed" -Level SUCCESS
        }
    }
}

#endregion

#region ═══════════════════════════════════════════════════════════════════════
#                              MAIN EXECUTION
#region ═══════════════════════════════════════════════════════════════════════

function Show-Banner {
    try { Clear-Host } catch { }

    $banner = @"

  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                      ║
  ║        ██████╗ ██████╗ ███████╗ █████╗ ███╗   ███╗                   ║
  ║        ██╔══██╗██╔══██╗██╔════╝██╔══██╗████╗ ████║                   ║
  ║        ██║  ██║██████╔╝█████╗  ███████║██╔████╔██║                   ║
  ║        ██║  ██║██╔══██╗██╔══╝  ██╔══██║██║╚██╔╝██║                   ║
  ║        ██████╔╝██║  ██║███████╗██║  ██║██║ ╚═╝ ██║                   ║
  ║        ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝                   ║
  ║                                                                      ║
  ║            Ultimate Windows 11 Maintenance Script v2.0               ║
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
    $elapsed = (Get-Date) - $script:Stats.StartTime
    $elapsedStr = "{0:D2}:{1:D2}:{2:D2}" -f [int]$elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds

    # Get disk info
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeSpace = [math]::Round($drive.Free / 1GB, 2)
    $totalSize = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $freePercent = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)

    Write-Progress -Activity "Complete" -Completed

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                         FINAL STATISTICS                             ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

    # Duration
    Write-Host "  ║  " -NoNewline -ForegroundColor Cyan
    Write-Host "Duration:              " -NoNewline -ForegroundColor White
    Write-Host $elapsedStr.PadRight(47) -NoNewline -ForegroundColor Green
    Write-Host "║" -ForegroundColor Cyan

    # Updates
    if ($script:Stats.WindowsUpdatesCount -gt 0 -or $script:Stats.AppUpdatesCount -gt 0) {
        Write-Host "  ║  " -NoNewline -ForegroundColor Cyan
        Write-Host "Updates installed:     " -NoNewline -ForegroundColor White
        $updatesStr = "Windows: $($script:Stats.WindowsUpdatesCount), Apps: $($script:Stats.AppUpdatesCount)"
        Write-Host $updatesStr.PadRight(47) -NoNewline -ForegroundColor Green
        Write-Host "║" -ForegroundColor Cyan
    }

    # Space freed
    Write-Host "  ║  " -NoNewline -ForegroundColor Cyan
    Write-Host "Space freed:           " -NoNewline -ForegroundColor White
    $freedStr = Format-FileSize $script:Stats.TotalFreedBytes
    Write-Host $freedStr.PadRight(47) -NoNewline -ForegroundColor Green
    Write-Host "║" -ForegroundColor Cyan

    # Freed by category
    if ($script:Stats.FreedByCategory.Count -gt 0) {
        Write-Host "  ╠──────────────────────────────────────────────────────────────────────╣" -ForegroundColor Cyan
        foreach ($cat in ($script:Stats.FreedByCategory.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 5)) {
            if ($cat.Value -gt 0) {
                Write-Host "  ║    " -NoNewline -ForegroundColor Cyan
                $catName = "$($cat.Key):".PadRight(20)
                Write-Host $catName -NoNewline -ForegroundColor Gray
                Write-Host (Format-FileSize $cat.Value).PadRight(45) -NoNewline -ForegroundColor Gray
                Write-Host "║" -ForegroundColor Cyan
            }
        }
    }

    Write-Host "  ╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

    # Disk space
    Write-Host "  ║  " -NoNewline -ForegroundColor Cyan
    Write-Host "Free disk space:       " -NoNewline -ForegroundColor White
    $diskStr = "$freeSpace GB / $totalSize GB ($freePercent% free)"
    Write-Host $diskStr.PadRight(47) -NoNewline -ForegroundColor Yellow
    Write-Host "║" -ForegroundColor Cyan

    # Warnings/Errors
    if ($script:Stats.WarningsCount -gt 0 -or $script:Stats.ErrorsCount -gt 0) {
        Write-Host "  ║  " -NoNewline -ForegroundColor Cyan
        Write-Host "Warnings/Errors:       " -NoNewline -ForegroundColor White
        $issueStr = "$($script:Stats.WarningsCount) warnings, $($script:Stats.ErrorsCount) errors"
        $issueColor = if ($script:Stats.ErrorsCount -gt 0) { "Red" } else { "Yellow" }
        Write-Host $issueStr.PadRight(47) -NoNewline -ForegroundColor $issueColor
        Write-Host "║" -ForegroundColor Cyan
    }

    Write-Host "  ╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    # Reboot notification
    if ($script:Stats.RebootRequired) {
        Write-Host ""
        Write-Host "  ⚠ " -NoNewline -ForegroundColor Yellow
        Write-Host "Reboot required to complete Windows updates!" -ForegroundColor Yellow
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
    }

    Write-Host ""
    Write-Host "  Log saved to: $script:LogPath" -ForegroundColor DarkGray
    Write-Host ""

    # Pause before closing window (for users running from downloaded script)
    Write-Host "  Press any key to exit (auto-close in 60 seconds)..." -ForegroundColor DarkGray

    $timeout = 60
    $startTime = Get-Date

    # Clear keyboard buffer
    while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }

    while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
        if ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
            break
        }
        Start-Sleep -Milliseconds 100
    }
}

function Start-WinClean {
    # Initialize log
    "WinClean v2.0 - Started at $(Get-Date)" | Out-File -FilePath $script:LogPath -Encoding utf8
    "=" * 70 | Out-File -FilePath $script:LogPath -Append -Encoding utf8

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
        Write-Host "  Continue anyway? (y/N): " -NoNewline -ForegroundColor Yellow

        $response = Read-Host
        if ($response -notmatch "^[YyДд]") {
            Write-Host ""
            Write-Host "  Operation cancelled. Please reboot and run again." -ForegroundColor Yellow
            Write-Host ""
            return
        }
        Write-Host ""
    }

    try {
        # Phase 1: Preparation
        $null = New-SystemRestorePoint -Description "WinClean $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

        # Phase 2: Updates
        if (-not $SkipUpdates) {
            Update-WindowsSystem
            Update-Applications
        }

        # Phase 3: Cleanup
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

        # Phase 4: Developer Cleanup
        Clear-DeveloperCaches

        # Phase 5: Docker/WSL Cleanup
        Clear-DockerWSL

        # Phase 6: Visual Studio Cleanup
        Clear-VisualStudio

        # Phase 7: System Cleanup
        if (-not $SkipCleanup) {
            Write-Log "DEEP SYSTEM CLEANUP" -Level TITLE
            Update-Progress -Activity "Deep Cleanup" -Status "Running system cleanup..."

            Invoke-DISMCleanup
            Invoke-StorageSense
            Clear-WindowsOld
        }

        # Phase 8: Telemetry Configuration (if requested)
        if ($DisableTelemetry) {
            Set-WindowsTelemetry -Disable
        }

    } catch {
        Write-Log "Critical error: $_" -Level ERROR
        $script:Stats.ErrorsCount++
    } finally {
        Show-FinalStatistics
    }
}

# Entry point
if ($MyInvocation.InvocationName -ne '.') {
    Start-WinClean
}

#endregion
