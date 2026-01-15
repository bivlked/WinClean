# Проверяем наличие модуля PSWindowsUpdate и устанавливаем его, если не установлен
if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
   Write-Host "Установка модуля PSWindowsUpdate..."
   Install-Module PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck
}

# Загружаем модуль PSWindowsUpdate в текущую сессию PowerShell
Import-Module PSWindowsUpdate

# Устанавливаем обновления Windows, игнорируя автоматическую перезагрузку
Write-Host "Поиск и установка обновлений Windows..."
$updates = Install-WindowsUpdate -AcceptAll -IgnoreReboot

# Проверяем, требуется ли перезагрузка после установки обновлений Windows
if ($updates.RebootRequired) {
   Write-Host "Обновления Windows установлены. Некоторые обновления требуют перезагрузки."
   Write-Host "Сначала обновим приложения..."
   
   # Обновляем все приложения через winget с автоматическим принятием лицензий
   Write-Host "Установка обновлений приложений..."
   winget upgrade --all --accept-source-agreements --accept-package-agreements
   
   # Предлагаем выполнить перезагрузку
   Write-Host "Все обновления установлены. Теперь можно перезагрузить компьютер."
   $reboot = Read-Host "Перезагрузить компьютер сейчас? (y/n)"
   if ($reboot -eq 'y') {
       Restart-Computer
   }
}
else {
   Write-Host "Обновления Windows установлены. Перезагрузка не требуется."
   Write-Host "Обновляем приложения..."
   
   # Обновляем все приложения через winget с автоматическим принятием лицензий
   winget upgrade --all --accept-source-agreements --accept-package-agreements
   
   # Предлагаем выполнить очистку компонентов Windows
   Write-Host "`nВсе обновления установлены. Хотите выполнить очистку компонентов Windows?"
   Write-Host "Это может занять некоторое время, но поможет освободить место на диске."
   $cleanup = Read-Host "Выполнить очистку? (y/n)"
   if ($cleanup -eq 'y') {
       Write-Host "Выполняется очистка компонентов Windows..."
       # Запускаем DISM для очистки компонентов и сброса базы обновлений
       Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
       Write-Host "Очистка завершена."
   }
}

Write-Host "`nРабота скрипта завершена."
