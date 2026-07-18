#Requires -Version 7.1

<#
.SYNOPSIS
    Nightly stand matrix: runs WinClean stand tests on all configured VMs and
    reports the verdict to Telegram
.DESCRIPTION
    Designed to run via cron ON the Proxmox host (configs with SshHost = 'local'),
    but works from the workstation too. For every stand.config*.json (except the
    example) it runs Invoke-StandTest.ps1, collects verdict + stats from the run
    artifacts, sends a single Telegram summary and prunes old results.

    Telegram credentials come from an env file (default /root/.winclean-stand.env):
        BOT_TOKEN=...
        CHAT_ID=...
        TG_PROXIES=socks5h://172.16.1.210:1080,socks5h://172.16.1.210:11080
    Delivery tries direct first, then each proxy (same pattern as the vpn-gw
    healthcheck - direct Telegram is intermittently unavailable).
.PARAMETER Mode
    Test mode passed to Invoke-StandTest (default: Full - real cleanup, no updates)
.PARAMETER Source
    Script source passed to Invoke-StandTest (default: main - tests published code)
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Full', 'FullWithUpdates')]
    [string]$Mode = 'Full',

    [ValidateSet('local', 'main', 'release')]
    [string]$Source = 'main',

    [string]$TelegramEnvPath = '/root/.winclean-stand.env',
    [int]$RetentionDays = 14
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StandCommon.ps1')

$resultsRoot = Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
$logFile = Join-Path $resultsRoot 'nightly.log'

function Write-NightlyLog {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Send-Telegram {
    param([string]$Text)

    if (-not (Test-Path $TelegramEnvPath)) {
        Write-NightlyLog "Telegram env not found ($TelegramEnvPath) - report not sent"
        return $false
    }
    $env = @{}
    foreach ($line in (Get-Content $TelegramEnvPath)) {
        if ($line -match '^\s*([A-Z_]+)\s*=\s*"?([^"]*?)"?\s*$') { $env[$Matches[1]] = $Matches[2].Trim() }
    }
    if (-not $env.BOT_TOKEN -or -not $env.CHAT_ID) {
        Write-NightlyLog "BOT_TOKEN/CHAT_ID missing in $TelegramEnvPath - report not sent"
        return $false
    }

    $transports = @('') + @(($env.TG_PROXIES -split ',') | Where-Object { $_ })
    foreach ($proxy in $transports) {
        $curlArgs = @('-sS', '--max-time', '10')
        if ($proxy) { $curlArgs += @('--proxy', $proxy.Trim()) }
        $curlArgs += @(
            '-X', 'POST', "https://api.telegram.org/bot$($env.BOT_TOKEN)/sendMessage",
            '-d', "chat_id=$($env.CHAT_ID)",
            '--data-urlencode', "text=$Text",
            '-o', '/dev/null', '-w', '%{http_code}'
        )
        $code = & curl @curlArgs 2>$null
        if ($code -eq '200') {
            Write-NightlyLog "Telegram delivered via $(if ($proxy) { $proxy } else { 'direct' })"
            return $true
        }
    }
    Write-NightlyLog "Telegram delivery FAILED via all transports"
    return $false
}

# --- Discover the stand matrix ---
$configs = Get-ChildItem -Path $PSScriptRoot -Filter 'stand.config*.json' |
    Where-Object { $_.Name -ne 'stand.config.example.json' } | Sort-Object Name

if (-not $configs) {
    Write-NightlyLog "No stand configs found - nothing to do"
    exit 1
}

Write-NightlyLog "Nightly matrix start: Mode=$Mode Source=$Source, $($configs.Count) stand(s)"
$summaryLines = @()
$anyFailed = $false

foreach ($configFile in $configs) {
    # Per-stand exception boundary: one broken stand/config must not abort the
    # matrix or prevent the final Telegram report
    try {
        $cfg = Get-StandConfig -ConfigPath $configFile.FullName
        $label = if ($cfg.PSObject.Properties.Name -contains 'Label' -and $cfg.Label) { $cfg.Label } else { $configFile.BaseName }

        # A configured stand whose VM is unreachable is a FAILURE, not a quiet skip
        $statusOut = Invoke-Pve -Config $cfg -Command "qm status $($cfg.StandVmId)" -AllowFail
        if ($LASTEXITCODE -ne 0) {
            $anyFailed = $true
            Write-NightlyLog "[$label] VM $($cfg.StandVmId) unavailable: $($statusOut -join ' ')"
            $summaryLines += "$label (VM $($cfg.StandVmId)): FAIL - VM unavailable"
            continue
        }

        Write-NightlyLog "[$label] running stand test on VM $($cfg.StandVmId)..."
        # Identify the run's artifacts as the newest dir that did not exist before
        # the run (timestamp names; birth time is unreliable on Linux filesystems)
        $dirsBefore = @(Get-ChildItem -Path $resultsRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })

        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-StandTest.ps1') `
            -Mode $Mode -Source $Source -ConfigPath $configFile.FullName *>> $logFile
        $testExit = $LASTEXITCODE

        $runDir = Get-ChildItem -Path $resultsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}_\d{6}$' -and $dirsBefore -notcontains $_.Name } |
            Sort-Object Name -Descending | Select-Object -First 1

        $stats = ''
        if ($runDir) {
            $jsonPath = Join-Path $runDir.FullName 'result.json'
            if (Test-Path $jsonPath) {
                $j = Get-Content $jsonPath -Raw | ConvertFrom-Json
                $stats = " - v$($j.Version), $([math]::Round($j.DurationSeconds))s, freed $([math]::Round($j.TotalFreedBytes/1MB)) MB, warn $($j.WarningsCount)"
            }
        }

        if ($testExit -eq 0) {
            Write-NightlyLog "[$label] PASS$stats"
            $summaryLines += "$label (VM $($cfg.StandVmId)): PASS$stats"
        } else {
            $anyFailed = $true
            Write-NightlyLog "[$label] FAIL (exit $testExit)$stats"
            $summaryLines += "$label (VM $($cfg.StandVmId)): FAIL$stats - artifacts: $(if ($runDir) { $runDir.Name } else { '?' })"
        }
    } catch {
        $anyFailed = $true
        Write-NightlyLog "[$($configFile.Name)] EXCEPTION: $_"
        $summaryLines += "$($configFile.BaseName): FAIL - $_"
    }
}

# --- Retention (by timestamp-name, same reason as above) ---
$cutoffStamp = (Get-Date).AddDays(-$RetentionDays).ToString('yyyyMMdd_HHmmss')
Get-ChildItem -Path $resultsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{8}_\d{6}$' -and $_.Name -lt $cutoffStamp } |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

# --- Report ---
$icon = if ($anyFailed) { 'FAIL' } else { 'OK' }
$report = "WinClean stand [$icon] $(Get-Date -Format 'dd.MM HH:mm') (Mode=$Mode, Source=$Source)`n" + ($summaryLines -join "`n")
$sent = Send-Telegram -Text $report
Write-NightlyLog "Nightly matrix done: $icon (telegram: $(if ($sent) { 'delivered' } else { 'FAILED' }))"

# Exit codes: 0 = all green and delivered; 1 = stand failure; 2 = report undelivered
if ($anyFailed) { exit 1 } elseif (-not $sent) { exit 2 } else { exit 0 }
