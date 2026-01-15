# Улучшенный скрипт для автоматического обновления и очистки Windows
# Версия 4.0 - Оптимизированная на основе анализа предыдущих версий
# Запускается автоматически: Обновление -> Проверка (если нужно) -> Очистка
# Требуется запуск с правами администратора

# Установка кодировки для корректного отображения русского текста
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Глобальные переменные
$script:rebootRequired = $false
$script:updatesInstalled = $false
$script:totalFreedSpace = 0

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
        Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
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
        return $false
    }
}

# Функция обновления Windows с деталями
function Update-WindowsSystem {
    Write-ColoredLog "ОБНОВЛЕНИЕ WINDOWS" "TITLE"
    
    if (-not (Test-InternetConnection)) {
        Write-ColoredLog "Отсутствует интернет-соединение. Обновление Windows пропущено." "ERROR"
        return
    }
    
    # Проверка службы wuauserv
    $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-ColoredLog "Служба Windows Update (wuauserv) не найдена!" "ERROR"
        return
    }
    if ($service.Status -ne "Running") {
        Write-ColoredLog "Служба wuauserv не запущена. Попытка запуска..." "WARNING"
        try {
            Start-Service wuauserv -ErrorAction Stop
            Write-ColoredLog "Служба запущена." "SUCCESS"
        } catch {
            Write-ColoredLog "Не удалось запустить службу: $_" "ERROR"
            return
        }
    }
    
    try {
        # Установка/импорт PSWindowsUpdate
        if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-ColoredLog "Установка модуля PSWindowsUpdate..." "INFO"
            Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop
        
        # Автоматическая регистрация Microsoft Update, если не зарегистрирован
        $muService = Get-WUServiceManager | Where-Object { $_.Name -eq "Microsoft Update" }
        if (-not $muService) {
            Write-ColoredLog "Регистрация сервиса Microsoft Update..." "INFO"
            Add-WUServiceManager -MicrosoftUpdate -Confirm:$false -ErrorAction Stop
            Write-ColoredLog "Сервис Microsoft Update зарегистрирован." "SUCCESS"
        }
        
        # Получение и показ списка обновлений
        Write-ColoredLog "Поиск доступных обновлений..." "INFO"
        $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
        
        if ($availableUpdates.Count -gt 0) {
            Write-ColoredLog "Найдено обновлений: $($availableUpdates.Count)" "INFO"
            Write-Host "`nДоступные обновления:" -ForegroundColor Cyan
            $availableUpdates | ForEach-Object {
                $sizeStr = if ($_.Size) { " ($([math]::Round($_.Size / 1MB, 2)) МБ)" } else { "" }
                Write-Host "  • $($_.KB) - $($_.Title)$sizeStr" -ForegroundColor Gray
            }
            Write-Host ""
            
            # Установка с деталями
            Write-ColoredLog "Установка обновлений..." "INFO"
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose -ErrorAction Stop
            
            $script:updatesInstalled = $true
            Write-ColoredLog "Обновления Windows установлены." "SUCCESS"
            
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
        # Проверка наличия winget
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-ColoredLog "Winget не найден. Установите из Microsoft Store." "ERROR"
            return
        }
        
        # Обновление источников
        Write-ColoredLog "Обновление источников winget..." "INFO"
        winget source update
        
        # Показ списка доступных обновлений
        Write-ColoredLog "Доступные обновления приложений:" "INFO"
        winget upgrade
        
        # Установка с полным выводом в консоль
        Write-ColoredLog "Установка обновлений..." "INFO"
        winget upgrade --all --accept-source-agreements --accept-package-agreements --disable-interactivity --include-unknown
        
        Write-ColoredLog "Обновление приложений завершено." "SUCCESS"
    } catch {
        Write-ColoredLog "Ошибка при обновлении приложений: $_" "ERROR"
    }
}

# Функция проверки целостности (только если обновления были установлены и требуется reboot)
function Test-SystemIntegrity {
    if (-not $script:updatesInstalled -or -not $script:rebootRequired) {
        return
    }
    
    Write-ColoredLog "ПРОВЕРКА ЦЕЛОСТНОСТИ СИСТЕМЫ" "TITLE"
    Write-ColoredLog "Обновления требуют проверки. Запуск DISM и SFC..." "INFO"
    
    try {
        # DISM CheckHealth сначала (быстрый)
        Write-ColoredLog "Проверка здоровья образа (DISM)..." "INFO"
        $dismCheck = Dism /Online /Cleanup-Image /CheckHealth
        Write-Host $dismCheck
        
        if ($dismCheck -match "corrupt" -or $dismCheck -match "repairable") {
            Write-ColoredLog "Обнаружены проблемы. Восстановление образа..." "WARNING"
            Dism /Online /Cleanup-Image /RestoreHealth
        }
        
        # SFC
        Write-ColoredLog "Запуск SFC /scannow..." "INFO"
        sfc /scannow
        
        Write-ColoredLog "Проверка завершена." "SUCCESS"
    } catch {
        Write-ColoredLog "Ошибка при проверке: $_" "ERROR"
    }
}

# Функция очистки системы
function Clear-System {
    Write-ColoredLog "ОЧИСТКА СИСТЕМЫ" "TITLE"
    
    # Измерение места до
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
    Remove-FolderContent -Path "C:\Windows\SoftwareDistribution" -Description "Кэш обновлений Windows"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name bits -ErrorAction SilentlyContinue
    
    # Корзина
    Write-ColoredLog "Очистка корзины..." "INFO"
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-ColoredLog "Корзина очищена." "SUCCESS"
    } catch {
        $shell = New-Object -ComObject Shell.Application
        $shell.Namespace(0xA).Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    # Кэш браузеров
    Write-ColoredLog "Очистка кэша браузеров..." "INFO"
    # Chrome
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -Description "Кэш Chrome"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" -Description "Code Cache Chrome"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache" -Description "GPUCache Chrome"
    
    # Edge
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" -Description "Кэш Edge"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache" -Description "Code Cache Edge"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache" -Description "GPUCache Edge"
    
    # Firefox
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
        Get-ChildItem -Path "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory | ForEach-Object {
            Remove-FolderContent -Path "$($_.FullName)\cache2" -Description "Кэш Firefox"
        }
    }
    
    # Yandex Browser (если установлен)
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache" -Description "Кэш Yandex"
    Remove-FolderContent -Path "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Code Cache" -Description "Code Cache Yandex"
    
    # DISM cleanup
    Write-ColoredLog "Очистка компонентов Windows (DISM)..." "INFO"
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    
    # Cleanmgr
    Write-ColoredLog "Запуск очистки диска (cleanmgr)..." "INFO"
    $sageset = 65535
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    Get-ChildItem $regPath | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "StateFlags$sageset" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    cleanmgr.exe /sagerun:$sageset
    
    # Windows.old с вопросом
    if (Test-Path "C:\Windows.old") {
        $oldSize = Get-FolderSize "C:\Windows.old"
        Write-ColoredLog "Обнаружена папка Windows.old ($oldSize МБ)." "WARNING"
        $confirm = Read-Host "Удалить Windows.old? (y/n, по умолчанию y)"
        if ($confirm -eq '' -or $confirm -eq 'y') {
            takeown /F "C:\Windows.old" /A /R /D Y | Out-Null
            icacls "C:\Windows.old" /grant Administrators:F /T /C | Out-Null
            Remove-Item "C:\Windows.old" -Force -Recurse -ErrorAction SilentlyContinue
            Write-ColoredLog "Windows.old удалена." "SUCCESS"
            $script:totalFreedSpace += $oldSize
        } else {
            Write-ColoredLog "Удаление Windows.old отменено." "INFO"
        }
    }
    
    # Измерение места после
    $drive = Get-PSDrive -Name $env:SystemDrive.Replace(':', '')
    $freeAfter = [math]::Round($drive.Free / 1GB, 2)
    $freedGb = [math]::Round(($freeAfter - $freeBefore), 2)
    
    Write-ColoredLog "Освобождено места: $freedGb ГБ" "SUCCESS"
}

# Основной запуск
if (-not (Test-Administrator)) {
    Write-ColoredLog "Требуются права администратора!" "ERROR"
    Exit 1
}

Clear-Host
Write-ColoredLog "НАЧАЛО АВТОМАТИЧЕСКОГО ОБСЛУЖИВАНИЯ" "TITLE"

New-SystemRestorePoint -Description "Auto Maintenance $(Get-Date -Format 'yyyy-MM-dd')"

Update-WindowsSystem
Update-Applications
Test-SystemIntegrity
Clear-System

Write-ColoredLog "ОБСЛУЖИВАНИЕ ЗАВЕРШЕНО" "TITLE"

if ($script:rebootRequired) {
    $reboot = Read-Host "Требуется перезагрузка. Перезагрузить сейчас? (y/n)"
    if ($reboot -eq 'y') {
        Restart-Computer
    }
}

Write-Host "`nНажмите любую клавишу для выхода..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null