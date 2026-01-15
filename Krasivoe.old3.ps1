# Улучшенный скрипт для комплексного обновления и очистки Windows
# Версия 3.0 - Исправленная и оптимизированная версия
# Требуется запуск с правами администратора

# Установка кодировки для корректного отображения русского текста
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Глобальные переменные для статистики
$script:totalFreedSpace = 0
$script:updatedAppsCount = 0
$script:failedAppsCount = 0
$script:skippedAppsCount = 0
$script:startTime = Get-Date
$script:rebootRequired = $false

# Функция для проверки прав администратора
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $user
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Функция для цветного вывода с временными метками
function Write-ColoredLog {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch ($Type) {
        "INFO"    { 
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
            Write-Host "[INFO] " -NoNewline -ForegroundColor Cyan
            Write-Host $Message -ForegroundColor White
        }
        "SUCCESS" { 
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
            Write-Host "[OK] " -NoNewline -ForegroundColor Green
            Write-Host $Message -ForegroundColor White
        }
        "WARNING" { 
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
            Write-Host "[WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host $Message -ForegroundColor Yellow
        }
        "ERROR"   { 
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
            Write-Host "[ERROR] " -NoNewline -ForegroundColor Red
            Write-Host $Message -ForegroundColor Red
        }
        "TITLE"   { 
            Write-Host "`n$("=" * 60)" -ForegroundColor Magenta
            Write-Host $Message -ForegroundColor Magenta
            Write-Host "$("=" * 60)`n" -ForegroundColor Magenta
        }
    }
}

# Функция для отображения прогресс-бара
function Show-Progress {
    param (
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )
    
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

# Функция для проверки интернет-соединения
function Test-InternetConnection {
    try {
        $testConnection = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
        if (-not $testConnection) {
            $testConnection = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet
        }
        return $testConnection
    } catch {
        return $false
    }
}

# Функция для получения размера папки
function Get-FolderSize {
    param ([string]$Path)
    
    if (Test-Path $Path) {
        try {
            $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                    Measure-Object -Property Length -Sum).Sum
            return [math]::Round($size / 1MB, 2)
        } catch {
            return 0
        }
    }
    return 0
}

# Функция для очистки папки с подсчетом освобожденного места
function Remove-FolderContent {
    param (
        [string]$Path,
        [string]$Description
    )
    
    if (Test-Path $Path) {
        $sizeBefore = Get-FolderSize -Path $Path
        try {
            Remove-Item -Path "$Path\*" -Force -Recurse -ErrorAction SilentlyContinue
            $sizeAfter = Get-FolderSize -Path $Path
            $freed = $sizeBefore - $sizeAfter
            $script:totalFreedSpace += $freed
            
            if ($freed -gt 0) {
                Write-ColoredLog "$Description - Освобождено: $freed МБ" "SUCCESS"
            }
        } catch {
            Write-ColoredLog "Ошибка при очистке $Description : $_" "WARNING"
        }
    }
}

# Функция для создания точки восстановления
function New-SystemRestorePoint {
    param ([string]$Description)
    
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        return $true
    } catch {
        Write-ColoredLog "Не удалось создать точку восстановления: $_" "WARNING"
        return $false
    }
}

# Функция для отображения меню
function Show-Menu {
    Clear-Host
    Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     СКРИПТ ОБНОВЛЕНИЯ И ОБСЛУЖИВАНИЯ WINDOWS 11         ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Выберите режим работы:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[1] " -NoNewline -ForegroundColor Green; Write-Host "Полное обслуживание (рекомендуется)"
    Write-Host "    └─ Обновления + Очистка" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[2] " -NoNewline -ForegroundColor Green; Write-Host "Только обновления"
    Write-Host "    └─ Windows Update + Приложения" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[3] " -NoNewline -ForegroundColor Green; Write-Host "Только очистка"
    Write-Host "    └─ Полная очистка диска + Кэш" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[4] " -NoNewline -ForegroundColor Green; Write-Host "Быстрая очистка"
    Write-Host "    └─ Только временные файлы" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[5] " -NoNewline -ForegroundColor Green; Write-Host "Проверка целостности системы"
    Write-Host "    └─ SFC /scannow (может занять 20+ минут)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[6] " -NoNewline -ForegroundColor Green; Write-Host "Настройка автозапуска"
    Write-Host "    └─ Создать задачу в планировщике" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[0] " -NoNewline -ForegroundColor Red; Write-Host "Выход"
    Write-Host ""
}

# Функция для обновления Windows
function Update-WindowsSystem {
    Write-ColoredLog "ОБНОВЛЕНИЕ WINDOWS" "TITLE"
    
    # Проверка интернет-соединения
    if (-not (Test-InternetConnection)) {
        Write-ColoredLog "Отсутствует подключение к интернету. Обновления невозможны." "ERROR"
        return
    }
    
    try {
        # Проверяем и устанавливаем NuGet провайдер если нужно
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget -or $nuget.Version -lt "2.8.5.201") {
            Write-ColoredLog "Установка NuGet провайдера..." "INFO"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
        }
        
        # Установка модуля PSWindowsUpdate если не установлен
        if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-ColoredLog "Установка модуля PSWindowsUpdate..." "INFO"
            
            # Устанавливаем модуль
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        }

        # Импортируем модуль
        Import-Module PSWindowsUpdate -ErrorAction Stop
        
        # Получение списка обновлений
        Write-ColoredLog "Поиск доступных обновлений Windows..." "INFO"
        $availableUpdates = @(Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop)
        
        if ($availableUpdates.Count -gt 0) {
            Write-ColoredLog "Найдено обновлений: $($availableUpdates.Count)" "INFO"
            
            # Показываем список обновлений
            Write-Host "`nСписок обновлений:" -ForegroundColor Cyan
            $availableUpdates | ForEach-Object {
                $size = if ($_.Size) { " ($([math]::Round($_.Size/1MB, 2)) МБ)" } else { "" }
                Write-Host "  • $($_.Title)$size" -ForegroundColor Gray
            }
            Write-Host ""
            
            # Установка обновлений
            Write-ColoredLog "Установка обновлений Windows..." "INFO"
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null
            
            Write-ColoredLog "Установка обновлений Windows завершена" "SUCCESS"
            
            # Проверка необходимости перезагрузки
            if (Get-WURebootStatus -Silent) {
                $script:rebootRequired = $true
            }
        } else {
            Write-ColoredLog "Система полностью обновлена" "SUCCESS"
        }
        
    } catch {
        Write-ColoredLog "Ошибка при обновлении Windows: $_" "ERROR"
    }
}

# Полностью переработанная функция обновления приложений через winget
function Update-Applications {
    Write-ColoredLog "ОБНОВЛЕНИЕ ПРИЛОЖЕНИЙ" "TITLE"
    
    if (-not (Test-InternetConnection)) {
        Write-ColoredLog "Отсутствует подключение к интернету. Обновления невозможны." "ERROR"
        return
    }
    
    try {
        # Проверяем наличие winget
        $wingetPath = $null
        
        # Способ 1: Через Get-Command
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $wingetPath = $wingetCmd.Source
        }
        
        # Способ 2: Прямой путь
        if (-not $wingetPath -and (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")) {
            $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        }
        
        if (-not $wingetPath) {
            Write-ColoredLog "Winget не найден. Установите App Installer из Microsoft Store." "ERROR"
            return
        }
        
        Write-ColoredLog "Обновление источников winget..." "INFO"
        & $wingetPath source update | Out-Null
        
        Write-ColoredLog "Проверка доступных обновлений..." "INFO"
        Write-Host ""
        
        # Сначала показываем список доступных обновлений
        $tempFile = [System.IO.Path]::GetTempFileName()
        $checkProcess = Start-Process -FilePath $wingetPath `
                                    -ArgumentList "upgrade" `
                                    -NoNewWindow `
                                    -RedirectStandardOutput $tempFile `
                                    -PassThru -Wait
        
        $output = Get-Content $tempFile -Raw -Encoding UTF8
        Remove-Item $tempFile -Force
        
        # Проверяем, есть ли обновления
        $hasUpdates = $false
        if ($output -match "(\d+)\s+(обновлени|upgrade|пакет)") {
            $updateCount = $Matches[1]
            if ([int]$updateCount -gt 0) {
                $hasUpdates = $true
                Write-ColoredLog "Найдено обновлений: $updateCount" "INFO"
            }
        } elseif ($output -notmatch "(доступных обновлений нет|No installed package|No applicable update)") {
            # Если не можем определить количество, но текст не говорит что обновлений нет
            $hasUpdates = $true
            Write-ColoredLog "Обнаружены доступные обновления" "INFO"
        }
        
        if (-not $hasUpdates) {
            Write-ColoredLog "Все приложения актуальны" "SUCCESS"
            return
        }
        
        # Показываем список
        Write-Host $output
        Write-Host ""
        
        Write-ColoredLog "Запуск обновления всех приложений..." "INFO"
        Write-ColoredLog "Это может занять несколько минут. Следите за прогрессом ниже:" "INFO"
        Write-Host ""
        
        # Запускаем обновление с видимым выводом
        $updateProcess = Start-Process -FilePath $wingetPath `
                                     -ArgumentList "upgrade", "--all", `
                                                  "--accept-source-agreements", `
                                                  "--accept-package-agreements", `
                                                  "--disable-interactivity", `
                                                  "--include-unknown" `
                                     -NoNewWindow -PassThru
        
        # Ждем завершения процесса
        $updateProcess.WaitForExit()
        
        if ($updateProcess.ExitCode -eq 0) {
            Write-Host ""
            Write-ColoredLog "Обновление приложений завершено успешно" "SUCCESS"
            $script:updatedAppsCount = [int]$updateCount
        } else {
            Write-Host ""
            Write-ColoredLog "Обновление завершено с предупреждениями (код: $($updateProcess.ExitCode))" "WARNING"
        }
        
    } catch {
        Write-ColoredLog "Критическая ошибка при обновлении приложений: $_" "ERROR"
    }
}

# Функция очистки системы
function Clear-System {
    param ([bool]$QuickClean = $false)
    
    Write-ColoredLog "ОЧИСТКА СИСТЕМЫ" "TITLE"
    
    # Проверка свободного места до очистки
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeSpaceBefore = [math]::Round($drive.Free / 1GB, 2)
    Write-ColoredLog "Свободно места до очистки: $freeSpaceBefore ГБ" "INFO"
    
    # Временные файлы
    Write-ColoredLog "Очистка временных файлов..." "INFO"
    Remove-FolderContent -Path $env:TEMP -Description "Временные файлы пользователя"
    Remove-FolderContent -Path "C:\Windows\Temp" -Description "Временные файлы Windows"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Temp" -Description "Локальные временные файлы"
    
    if (-not $QuickClean) {
        # Очистка Windows.old
        if (Test-Path "C:\Windows.old") {
            $oldSize = Get-FolderSize -Path "C:\Windows.old"
            Write-ColoredLog "Найдена папка Windows.old ($oldSize МБ). Очистка..." "INFO"
            
            $confirm = Read-Host "Удалить папку Windows.old? Это действие необратимо! (y/n)"
            if ($confirm -eq 'y') {
                takeown /F "C:\Windows.old" /A /R /D Y 2>$null | Out-Null
                icacls "C:\Windows.old" /grant Administrators:F /T /C 2>$null | Out-Null
                Remove-Item -Path "C:\Windows.old" -Force -Recurse -ErrorAction SilentlyContinue
                Write-ColoredLog "Windows.old удалена" "SUCCESS"
            }
        }
        
        # Очистка кэша Windows Update
        Write-ColoredLog "Очистка кэша Windows Update..." "INFO"
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
        Remove-FolderContent -Path "C:\Windows\SoftwareDistribution\Download" -Description "Загрузки обновлений Windows"
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Start-Service -Name bits -ErrorAction SilentlyContinue
        
        # Очистка кэша браузеров
        Write-ColoredLog "Очистка кэша браузеров..." "INFO"
        
        # Chrome
        $chromeCachePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage"
        )
        foreach ($path in $chromeCachePaths) {
            Remove-FolderContent -Path $path -Description "Кэш Chrome"
        }
        
        # Edge
        $edgeCachePaths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage"
        )
        foreach ($path in $edgeCachePaths) {
            Remove-FolderContent -Path $path -Description "Кэш Edge"
        }
        
        # Яндекс.Браузер
        $yandexCachePaths = @(
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Service Worker\CacheStorage"
        )
        foreach ($path in $yandexCachePaths) {
            Remove-FolderContent -Path $path -Description "Кэш Яндекс.Браузер"
        }
        
        # Firefox
        if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
            Get-ChildItem -Path "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory | ForEach-Object {
                Remove-FolderContent -Path "$($_.FullName)\cache2" -Description "Кэш Firefox"
                Remove-FolderContent -Path "$($_.FullName)\startupCache" -Description "Startup кэш Firefox"
            }
        }
        
        # Очистка кэша Windows Store
        Write-ColoredLog "Очистка кэша Windows Store..." "INFO"
        Start-Process -FilePath "wsreset.exe" -NoNewWindow -Wait
        
        # Очистка логов
        Write-ColoredLog "Очистка системных логов..." "INFO"
        wevtutil el | ForEach-Object {
            wevtutil cl "$_" 2>$null
        }
        
        # Очистка корзины
        Write-ColoredLog "Очистка корзины..." "INFO"
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-ColoredLog "Корзина очищена" "SUCCESS"
        } catch {
            # Альтернативный метод
            $recycleBin = New-Object -ComObject Shell.Application
            $recycleBin.NameSpace(0x0a).Items() | ForEach-Object {
                Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        # Очистка кэша иконок
        Write-ColoredLog "Очистка кэша иконок..." "INFO"
        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
        Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Description "Кэш эскизов"
        
        # DISM очистка
        Write-ColoredLog "Запуск DISM для очистки компонентов..." "INFO"
        Write-ColoredLog "Это может занять несколько минут..." "INFO"
        
        $dismResult = Start-Process -FilePath "Dism.exe" `
                                   -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" `
                                   -Wait -NoNewWindow -PassThru
        
        if ($dismResult.ExitCode -eq 0) {
            Write-ColoredLog "Очистка компонентов Windows завершена" "SUCCESS"
        } else {
            Write-ColoredLog "DISM завершился с предупреждением (код: $($dismResult.ExitCode))" "WARNING"
        }
        
        # Запуск Disk Cleanup
        Write-ColoredLog "Настройка параметров очистки диска..." "INFO"
        
        # Настраиваем все параметры очистки
        $cleanupKeys = @(
            "Active Setup Temp Folders",
            "BranchCache",
            "Downloaded Program Files",
            "Internet Cache Files",
            "Memory Dump Files",
            "Old ChkDsk Files",
            "Previous Installations",
            "Recycle Bin",
            "Setup Log Files",
            "System error memory dump files",
            "System error minidump files",
            "Temporary Files",
            "Temporary Setup Files",
            "Thumbnail Cache",
            "Update Cleanup",
            "Upgrade Discarded Files",
            "Windows Error Reporting Archive Files",
            "Windows Error Reporting Queue Files",
            "Windows Error Reporting System Archive Files",
            "Windows Error Reporting System Queue Files",
            "Windows ESD installation files",
            "Windows Upgrade Log Files"
        )
        
        # Настраиваем реестр для cleanmgr
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        foreach ($key in $cleanupKeys) {
            $keyPath = Join-Path $regPath $key
            if (Test-Path $keyPath) {
                Set-ItemProperty -Path $keyPath -Name "StateFlags9999" -Value 2 -Type DWORD -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-ColoredLog "Запуск очистки диска..." "INFO"
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:9999" -Wait -NoNewWindow
        Write-ColoredLog "Очистка диска завершена" "SUCCESS"
    }
    
    # Подсчет освобожденного места
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeSpaceAfter = [math]::Round($drive.Free / 1GB, 2)
    $totalFreed = $freeSpaceAfter - $freeSpaceBefore
    
    # Форматируем значения для правильного выравнивания
    $freedSpaceStr = "$([math]::Round($totalFreed, 2)) ГБ"
    $diskSpaceStr = "$freeSpaceAfter ГБ"
    
    Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    РЕЗУЛЬТАТЫ ОЧИСТКИ                    ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host ("║ Освобождено места: {0,-38}║" -f $freedSpaceStr) -ForegroundColor Green
    Write-Host ("║ Свободно на диске: {0,-38}║" -f $diskSpaceStr) -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
}

# Функция проверки целостности системы (опциональная)
function Test-SystemIntegrity {
    Write-ColoredLog "ПРОВЕРКА ЦЕЛОСТНОСТИ СИСТЕМЫ" "TITLE"
    
    try {
        Write-ColoredLog "Запуск SFC /scannow..." "INFO"
        Write-ColoredLog "Это может занять от 20 минут до нескольких часов..." "WARNING"
        Write-ColoredLog "Вы можете прервать процесс нажатием Ctrl+C" "INFO"
        Write-Host ""
        
        # Запускаем SFC с видимым выводом
        & sfc /scannow
        
        Write-Host ""
        Write-ColoredLog "Проверка целостности завершена" "SUCCESS"
        
        $runDism = Read-Host "Запустить DISM для восстановления? (y/n)"
        if ($runDism -eq 'y') {
            Write-ColoredLog "Запуск DISM для восстановления..." "INFO"
            & Dism /Online /Cleanup-Image /RestoreHealth
            
            Write-Host ""
            Write-ColoredLog "Восстановление завершено" "SUCCESS"
        }
        
    } catch {
        Write-ColoredLog "Ошибка при проверке целостности системы: $_" "ERROR"
    }
}

# Функция создания задачи в планировщике
function New-ScheduledMaintenanceTask {
    Write-ColoredLog "НАСТРОЙКА АВТОМАТИЧЕСКОГО ОБСЛУЖИВАНИЯ" "TITLE"
    
    try {
        $taskName = "Windows Maintenance Script"
        $scriptPath = $MyInvocation.MyCommand.Path
        
        if (-not $scriptPath) {
            Write-ColoredLog "Не удалось определить путь к скрипту" "ERROR"
            return
        }
        
        # Удаляем существующую задачу, если есть
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
        # Запрашиваем расписание
        Write-Host "Выберите расписание запуска:" -ForegroundColor Yellow
        Write-Host "[1] Еженедельно (рекомендуется)" -ForegroundColor Green
        Write-Host "[2] Ежемесячно" -ForegroundColor Green
        Write-Host "[3] При входе в систему" -ForegroundColor Green
        Write-Host "[0] Отмена" -ForegroundColor Red
        
        $schedule = Read-Host "`nВаш выбор"
        
        switch ($schedule) {
            "1" {
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
                $desc = "еженедельно по воскресеньям в 3:00"
            }
            "2" {
                $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 3am
                $desc = "ежемесячно 1-го числа в 3:00"
            }
            "3" {
                $trigger = New-ScheduledTaskTrigger -AtLogon
                $desc = "при входе в систему"
            }
            default {
                Write-ColoredLog "Создание задачи отменено" "WARNING"
                return
            }
        }
        
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                                         -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Auto"
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                                -DontStopIfGoingOnBatteries `
                                                -StartWhenAvailable `
                                                -RunOnlyIfNetworkAvailable
        
        Register-ScheduledTask -TaskName $taskName `
                              -Trigger $trigger `
                              -Action $action `
                              -Principal $principal `
                              -Settings $settings `
                              -Description "Автоматическое обслуживание Windows"
        
        Write-ColoredLog "Задача создана успешно! Запуск $desc" "SUCCESS"
        
    } catch {
        Write-ColoredLog "Ошибка при создании задачи: $_" "ERROR"
    }
}

# Главная функция
function Start-Maintenance {
    param ([string]$Mode = "Interactive")
    
    if (-not (Test-Administrator)) {
        Write-ColoredLog "Скрипт требует запуска с правами администратора!" "ERROR"
        Write-Host "`nНажмите любую клавишу для выхода..."
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        Exit 1
    }
    
    if ($Mode -eq "Auto") {
        # Автоматический режим - полное обслуживание
        Write-ColoredLog "Автоматический запуск - выполняется полное обслуживание" "INFO"
        
        # Создаем точку восстановления
        Write-ColoredLog "Создание точки восстановления..." "INFO"
        if (New-SystemRestorePoint -Description "Auto Maintenance $(Get-Date -Format 'yyyy-MM-dd')") {
            Write-ColoredLog "Точка восстановления создана" "SUCCESS"
        }
        
        Update-WindowsSystem
        Update-Applications
        Clear-System
        
        # Показываем итоговую статистику
        $endTime = Get-Date
        $duration = $endTime - $script:startTime
        
        # Форматируем значения для правильного выравнивания
        $durationStr = $duration.ToString('hh\:mm\:ss')
        $freedSpaceGb = [math]::Round($script:totalFreedSpace / 1024, 2)
        
        Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                  ИТОГОВАЯ СТАТИСТИКА                     ║" -ForegroundColor Cyan
        Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host ("║ Время выполнения: {0,-39}║" -f $durationStr) -ForegroundColor Cyan
        Write-Host ("║ Обновлено приложений: {0,-35}║" -f $script:updatedAppsCount) -ForegroundColor Cyan
        Write-Host ("║ Пропущено приложений: {0,-35}║" -f $script:skippedAppsCount) -ForegroundColor Cyan
        Write-Host ("║ Приложений с ошибками: {0,-34}║" -f $script:failedAppsCount) -ForegroundColor Cyan
        Write-Host ("║ Освобождено места: {0,-38}║" -f "$freedSpaceGb ГБ") -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    } else {
        # Интерактивный режим
        Show-Menu
        $choice = Read-Host "Выберите действие (0-6)"
        
        switch ($choice) {
            "1" {
                # Полное обслуживание
                Clear-Host
                Write-ColoredLog "ПОЛНОЕ ОБСЛУЖИВАНИЕ СИСТЕМЫ" "TITLE"
                
                # Создаем точку восстановления
                Write-ColoredLog "Создание точки восстановления..." "INFO"
                if (New-SystemRestorePoint -Description "Full Maintenance $(Get-Date -Format 'yyyy-MM-dd')") {
                    Write-ColoredLog "Точка восстановления создана" "SUCCESS"
                }
                
                Update-WindowsSystem
                Update-Applications
                Clear-System
            }
            "2" {
                # Только обновления
                Clear-Host
                Update-WindowsSystem
                Update-Applications
            }
            "3" {
                # Только очистка
                Clear-Host
                Clear-System
            }
            "4" {
                # Быстрая очистка
                Clear-Host
                Clear-System -QuickClean $true
            }
            "5" {
                # Проверка целостности
                Clear-Host
                Write-ColoredLog "ВНИМАНИЕ!" "WARNING"
                Write-Host ""
                Write-Host "Проверка целостности системы (SFC /scannow) может занять" -ForegroundColor Yellow
                Write-Host "от 20 минут до нескольких часов в зависимости от системы." -ForegroundColor Yellow
                Write-Host ""
                $confirm = Read-Host "Вы уверены, что хотите запустить проверку? (y/n)"
                if ($confirm -eq 'y') {
                    Test-SystemIntegrity
                } else {
                    Write-ColoredLog "Проверка отменена" "INFO"
                }
            }
            "6" {
                # Настройка автозапуска
                Clear-Host
                New-ScheduledMaintenanceTask
            }
            "0" {
                Write-Host "`nВыход из программы..." -ForegroundColor Yellow
                return
            }
            default {
                Write-Host "`nНеверный выбор. Программа завершена." -ForegroundColor Red
                return
            }
        }
        
        if ($choice -ne "0" -and $choice -ne "6") {
            # Показываем итоговую статистику
            $endTime = Get-Date
            $duration = $endTime - $script:startTime
            
            # Форматируем значения для правильного выравнивания
            $durationStr = $duration.ToString('hh\:mm\:ss')
            $freedSpaceGb = [math]::Round($script:totalFreedSpace / 1024, 2)
            
            Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║                  ИТОГОВАЯ СТАТИСТИКА                     ║" -ForegroundColor Cyan
            Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
            Write-Host ("║ Время выполнения: {0,-39}║" -f $durationStr) -ForegroundColor Cyan
            Write-Host ("║ Обновлено приложений: {0,-35}║" -f $script:updatedAppsCount) -ForegroundColor Cyan
            Write-Host ("║ Пропущено приложений: {0,-35}║" -f $script:skippedAppsCount) -ForegroundColor Cyan
            Write-Host ("║ Приложений с ошибками: {0,-34}║" -f $script:failedAppsCount) -ForegroundColor Cyan
            Write-Host ("║ Освобождено места: {0,-38}║" -f "$freedSpaceGb ГБ") -ForegroundColor Cyan
            Write-Host "╚══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
            
            # Проверка необходимости перезагрузки
            if ($script:rebootRequired) {
                Write-Host "`nТребуется перезагрузка для завершения установки обновлений!" -ForegroundColor Yellow
                [console]::Beep(1000, 500)
                $reboot = Read-Host "Перезагрузить компьютер сейчас? (y/n)"
                if ($reboot -eq 'y') {
                    Write-ColoredLog "Перезагрузка через 10 секунд..." "WARNING"
                    Start-Sleep -Seconds 10
                    Restart-Computer
                }
            }
        }
    }
}

# Точка входа
if ($args -contains "-Auto") {
    Start-Maintenance -Mode "Auto"
} else {
    Start-Maintenance -Mode "Interactive"
}

# Звуковой сигнал завершения
[console]::Beep(800, 200)
[console]::Beep(1000, 200)
[console]::Beep(1200, 300)

Write-Host "`nРабота скрипта завершена. Нажмите любую клавишу для выхода..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null