# Скрипт для комплексного обновления и очистки Windows
# Требуется запуск с правами администратора

# Функция для проверки прав администратора
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $user
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Функция для логирования
function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    Write-Host $logMessage
    
    # Логирование в файл (опционально)
    # $logPath = "$env:USERPROFILE\Documents\WindowsUpdateLog.txt"
    # Add-Content -Path $logPath -Value $logMessage
}

# Проверка прав администратора
if (-not (Test-Administrator)) {
    Write-Log "Скрипт требует запуска с правами администратора. Пожалуйста, запустите PowerShell от имени администратора." "ERROR"
    Write-Host "Нажмите любую клавишу для выхода..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    Exit 1
}

Write-Log "Начало выполнения скрипта обновления и очистки Windows..."

try {
    # Проверяем наличие модуля PSWindowsUpdate и устанавливаем его, если не установлен
    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Установка модуля PSWindowsUpdate..."
        Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -ErrorAction Stop
    }

    # Загружаем модуль PSWindowsUpdate в текущую сессию PowerShell
    Import-Module PSWindowsUpdate -ErrorAction Stop
    Write-Log "Модуль PSWindowsUpdate успешно загружен"
    
    # Получаем информацию о доступных обновлениях
    Write-Log "Получение списка доступных обновлений Windows..."
    $availableUpdates = Get-WindowsUpdate -ErrorAction Stop
    
    if ($availableUpdates.Count -gt 0) {
        Write-Log "Найдено $($availableUpdates.Count) доступных обновлений"
        
        # Устанавливаем обновления Windows, игнорируя автоматическую перезагрузку
        Write-Log "Установка обновлений Windows..."
        $updates = Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
        
        # Проверяем установку необязательных обновлений
        $optionalUpdates = Get-WindowsUpdate -MicrosoftUpdate -Category "Optional" -ErrorAction SilentlyContinue
        if ($optionalUpdates.Count -gt 0) {
            Write-Log "Найдено $($optionalUpdates.Count) необязательных обновлений"
            Install-WindowsUpdate -AcceptAll -IgnoreReboot -MicrosoftUpdate -Category "Optional" -ErrorAction SilentlyContinue | Out-Null
        }
    } else {
        Write-Log "Обновления Windows не найдены или система полностью обновлена"
    }

    # Проверяем, требуется ли перезагрузка после установки обновлений Windows
    $rebootRequired = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $rebootRequired = $true
        Write-Log "Обновления Windows установлены. Некоторые обновления требуют перезагрузки." "WARNING"
    } else {
        Write-Log "Обновления Windows установлены. Перезагрузка не требуется."
    }

    # Обновляем все приложения через winget с автоматическим принятием лицензий
    Write-Log "Установка обновлений приложений через winget..."
    try {
        $wingetResult = winget upgrade --all --accept-source-agreements --accept-package-agreements
        Write-Log "Обновление приложений через winget завершено."
    } catch {
        Write-Log "Произошла ошибка при обновлении приложений через winget: $_" "ERROR"
    }

    # Очистка системы
    Write-Log "Начало процесса очистки системы..."

    # 1. Очистка временных файлов Windows
    Write-Log "Очистка временных файлов Windows..."
    Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue

    # 2. Очистка кэша SoftwareDistribution (файлы обновлений Windows)
    Write-Log "Очистка кэша SoftwareDistribution..."
    if ((Get-Service -Name wuauserv).Status -eq 'Running') {
        Stop-Service -Name wuauserv -Force
        $wuServiceStopped = $true
    }
    Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Force -Recurse -ErrorAction SilentlyContinue
    if ($wuServiceStopped) {
        Start-Service -Name wuauserv
    }

    # 3. Очистка корзины
    Write-Log "Очистка корзины..."
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.Namespace(0xA).Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
    } catch {
        Write-Log "Альтернативная очистка корзины..." "INFO"
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }
        foreach ($drive in $drives) {
            $recycleBin = "$($drive.Name)\`$Recycle.Bin"
            if (Test-Path $recycleBin) {
                Remove-Item "$recycleBin\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    # 4. Очистка кэша браузеров
    Write-Log "Очистка кэша браузеров..."
    # Chrome
    if (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache") {
        Remove-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
    
    # Edge
    if (Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache") {
        Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
    
    # Firefox
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") {
        Get-ChildItem -Path "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory | ForEach-Object {
            Remove-Item -Path "$($_.FullName)\cache2\*" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    # 5. Запускаем DISM для очистки компонентов и сброса базы обновлений
    Write-Log "Запуск DISM для очистки компонентов Windows..."
    try {
        $dismProcess = Start-Process -FilePath "Dism.exe" -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -NoNewWindow -PassThru
        if ($dismProcess.ExitCode -eq 0) {
            Write-Log "Очистка компонентов Windows завершена успешно."
        } else {
            Write-Log "DISM завершился с кодом ошибки $($dismProcess.ExitCode)" "WARNING"
        }
    } catch {
        Write-Log "Ошибка при выполнении DISM: $_" "ERROR"
    }

    # 6. Запуск встроенной утилиты очистки диска (аналогично нажатию "Очистить системные файлы")
    Write-Log "Запуск встроенной утилиты очистки диска..."
    
    # Создаем файл настроек для cleanmgr (очищаем все доступные категории)
    $sageset = 65535  # Все категории
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    
    try {
        Get-ChildItem $regPath -ErrorAction Stop | ForEach-Object {
            New-ItemProperty -Path "$($_.PSPath)" -Name "StateFlags$sageset" -Value 2 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Запускаем cleanmgr с полной очисткой
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$sageset" -Wait -NoNewWindow
        Write-Log "Очистка диска завершена."
    } catch {
        Write-Log "Ошибка при настройке или запуске cleanmgr: $_" "ERROR"
        
        # Альтернативный вариант запуска cleanmgr без предварительной настройки
        Write-Log "Пробуем альтернативный метод очистки диска..." "INFO"
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/d $($env:SystemDrive.Replace(':', ''))" -Wait -NoNewWindow
    }

    # Завершение работы скрипта и предложение перезагрузки
    Write-Log "Все операции обновления и очистки выполнены успешно."
    
    if ($rebootRequired) {
        Write-Host "`nТребуется перезагрузка для завершения установки обновлений."
        $reboot = Read-Host "Перезагрузить компьютер сейчас? (y/n)"
        if ($reboot -eq 'y') {
            Write-Log "Выполняется перезагрузка компьютера..."
            Restart-Computer
        } else {
            Write-Log "Перезагрузка отложена. Не забудьте перезагрузить компьютер позже для завершения установки обновлений." "WARNING"
        }
    } else {
        Write-Host "`nХотите выполнить перезагрузку компьютера для применения всех изменений?"
        $reboot = Read-Host "Перезагрузить компьютер сейчас? (y/n)"
        if ($reboot -eq 'y') {
            Write-Log "Выполняется перезагрузка компьютера..."
            Restart-Computer
        }
    }
} catch {
    Write-Log "Произошла критическая ошибка: $_" "ERROR"
    Write-Log "Трассировка стека: $($_.ScriptStackTrace)" "ERROR"
}

Write-Log "Работа скрипта завершена."
Write-Host "`nНажмите любую клавишу для выхода..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
