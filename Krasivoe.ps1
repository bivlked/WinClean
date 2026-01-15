<#
.SYNOPSIS
    Krasivoe Dream Script — v1.4 (UI полировка)
.DESCRIPTION
    Финальный релиз с косметикой:
      • Динамический прогресс‑бар (0‑100 %) через переменную $step.
      • Цвет итогового блока: зелёный — всё чисто, жёлтый — warnings, красный — errors.
      • Параметр -Quiet (приглушает всё, кроме финального отчёта и ошибок).
      • Freed‑bytes выводится по категориям + суммарно.
.NOTES
    Author: Иван
    Date: 2025‑07‑31
    Requires: PowerShell 7.1+
#>

#Requires -Version 7.1
using namespace System.Threading

param(
    [switch]$SkipUpdates,
    [switch]$SkipRestore,
    [switch]$Silent,
    [switch]$Quiet,
    [switch]$ReportOnly
)

#region Global Variables
[long]      $script:TotalFreedBytes     = 0
[hashtable] $script:FreedByCategory     = @{}
[int]       $script:WindowsUpdatesCount = 0
[int]       $script:AppUpdatesCount     = 0
[int]       $script:WarningsCount       = 0
[int]       $script:ErrorsCount         = 0
[bool]      $script:RebootRequired      = $false
[datetime]  $script:StartTime           = Get-Date
[int]       $script:Step               = 0
#endregion

#region Logging & Progress
function Write-ColoredLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR','FINAL')]$Level='INFO',
        [switch]$Force
    )
    if ($Silent) { return }
    if ($Quiet -and -not $Force -and $Level -notin 'ERROR','FINAL') { return }
    $c=@{INFO='Gray';SUCCESS='Green';WARNING='Yellow';ERROR='Red';FINAL='Green'}
    if ($Level -eq 'FINAL') {
        if ($script:ErrorsCount -gt 0) { $c['FINAL']='Red' }
        elseif ($script:WarningsCount -gt 0) { $c['FINAL']='Yellow' }
    }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] [$Level] $Message" -ForegroundColor $c[$Level]
}

function Advance-Progress {
    param([string]$Activity)
    $script:Step += 10
    if (-not $Silent) { Write-Progress -Activity $Activity -PercentComplete $script:Step }
}
#endregion

#region Preconditions & Init
function Test-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) { Write-ColoredLog 'Запустите скрипт от имени администратора.' 'ERROR' -Force; exit 1 }
}
function Validate-Environment { if ($PSVersionTable.PSVersion -lt [Version]'7.1') { Write-ColoredLog 'Требуется PowerShell 7.1 или выше.' 'ERROR' -Force; exit 1 } }
function Init-Globals { $global:KrasivoeLogPath = Join-Path $env:TEMP "KrasivoeDream_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"; Write-ColoredLog '==== Старт Krasivoe Dream Script ====' 'INFO' -Force; Write-ColoredLog "Лог будет сохранён: $global:KrasivoeLogPath" 'INFO' -Force }
#endregion

#region Helper Functions
function Add-FreedBytes { param([string]$Category,[long]$Bytes) if ($Bytes -le 0) { return }; [Interlocked]::Add([ref]$script:TotalFreedBytes,$Bytes)|Out-Null; if (-not $script:FreedByCategory.ContainsKey($Category)) { $script:FreedByCategory[$Category]=0 }; $script:FreedByCategory[$Category]+=$Bytes }
function Get-FolderSize { param([string]$Path) if (-not (Test-Path -LiteralPath $Path)) {return 0}; try { (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch {0} }
function Remove-FolderContent {
    param([string]$Path,[string]$Category)
    if ($ReportOnly) { return }
    if (-not (Test-Path -LiteralPath $Path)) { Write-ColoredLog "Каталог $Path не найден." 'INFO'; return }
    $before=Get-FolderSize $Path
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    $freed=$before-(Get-FolderSize $Path)
    Add-FreedBytes $Category $freed
    Write-ColoredLog "$Category — освобождено: $([math]::Round($freed/1MB,2)) МБ" 'SUCCESS'
}
#endregion

#region Core Modules (unchanged code from v1.3 but with Advance‑Progress calls)
# *Restore Point*
function New-SystemRestorePoint {
    if ($SkipRestore) { Write-ColoredLog 'Пропуск создания точки восстановления.' 'INFO'; return }
    Write-ColoredLog 'Создание точки восстановления...' 'INFO'; Advance-Progress 'Restore Point'
    $cmd = "Checkpoint-Computer -Description 'KrasivoeDream' -RestorePointType MODIFY_SETTINGS"
    try { if ($ReportOnly){return}; Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -Command $cmd" -WindowStyle Hidden -Wait; Write-ColoredLog 'Точка восстановления создана.' 'SUCCESS' } catch { Write-ColoredLog 'Не удалось создать точку восстановления.' 'WARNING'; $script:WarningsCount++ }
}

function Invoke-StorageSense {
    Write-ColoredLog 'Запуск Storage Sense...' 'INFO'; Advance-Progress 'Storage Sense'
    $task="\\Microsoft\\Windows\\DiskCleanup\\StorageSense"; if ((schtasks /Query /TN $task 2>$null) -and $LASTEXITCODE -eq 0) { if (-not $ReportOnly){ schtasks /Run /TN $task | Out-Null; Start-Sleep 15 }; Write-ColoredLog 'Storage Sense завершён.' 'SUCCESS' } else { Write-ColoredLog 'Задача Storage Sense отсутствует.' 'INFO'; throw }
}

function Invoke-CleanMgr { Write-ColoredLog 'Запуск CleanMgr...' 'INFO'; Advance-Progress 'CleanMgr'; if ($ReportOnly){return}; try { Start-Process -FilePath "$env:SystemRoot\System32\cleanmgr.exe" -ArgumentList '/autoclean' -Wait -WindowStyle Hidden } catch { Write-ColoredLog 'Ошибка CleanMgr.' 'WARNING'; $script:WarningsCount++ } }

function Update-Windows {
    if ($SkipUpdates) { Write-ColoredLog 'Пропуск обновлений Windows.' 'INFO'; return }
    Write-ColoredLog 'Поиск и установка обновлений Windows...' 'INFO'; Advance-Progress 'Windows Update'
    try { if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)){ Install-Module PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false|Out-Null }; Import-Module PSWindowsUpdate -ErrorAction Stop; $upd=Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue; if ($upd){ $script:WindowsUpdatesCount=$upd.Count; if (-not $ReportOnly){ Install-WindowsUpdate -AcceptAll -MicrosoftUpdate -AutoReboot:$false -IgnoreReboot|Out-Null; if (Get-WURebootStatus){$script:RebootRequired=$true} }; Write-ColoredLog "Установлено обновлений Windows: $($script:WindowsUpdatesCount)" 'SUCCESS' } else { Write-ColoredLog 'Обновлений Windows нет.' 'INFO' } } catch { Write-ColoredLog 'Ошибка Windows Update.' 'WARNING'; $script:WarningsCount++ }
}

function Update-Apps {
    if ($SkipUpdates){ Write-ColoredLog 'Пропуск winget обновлений.' 'INFO'; return }
    Write-ColoredLog 'Обновление приложений (winget)...' 'INFO'; Advance-Progress 'winget'
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)){ Write-ColoredLog 'winget не найден.' 'WARNING'; $script:WarningsCount++; return }
    try { if (-not $ReportOnly){ $output=winget upgrade --all --silent --accept-source-agreements --accept-package-agreements --include-unknown 2>&1 }; $count=($output|Select-String 'Successfully installed'|Measure-Object).Count; $script:AppUpdatesCount=$count; Write-ColoredLog "Обновлено приложений: $count" ($count -gt 0 ? 'SUCCESS':'INFO') } catch { Write-ColoredLog 'Ошибка winget.' 'WARNING'; $script:WarningsCount++ }
}
#endregion

#region Clear Caches & Logs (unchanged from v1.3 with Advance)
function Clear-VariousCaches { Write-ColoredLog 'Очистка кэшей...' 'INFO'; Advance-Progress 'Caches'; $paths=@("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache","$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache","$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache","$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Cache","$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache","$env:ProgramData\USOShared\Logs","$env:ProgramData\Microsoft\Windows\WER","$env:SystemRoot\SoftwareDistribution\Download","$env:SystemRoot\Prefetch","$env:SystemDrive\ProgramData\Microsoft\Windows\DeliveryOptimization"); foreach($p in $paths){ Remove-FolderContent $p 'Cache' } }

function Clear-EventLogs { Write-ColoredLog 'Очистка журналов событий...' 'INFO'; Advance-Progress 'Event Logs'; if ($ReportOnly){return}; try { wevtutil el | Where-Object { $_ -notmatch 'Analytic' -and $_ -notmatch 'Debug' } | ForEach-Object { try { wevtutil cl $_ } catch { $script:WarningsCount++; Write-ColoredLog "Не удалось очистить $_" 'WARNING' } }; Write-ColoredLog 'Журналы событий очищены.' 'SUCCESS' } catch { Write-ColoredLog 'Ошибка очистки журналов.' 'WARNING'; $script:WarningsCount++ } }
#endregion

#region Statistics & Main
function Write-FinalStatistics {
    $elapsed = (Get-Date) - $script:StartTime
    $gb = [math]::Round($script:TotalFreedBytes / 1GB, 2)
    Write-ColoredLog '------- Итоговый отчёт -------' 'FINAL' -Force

    foreach ($k in $script:FreedByCategory.Keys) {
        $mb = [math]::Round($script:FreedByCategory[$k] / 1MB, 2)
        Write-ColoredLog "• $($k): $mb МБ" 'FINAL' -Force
    }

    Write-ColoredLog "Всего освобождено: $($gb) ГБ" 'FINAL' -Force
    Write-ColoredLog "Обновления Windows: $($script:WindowsUpdatesCount) | Приложений: $($script:AppUpdatesCount)" 'FINAL' -Force
    Write-ColoredLog "Warnings: $($script:WarningsCount) | Errors: $($script:ErrorsCount) | Время: $([int]$elapsed.TotalMinutes) мин." 'FINAL' -Force

    if ($script:RebootRequired -and -not $ReportOnly) {
        Write-ColoredLog 'Для завершения установки обновлений требуется перезагрузка.' 'FINAL' -Force
    }
}

#endregion

#region Main
function Run-KrasivoeDream {
    Test-Administrator
    Validate-Environment
    Init-Globals
    try {
        New-SystemRestorePoint
        try { Invoke-StorageSense } catch { Invoke-CleanMgr }
        Remove-FolderContent $env:TEMP 'Temp'
        Update-Windows
        Update-Apps
        Clear-VariousCaches
        Clear-EventLogs
    }
    catch {
        $script:ErrorsCount++
        Write-ColoredLog $_.Exception.Message 'ERROR' -Force
    }
    finally {
        Write-FinalStatistics
    }
}

if ($MyInvocation.InvocationName -ne '.') { Run-KrasivoeDream }
#endregion
