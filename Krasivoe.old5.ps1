# Автоматический скрипт обслуживания Windows 11
# Версия 5.1 - Оптимизированная с улучшенной обработкой ошибок
# Последовательность: Обновление → Проверка (если нужно) → Очистка
# Требуется запуск с правами администратора

#Requires -RunAsAdministrator
#Requires -Version 5.1

# Установка кодировки для корректного отображения русского текста
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Глобальные переменные
$script:rebootRequired = $false
$script:updatesInstalled = $false
$script:totalFreedSpace = 0
$script:startTime = Get-Date
$script:windowsUpdatesCount = 0
$script:appUpdatesCount = 0
$script:errorsCount = 0

# Функция для корректного завершения скрипта
function Exit-Script {
    param([int]$ExitCode = 0)
    
    Write-Host "`nНажмите любую клавишу для выхода..."
    try {
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        Read-Host "Нажмите Enter для выхода"
    }
    
    Exit $ExitCode
}

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

# Функция для проверки интернет-соединения
function Test-InternetConnection {
    try {
        # Пробуем несколько DNS серверов для надежности
        $dnsServers = @("8.8.8.8", "1.1.1.1", "8.8.4.4")
        
        foreach ($dns in $dnsServers) {
            if (Test-Connection -ComputerName $dns -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                return $true
            }
        }
        
        return $false
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
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
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
    
    # Защита от удаления критичных системных папок
    $protectedPaths = @(
        "C:\Windows",
        "C:\Windows\System32",
        "C:\Program Files",
        "C:\Program Files (x86)",
        $env:USERPROFILE,
        "C:\Users"
    )
    
    foreach ($protected in $protectedPaths) {
        if ($Path -eq $protected -or $Path -eq "$protected\") {
            Write-ColoredLog "Попытка очистки защищенной папки предотвращена: $Path" "ERROR"
            return
        }
    }
    
    if (Test-Path $Path) {
        $sizeBefore = Get-FolderSize -Path $Path
        try {
            # Получаем элементы для удаления
            $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
            $itemCount = $items.Count
            
            if ($itemCount -gt 0) {
                Remove-Item -Path "$Path\*" -Force -Recurse -ErrorAction SilentlyContinue
                $sizeAfter = Get-FolderSize -Path $Path
                $freed = $sizeBefore - $sizeAfter
                $script:totalFreedSpace += $freed
                
                if ($freed -gt 0) {
                    $freedMb = [math]::Round($freed, 2)
                    Write-ColoredLog "$Description - Освобождено: $freedMb МБ ($itemCount объектов)" "SUCCESS"
                }
            }
        } catch {
            Write-ColoredLog "Ошибка при очистке ${Description}: $_" "WARNING"
        }
    }
}

# Функция для создания точки восстановления
function New-SystemRestorePoint {
    param ([string]$Description)
    
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-ColoredLog "Точка восстановления создана: $Description" "SUCCESS"
        return $true
    } catch {
        Write-ColoredLog "Не удалось создать точку восстановления: $_" "WARNING"
        $script:errorsCount++
        return $false
    }
}

# Функция для безопасной установки и импорта модуля PSWindowsUpdate
function Initialize-PSWindowsUpdate {
    try {
        # Проверяем наличие модуля
        if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-ColoredLog "Установка модуля PSWindowsUpdate..." "INFO"
            
            # Проверяем и устанавливаем NuGet provider
            $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nugetProvider -or $nugetProvider.Version -lt "2.8.5.201") {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
            }
            
            # Устанавливаем модуль
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop | Out-Null
            Write-ColoredLog "Модуль установлен успешно." "SUCCESS"
        }
        
        # Импортируем модуль
        Import-Module PSWindowsUpdate -ErrorAction Stop
        return $true
    } catch {
        Write-ColoredLog "Не удалось установить/загрузить PSWindowsUpdate: $_" "ERROR"
        return $false
    }
}

# Функция обновления Windows с полным выводом
function Update-WindowsSystem {
    Write-ColoredLog "ОБНОВЛЕНИЕ WINDOWS" "TITLE"
    
    if (-not (Test-InternetConnection)) {
        Write-ColoredLog "Отсутствует интернет-соединение. Обновление Windows пропущено." "ERROR"
        return
    }
    
    # Проверка службы wuauserv
    $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-ColoredLog "Служба Windows Update не найдена!" "ERROR"
        return
    }
    if ($service.Status -ne "Running") {
        Write-ColoredLog "Запуск службы Windows Update..." "INFO"
        try {
            Start-Service wuauserv -ErrorAction Stop
            Write-ColoredLog "Служба запущена." "SUCCESS"
        } catch {
            Write-ColoredLog "Не удалось запустить службу: $_" "ERROR"
            return
        }
    }
    
    try {
        # Инициализация PSWindowsUpdate
        if (-not (Initialize-PSWindowsUpdate)) {
            return
        }
        
        # Автоматическая регистрация Microsoft Update
        $muService = Get-WUServiceManager -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Microsoft Update" }
        if (-not $muService) {
            Write-ColoredLog "Регистрация сервиса Microsoft Update..." "INFO"
            try {
                Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -ErrorAction Stop | Out-Null
                Write-ColoredLog "Сервис Microsoft Update зарегистрирован." "SUCCESS"
            } catch {
                Write-ColoredLog "Не удалось зарегистрировать Microsoft Update: $_" "WARNING"
            }
        }
        
        # Получение списка обновлений
        Write-ColoredLog "Поиск доступных обновлений..." "INFO"
        $availableUpdates = @()
        
        try {
            $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
        } catch {
            # Если Microsoft Update не работает, пробуем обычный Windows Update
            Write-ColoredLog "Использование Windows Update вместо Microsoft Update..." "INFO"
            $availableUpdates = Get-WindowsUpdate -ErrorAction Stop
        }
        
        if ($availableUpdates.Count -gt 0) {
            Write-ColoredLog "Найдено обновлений: $($availableUpdates.Count)" "INFO"
            Write-Host "`nДоступные обновления:" -ForegroundColor Cyan
            
            # Показываем детальный список обновлений
            foreach ($update in $availableUpdates) {
                $sizeStr = if ($update.Size) { " ($([math]::Round($update.Size / 1MB, 2)) МБ)" } else { "" }
                Write-Host "  • " -NoNewline -ForegroundColor Gray
                Write-Host "$($update.KB) " -NoNewline -ForegroundColor Yellow
                Write-Host "- $($update.Title)$sizeStr" -ForegroundColor Gray
            }
            Write-Host ""
            
            # Установка с полным выводом
            Write-ColoredLog "Установка обновлений..." "INFO"
            Write-Host ""
            
            # Счетчики для статистики
            $installedCount = 0
            $failedCount = 0
            
            # Устанавливаем каждое обновление
            for ($i = 0; $i -lt $availableUpdates.Count; $i++) {
                $update = $availableUpdates[$i]
                $progress = [math]::Round((($i + 1) / $availableUpdates.Count) * 100)
                
                Write-Host "[$($i + 1)/$($availableUpdates.Count)] " -NoNewline -ForegroundColor Cyan
                Write-Host "Установка: " -NoNewline -ForegroundColor White
                Write-Host "$($update.Title)" -ForegroundColor Gray
                
                try {
                    # Устанавливаем обновление без verbose для чистого вывода
                    $installResult = Install-WindowsUpdate -KBArticleID $update.KB -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
                    
                    Write-Host "  ✓ Установлено успешно" -ForegroundColor Green
                    $installedCount++
                } catch {
                    $errorMsg = $_.Exception.Message
                    
                    # Проверяем специфичные ошибки
                    if ($errorMsg -like "*0x80240022*" -or $errorMsg -like "*already installed*") {
                        Write-Host "  ✓ Уже установлено" -ForegroundColor DarkGreen
                        $installedCount++
                    } elseif ($errorMsg -like "*0x80070422*") {
                        Write-Host "  ✗ Ошибка: Служба Windows Update остановлена" -ForegroundColor Red
                        $failedCount++
                    } elseif ($errorMsg -like "*0x8024402C*" -or $errorMsg -like "*0x80072EE2*") {
                        Write-Host "  ✗ Ошибка: Проблема с подключением к серверу обновлений" -ForegroundColor Red
                        $failedCount++
                    } else {
                        Write-Host "  ✗ Ошибка: $errorMsg" -ForegroundColor Red
                        $failedCount++
                    }
                }
                
                # Показываем прогресс
                Write-Progress -Activity "Установка обновлений Windows" -Status "$progress% завершено" -PercentComplete $progress
            }
            
            Write-Progress -Activity "Установка обновлений Windows" -Completed
            
            Write-Host ""
            if ($failedCount -eq 0) {
                Write-ColoredLog "Все обновления установлены успешно ($installedCount из $($availableUpdates.Count))." "SUCCESS"
            } else {
                Write-ColoredLog "Установлено $installedCount из $($availableUpdates.Count) обновлений. Ошибок: $failedCount" "WARNING"
                $script:errorsCount += $failedCount
            }
            
            $script:updatesInstalled = $true
            $script:windowsUpdatesCount = $installedCount
            
            # Проверка необходимости перезагрузки
            if (Get-WURebootStatus -Silent) {
                $script:rebootRequired = $true
                Write-ColoredLog "Требуется перезагрузка для завершения обновлений." "WARNING"
            }
        } else {
            Write-ColoredLog "Система Windows уже обновлена." "SUCCESS"
        }
    } catch {
        Write-ColoredLog "Ошибка при обновлении Windows: $_" "ERROR"
    }
}

# Функция обновления приложений с полным выводом
function Update-Applications {
    Write-ColoredLog "ОБНОВЛЕНИЕ ПРИЛОЖЕНИЙ ЧЕРЕЗ WINGET" "TITLE"
    
    if (-not (Test-InternetConnection)) {
        Write-ColoredLog "Отсутствует интернет-соединение. Обновление приложений пропущено." "ERROR"
        return
    }
    
    try {
        # Проверка наличия winget несколькими способами
        $wingetPath = $null
        
        # Способ 1: через Get-Command
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $wingetPath = $wingetCmd.Source
        }
        
        # Способ 2: стандартный путь
        if (-not $wingetPath) {
            $standardPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
            if (Test-Path $standardPath) {
                $wingetPath = $standardPath
            }
        }
        
        # Способ 3: через where.exe
        if (-not $wingetPath) {
            $whereResult = where.exe winget 2>$null
            if ($whereResult) {
                $wingetPath = $whereResult[0]
            }
        }
        
        if (-not $wingetPath) {
            Write-ColoredLog "Winget не найден. Установите App Installer из Microsoft Store." "ERROR"
            return
        }
        
        # Обновление источников
        Write-ColoredLog "Обновление источников winget..." "INFO"
        $sourceUpdateProcess = Start-Process -FilePath $wingetPath `
                                            -ArgumentList "source", "update" `
                                            -NoNewWindow -PassThru -Wait
        
        if ($sourceUpdateProcess.ExitCode -eq 0) {
            Write-ColoredLog "Источники обновлены." "SUCCESS"
        } else {
            Write-ColoredLog "Предупреждение при обновлении источников (код: $($sourceUpdateProcess.ExitCode))" "WARNING"
        }
        
        # Показ списка доступных обновлений
        Write-ColoredLog "Проверка доступных обновлений приложений..." "INFO"
        Write-Host ""
        
        # Получаем список обновлений с прямым выводом
        Write-Host "Получение списка обновлений:" -ForegroundColor Cyan
        $updateCheckProcess = Start-Process -FilePath $wingetPath `
                                          -ArgumentList "upgrade" `
                                          -NoNewWindow -PassThru -Wait
        
        # Повторно запускаем для отображения списка
        & $wingetPath upgrade
        
        Write-Host ""
        
        # Анализируем, есть ли обновления
        $tempFile = [System.IO.Path]::GetTempFileName()
        $checkProcess = Start-Process -FilePath $wingetPath `
                                    -ArgumentList "upgrade" `
                                    -NoNewWindow `
                                    -RedirectStandardOutput $tempFile `
                                    -PassThru -Wait
        
        $updateCheckOutput = Get-Content $tempFile -Raw -Encoding UTF8
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        # Проверяем наличие обновлений
        $hasUpdates = $false
        $updateCount = 0
        
        if ($updateCheckOutput -match "(\d+)\s+(обновлени[еяй]|upgrades?\s+available|пакет[ов]?)") {
            $hasUpdates = $true
            $updateCount = [int]$Matches[1]
        } elseif ($updateCheckOutput -notmatch "(Нет доступных обновлений|No installed package|No applicable update|No upgrades available)") {
            # Подсчитываем строки с обновлениями
            $lines = $updateCheckOutput -split "`n"
            foreach ($line in $lines) {
                if ($line -match "^\S+\s+[\d\.\-]+\s+[\d\.\-<>]+\s+\S+") {
                    $updateCount++
                }
            }
            if ($updateCount -gt 0) {
                $hasUpdates = $true
            }
        }
        
        if ($hasUpdates) {
            $script:appUpdatesCount = $updateCount
            
            # Установка с полным выводом
            Write-ColoredLog "Установка $updateCount обновлений приложений..." "INFO"
            Write-Host "Это может занять несколько минут. Следите за прогрессом:" -ForegroundColor DarkGray
            Write-Host ""
            
            # Запускаем обновление с прямым выводом
            & $wingetPath upgrade --all --accept-source-agreements --accept-package-agreements --disable-interactivity --include-unknown
            
            Write-Host ""
            Write-ColoredLog "Обновление приложений завершено." "SUCCESS"
        } else {
            Write-ColoredLog "Все приложения актуальны." "SUCCESS"
        }
    } catch {
        Write-ColoredLog "Ошибка при обновлении приложений: $_" "ERROR"
        $script:errorsCount++
    }
}

# Функция проверки целостности (только если были обновления и требуется перезагрузка)
function Test-SystemIntegrity {
    if (-not $script:updatesInstalled -or -not $script:rebootRequired) {
        return
    }
    
    Write-ColoredLog "ПРОВЕРКА ЦЕЛОСТНОСТИ СИСТЕМЫ" "TITLE"
    Write-ColoredLog "Обновления требуют проверки целостности..." "INFO"
    
    try {
        # DISM CheckHealth сначала
        Write-ColoredLog "Быстрая проверка здоровья образа (DISM)..." "INFO"
        $dismCheck = Dism /Online /Cleanup-Image /CheckHealth
        Write-Host $dismCheck
        
        if ($dismCheck -match "corrupt" -or $dismCheck -match "repairable") {
            Write-ColoredLog "Обнаружены проблемы. Восстановление образа..." "WARNING"
            Dism /Online /Cleanup-Image /RestoreHealth | Out-Host
        }
        
        # SFC
        Write-ColoredLog "Запуск проверки системных файлов (SFC)..." "INFO"
        Write-ColoredLog "Это может занять 10-20 минут..." "INFO"
        sfc /scannow | Out-Host
        
        Write-ColoredLog "Проверка целостности завершена." "SUCCESS"
    } catch {
        Write-ColoredLog "Ошибка при проверке: $_" "ERROR"
        $script:errorsCount++
    }
}

# Функция очистки системы
function Clear-System {
    Write-ColoredLog "ОЧИСТКА СИСТЕМЫ" "TITLE"
    
    # Измерение места до очистки
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeBefore = [math]::Round($drive.Free / 1GB, 2)
    Write-ColoredLog "Свободно места до очистки: $freeBefore ГБ" "INFO"
    
    # Временные файлы
    Write-ColoredLog "Очистка временных файлов..." "INFO"
    Remove-FolderContent -Path $env:TEMP -Description "Временные файлы пользователя"
    Remove-FolderContent -Path "C:\Windows\Temp" -Description "Временные файлы Windows"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Temp" -Description "Локальные временные файлы"
    
    # Кэш обновлений Windows
    Write-ColoredLog "Очистка кэша обновлений Windows..." "INFO"
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
    Remove-FolderContent -Path "C:\Windows\SoftwareDistribution\Download" -Description "Кэш обновлений Windows"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name bits -ErrorAction SilentlyContinue
    
    # Корзина - всегда без вопросов
    Write-ColoredLog "Очистка корзины..." "INFO"
    try {
        # Сначала пробуем стандартный метод
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-ColoredLog "Корзина очищена." "SUCCESS"
    } catch {
        # Альтернативный метод через COM объект
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            $recycleBin.Items() | ForEach-Object { 
                Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue 
            }
            Write-ColoredLog "Корзина очищена (альтернативный метод)." "SUCCESS"
        } catch {
            Write-ColoredLog "Не удалось очистить корзину: $_" "WARNING"
        }
    }
    
    # Кэш браузеров - всегда без вопросов
    Write-ColoredLog "Очистка кэша браузеров..." "INFO"
    
    # Chrome
    $chromePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage"
    )
    foreach ($path in $chromePaths) {
        Remove-FolderContent -Path $path -Description "Кэш Chrome"
    }
    
    # Edge
    $edgePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage"
    )
    foreach ($path in $edgePaths) {
        Remove-FolderContent -Path $path -Description "Кэш Edge"
    }
    
    # Firefox
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
        Get-ChildItem -Path "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory | ForEach-Object {
            Remove-FolderContent -Path "$($_.FullName)\cache2" -Description "Кэш Firefox"
            Remove-FolderContent -Path "$($_.FullName)\startupCache" -Description "Startup кэш Firefox"
        }
    }
    
    # Yandex Browser
    $yandexPaths = @(
        "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\GPUCache"
    )
    foreach ($path in $yandexPaths) {
        Remove-FolderContent -Path $path -Description "Кэш Yandex Browser"
    }
    
    # Очистка логов событий
    Write-ColoredLog "Очистка системных логов..." "INFO"
    wevtutil el | ForEach-Object {
        wevtutil cl "$_" 2>$null
    }
    
    # Очистка кэша иконок
    Write-ColoredLog "Очистка кэша иконок..." "INFO"
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Description "Кэш эскизов"
    
    # DISM cleanup
    Write-ColoredLog "Очистка компонентов Windows (DISM)..." "INFO"
    Write-ColoredLog "Это может занять несколько минут..." "INFO"
    
    $dismProcess = Start-Process -FilePath "Dism.exe" `
                                -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" `
                                -Wait -PassThru -NoNewWindow
    
    if ($dismProcess.ExitCode -eq 0) {
        Write-ColoredLog "Очистка компонентов завершена успешно." "SUCCESS"
    } elseif ($dismProcess.ExitCode -eq 87) {
        Write-ColoredLog "Очистка компонентов не требуется." "INFO"
    } else {
        Write-ColoredLog "Очистка компонентов завершена с кодом: $($dismProcess.ExitCode)" "WARNING"
    }
    
    # Cleanmgr
    Write-ColoredLog "Запуск очистки диска..." "INFO"
    $sageset = 9999
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    
    # Настраиваем все категории для очистки
    $cleanupCategories = @(
        "Active Setup Temp Folders", "BranchCache", "Downloaded Program Files",
        "Internet Cache Files", "Memory Dump Files", "Old ChkDsk Files",
        "Previous Installations", "Recycle Bin", "Setup Log Files",
        "System error memory dump files", "System error minidump files",
        "Temporary Files", "Temporary Setup Files", "Thumbnail Cache",
        "Update Cleanup", "Upgrade Discarded Files", "User file versions",
        "Windows Error Reporting Archive Files", "Windows Error Reporting Queue Files",
        "Windows Error Reporting System Archive Files", "Windows Error Reporting System Queue Files",
        "Windows ESD installation files", "Windows Upgrade Log Files"
    )
    
    foreach ($category in $cleanupCategories) {
        $categoryPath = Join-Path $regPath $category
        if (Test-Path $categoryPath) {
            Set-ItemProperty -Path $categoryPath -Name "StateFlags$sageset" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Запускаем cleanmgr с таймаутом (максимум 5 минут)
    $cleanmgrProcess = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" -PassThru -NoNewWindow
    
    # Ждем завершения с таймаутом
    $timeout = 300 # 5 минут
    $cleanmgrProcess | Wait-Process -Timeout $timeout -ErrorAction SilentlyContinue
    
    if (-not $cleanmgrProcess.HasExited) {
        Write-ColoredLog "Очистка диска занимает слишком много времени. Продолжаем..." "WARNING"
        try {
            $cleanmgrProcess | Stop-Process -Force -ErrorAction SilentlyContinue
        } catch {}
    } elseif ($cleanmgrProcess.ExitCode -eq 0) {
        Write-ColoredLog "Очистка диска завершена." "SUCCESS"
    } else {
        Write-ColoredLog "Очистка диска завершена с кодом: $($cleanmgrProcess.ExitCode)" "WARNING"
    }
    
    # Windows.old - спрашиваем только если существует
    if (Test-Path "C:\Windows.old") {
        $oldSize = Get-FolderSize "C:\Windows.old"
        $oldSizeGb = [math]::Round($oldSize / 1024, 2)
        
        Write-Host ""
        Write-ColoredLog "Обнаружена папка Windows.old ($oldSizeGb ГБ)." "WARNING"
        Write-Host "Эта папка содержит файлы предыдущей версии Windows." -ForegroundColor DarkGray
        Write-Host "Удалить Windows.old? (" -NoNewline -ForegroundColor Yellow
        Write-Host "Y" -NoNewline -ForegroundColor Green
        Write-Host "/n, по умолчанию " -NoNewline -ForegroundColor Yellow
        Write-Host "Y" -NoNewline -ForegroundColor Green
        Write-Host " через 10 сек): " -NoNewline -ForegroundColor Yellow
        
        # Таймаут 10 секунд, по умолчанию - удаляем
        $timeoutSeconds = 10
        $startTime = Get-Date
        $response = ""
        
        # Очищаем буфер клавиатуры
        while ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
        }
        
        while ((Get-Date) -lt $startTime.AddSeconds($timeoutSeconds)) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Enter") {
                    $response = "Y"
                    break
                } elseif ($key.KeyChar -match "[YyДд]") {
                    $response = "Y"
                    Write-Host "Y" -ForegroundColor Green
                    break
                } elseif ($key.KeyChar -match "[NnНн]") {
                    $response = "N"
                    Write-Host "N" -ForegroundColor Red
                    break
                }
            }
            
            # Показываем обратный отсчет
            $remaining = $timeoutSeconds - [int]((Get-Date) - $startTime).TotalSeconds
            Write-Host "`r$(' ' * 50)`r" -NoNewline
            Write-Host "Удалить Windows.old? (Y/n, по умолчанию Y через $remaining сек): " -NoNewline -ForegroundColor Yellow
            
            Start-Sleep -Milliseconds 100
        }
        
        if ($response -eq "" -or $response -eq "Y") {
            if ($response -eq "") {
                Write-Host "Y" -ForegroundColor Green
            }
            Write-ColoredLog "Удаление Windows.old..." "INFO"
            
            try {
                # Используем более надежный метод удаления
                $dismCleanup = Start-Process -FilePath "Dism.exe" `
                                           -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" `
                                           -Wait -PassThru -NoNewWindow
                
                if (Test-Path "C:\Windows.old") {
                    # Если DISM не удалил, пробуем вручную
                    takeown /F "C:\Windows.old" /A /R /D Y 2>&1 | Out-Null
                    icacls "C:\Windows.old" /grant Administrators:F /T /C /Q 2>&1 | Out-Null
                    Remove-Item "C:\Windows.old" -Force -Recurse -ErrorAction SilentlyContinue
                }
                
                if (-not (Test-Path "C:\Windows.old")) {
                    Write-ColoredLog "Windows.old удалена." "SUCCESS"
                    $script:totalFreedSpace += $oldSize
                } else {
                    Write-ColoredLog "Не удалось полностью удалить Windows.old. Попробуйте очистку диска вручную." "WARNING"
                }
            } catch {
                Write-ColoredLog "Ошибка при удалении Windows.old: $_" "ERROR"
            }
        } else {
            Write-ColoredLog "Удаление Windows.old отменено пользователем." "INFO"
        }
    }
    
    # Дополнительные очистки для повышения эффективности
    
    # Очистка кэша Windows Store
    Write-ColoredLog "Очистка кэша Windows Store..." "INFO"
    try {
        # wsreset может открыть окно Store, поэтому используем альтернативный метод
        $storeCachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
        if (Test-Path $storeCachePath) {
            Remove-FolderContent -Path $storeCachePath -Description "Кэш Windows Store"
        }
        
        # Также очищаем кэш других компонентов Store
        $storePackages = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Name -like "*Microsoft.Store*" -or $_.Name -like "*Microsoft.WindowsStore*" }
        
        foreach ($package in $storePackages) {
            $cachePath = Join-Path $package.FullName "LocalCache"
            if (Test-Path $cachePath) {
                Remove-FolderContent -Path $cachePath -Description "Кэш $($package.Name)"
            }
        }
    } catch {
        Write-ColoredLog "Не удалось очистить кэш Windows Store: $_" "WARNING"
    }
    
    # Очистка prefetch
    Write-ColoredLog "Очистка prefetch..." "INFO"
    Remove-FolderContent -Path "C:\Windows\Prefetch" -Description "Файлы prefetch"
    
    # Очистка файлов доставки оптимизации
    Write-ColoredLog "Очистка кэша доставки оптимизации..." "INFO"
    Remove-FolderContent -Path "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" -Description "Кэш доставки оптимизации"
    
    # Очистка WER (Windows Error Reporting)
    Write-ColoredLog "Очистка отчетов об ошибках..." "INFO"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Windows\WER" -Description "Локальные отчеты об ошибках"
    Remove-FolderContent -Path "$env:ProgramData\Microsoft\Windows\WER" -Description "Системные отчеты об ошибках"
    
    # Очистка старых точек восстановления (оставляем только последние 2)
    Write-ColoredLog "Оптимизация точек восстановления..." "INFO"
    try {
        # Проверяем наличие vssadmin
        $vssadminPath = "$env:SystemRoot\System32\vssadmin.exe"
        if (Test-Path $vssadminPath) {
            $vssProcess = Start-Process -FilePath $vssadminPath `
                                       -ArgumentList "delete", "shadows", "/for=$env:SystemDrive", "/oldest", "/quiet" `
                                       -Wait -PassThru -NoNewWindow
            
            if ($vssProcess.ExitCode -eq 0) {
                Write-ColoredLog "Старые точки восстановления удалены." "SUCCESS"
            }
        }
    } catch {
        Write-ColoredLog "Не удалось оптимизировать точки восстановления: $_" "WARNING"
    }
    
    # Измерение места после очистки
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeAfter = [math]::Round($drive.Free / 1GB, 2)
    $freedGb = [math]::Round(($freeAfter - $freeBefore), 2)
    
    # Конвертируем освобожденное место из МБ в ГБ для итогового подсчета
    $totalFreedGb = [math]::Round($script:totalFreedSpace / 1024, 2)
    
    # Учитываем место, освобожденное cleanmgr и другими средствами
    $actualFreedGb = [math]::Max($freedGb, $totalFreedGb)
    $script:totalFreedSpace = $actualFreedGb * 1024 # Обратно в МБ для статистики
    
    Write-Host ""
    if ($actualFreedGb -gt 0) {
        Write-ColoredLog "Прямое освобождение: $freedGb ГБ" "SUCCESS"
        Write-ColoredLog "Всего очищено файлов: $totalFreedGb ГБ" "SUCCESS"
    } else {
        Write-ColoredLog "Дополнительное место не освобождено (система уже оптимизирована)" "INFO"
    }
}

# Основная логика
if (-not (Test-Administrator)) {
    Write-ColoredLog "Требуются права администратора!" "ERROR"
    Write-Host "`nЗапустите скрипт от имени администратора."
    Exit-Script 1
}

Clear-Host

# Проверка версии Windows
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$osVersion = $osInfo.Caption
$osBuild = $osInfo.BuildNumber

Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          АВТОМАТИЧЕСКОЕ ОБСЛУЖИВАНИЕ WINDOWS 11          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Система: $osVersion (Build $osBuild)" -ForegroundColor DarkGray
Write-Host "Время запуска: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# Проверка, что это Windows 11
if ($osBuild -lt 22000) {
    Write-ColoredLog "Внимание: Скрипт оптимизирован для Windows 11 (Build 22000+)" "WARNING"
    Write-ColoredLog "Текущая версия: Build $osBuild" "WARNING"
    Write-Host ""
}

# Создание точки восстановления
Write-ColoredLog "Создание точки восстановления..." "INFO"
if (New-SystemRestorePoint -Description "Auto Maintenance $(Get-Date -Format 'yyyy-MM-dd HH:mm')") {
    Write-Host ""
}

# Выполнение основных задач
Update-WindowsSystem
Update-Applications
Test-SystemIntegrity
Clear-System

# Итоговая статистика
Write-Host ""
Write-ColoredLog "ОБСЛУЖИВАНИЕ ЗАВЕРШЕНО" "TITLE"

$duration = (Get-Date) - $script:startTime
$durationStr = "{0:D2}:{1:D2}:{2:D2}" -f $duration.Hours, $duration.Minutes, $duration.Seconds

# Получаем финальную информацию о диске
$drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
$freeSpaceNow = [math]::Round($drive.Free / 1GB, 2)
$totalSize = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
$usedPercent = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 1)

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   ИТОГОВАЯ СТАТИСТИКА                    ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║ " -NoNewline -ForegroundColor Cyan
Write-Host "Время выполнения: " -NoNewline -ForegroundColor White
Write-Host "$durationStr" -NoNewline -ForegroundColor Green
Write-Host (" " * (39 - $durationStr.Length)) -NoNewline
Write-Host "║" -ForegroundColor Cyan

if ($script:windowsUpdatesCount -gt 0 -or $script:appUpdatesCount -gt 0) {
    Write-Host "║ " -NoNewline -ForegroundColor Cyan
    Write-Host "Установлено обновлений: " -NoNewline -ForegroundColor White
    $updatesStr = "Windows: $($script:windowsUpdatesCount), Приложения: $($script:appUpdatesCount)"
    Write-Host $updatesStr -NoNewline -ForegroundColor Green
    Write-Host (" " * (33 - $updatesStr.Length)) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
}

Write-Host "║ " -NoNewline -ForegroundColor Cyan
Write-Host "Освобождено места: " -NoNewline -ForegroundColor White
$freedStr = if ($script:totalFreedSpace -gt 0) {
    "$([math]::Round($script:totalFreedSpace / 1024, 2)) ГБ"
} else {
    "0 ГБ (система оптимизирована)"
}
Write-Host $freedStr -NoNewline -ForegroundColor Green
Write-Host (" " * (38 - $freedStr.Length)) -NoNewline
Write-Host "║" -ForegroundColor Cyan

Write-Host "║ " -NoNewline -ForegroundColor Cyan
Write-Host "Свободно на диске: " -NoNewline -ForegroundColor White
$freeStr = "$freeSpaceNow ГБ из $totalSize ГБ ($([math]::Round(100 - $usedPercent, 1))%)"
Write-Host $freeStr -NoNewline -ForegroundColor Yellow
Write-Host (" " * (38 - $freeStr.Length)) -NoNewline
Write-Host "║" -ForegroundColor Cyan

if ($script:errorsCount -gt 0) {
    Write-Host "║ " -NoNewline -ForegroundColor Cyan
    Write-Host "Ошибок при выполнении: " -NoNewline -ForegroundColor White
    Write-Host "$($script:errorsCount)" -NoNewline -ForegroundColor Red
    Write-Host (" " * (34 - "$($script:errorsCount)".Length)) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
}

Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Проверка необходимости перезагрузки
if ($script:rebootRequired) {
    Write-Host ""
    Write-Host "⚠ " -NoNewline -ForegroundColor Yellow
    Write-ColoredLog "Требуется перезагрузка для завершения установки обновлений!" "WARNING"
    Write-Host ""
    Write-Host "Перезагрузить компьютер сейчас? (y/N): " -NoNewline -ForegroundColor Yellow
    
    $response = Read-Host
    if ($response -match "^[YyДд]") {
        Write-ColoredLog "Компьютер будет перезагружен через 10 секунд..." "WARNING"
        Write-ColoredLog "Нажмите Ctrl+C для отмены" "INFO"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-ColoredLog "Перезагрузка отложена. Обязательно перезагрузите компьютер позже!" "WARNING"
    }
}

# Завершение работы
Exit-Script 0