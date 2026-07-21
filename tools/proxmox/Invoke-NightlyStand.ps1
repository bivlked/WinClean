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

    Telegram credentials come from an env file (default /root/.winclean-stand.env),
    written by Deploy-StandRunner.ps1 from the (gitignored) stand config - see
    stand.config.example.json for the GatewayCtId/GatewaySocksProxies fields:
        BOT_TOKEN=...
        CHAT_ID=...
        TG_PROXIES=socks5h://<gateway-host>:1080,socks5h://<gateway-host>:11080
    Delivery tries direct first, then each proxy (same pattern as the vpn-gw
    healthcheck - direct Telegram is intermittently unavailable).
.PARAMETER Mode
    Test mode passed to Invoke-StandTest (default: Full - real cleanup, no updates)
.PARAMETER Source
    Script source passed to Invoke-StandTest (default: main - tests published code).
    Unless it is already 'release', the matrix ALSO runs a quick Report pass against
    the published release asset, so a broken release with a healthy main branch does
    not pass the night unnoticed (p.30 of the audit).
.PARAMETER HeartbeatCheckOnly
    Dead-man switch (p.29 of the audit). Skips the matrix; instead reads the heartbeat
    that a normal run leaves in results/last-run.json and, if it is missing or older
    than HeartbeatMaxAgeHours, sends a Telegram alert. Run this from a SEPARATE cron,
    later than the nightly, so a nightly cron that never fired is still caught.
.PARAMETER HeartbeatMaxAgeHours
    How old the last successful matrix run may be before the dead-man switch alerts
    (default 26 - a nightly cadence plus a couple of hours of slack).
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Full', 'FullWithUpdates')]
    [string]$Mode = 'Full',

    [ValidateSet('local', 'main', 'release')]
    [string]$Source = 'main',

    [string]$TelegramEnvPath = '/root/.winclean-stand.env',
    [int]$RetentionDays = 14,

    [switch]$HeartbeatCheckOnly,
    [int]$HeartbeatMaxAgeHours = 26
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

    # v2.17 (p.27 of the audit): the token used to be embedded in the URL, which lands
    # in curl's argv and is readable by any other local user via ps aux on a shared
    # host. A curl config file (-K) keeps the URL/token/message out of the process
    # arguments - only the config file's own path shows up there, not its contents.
    # curl's config format needs backslash/quote escaping inside quoted values.
    $escape = { param($s) ($s -replace '\\', '\\\\') -replace '"', '\"' }
    $curlConfig = New-TemporaryFile
    try {
        if (-not $IsWindows) { & chmod 600 $curlConfig 2>$null }
        @(
            "url = ""https://api.telegram.org/bot$(& $escape $env.BOT_TOKEN)/sendMessage"""
            "data = ""chat_id=$(& $escape $env.CHAT_ID)"""
            "data-urlencode = ""text=$(& $escape $Text)"""
            'output = "/dev/null"'
            'write-out = "%{http_code}"'
            'silent'
            'show-error'
            'max-time = 10'
        ) | Set-Content -LiteralPath $curlConfig -Encoding ascii

        $transports = @('') + @(($env.TG_PROXIES -split ',') | Where-Object { $_ })
        foreach ($proxy in $transports) {
            $curlArgs = @('-K', $curlConfig)
            if ($proxy) { $curlArgs += @('--proxy', $proxy.Trim()) }
            $code = & curl @curlArgs 2>$null
            if ($code -eq '200') {
                Write-NightlyLog "Telegram delivered via $(if ($proxy) { $proxy } else { 'direct' })"
                return $true
            }
        }
        Write-NightlyLog "Telegram delivery FAILED via all transports"
        return $false
    } finally {
        Remove-Item -LiteralPath $curlConfig -Force -ErrorAction SilentlyContinue
    }
}

# --- Dead-man switch (p.29): verify the last run's heartbeat, alert if it is stale ---
# Run from an independent cron LATER than the nightly, so a nightly cron that never
# fired (and therefore left no fresh heartbeat) is still caught and reported.
$heartbeatPath = Join-Path $resultsRoot 'last-run.json'
if ($HeartbeatCheckOnly) {
    $hb = $null
    if (Test-Path $heartbeatPath) {
        try { $hb = Get-Content $heartbeatPath -Raw | ConvertFrom-Json } catch { $hb = $null }
    }
    if (Test-HeartbeatStale -Heartbeat $hb -Now (Get-Date) -MaxAgeHours $HeartbeatMaxAgeHours) {
        $last = if ($hb -and $hb.Timestamp) { $hb.Timestamp } else { 'never' }
        $msg = "Nightly matrix has not completed in over $HeartbeatMaxAgeHours h (last: $last) - the nightly cron may be dead."
        Write-NightlyLog "DEAD-MAN: $msg"
        $null = Send-Telegram -Text "WinClean stand [FAIL] $(Get-Date -Format 'dd.MM HH:mm')`n$msg"
        exit 1
    }
    Write-NightlyLog "Heartbeat OK (last run $($hb.Timestamp), within $HeartbeatMaxAgeHours h)"
    exit 0
}

function Invoke-OneStandRun {
    <# Runs one stand test for a given source/mode and returns { Passed; Line }. Reads
       the outer $resultsRoot/$logFile/$PSScriptRoot. Kept as a function so the matrix
       can run each stand against more than one source (p.30) without duplicating the
       artifact-discovery and stats-extraction below. #>
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RunSource,
        [Parameter(Mandatory)][string]$RunMode
    )
    Write-NightlyLog "[$Label] running $RunMode/$RunSource on VM $($Cfg.StandVmId)..."
    # Identify the run's artifacts as the newest dir that did not exist before the run
    # (timestamp names; birth time is unreliable on Linux filesystems)
    $dirsBefore = @(Get-ChildItem -Path $resultsRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name })

    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-StandTest.ps1') `
        -Mode $RunMode -Source $RunSource -ConfigPath $ConfigPath *>> $logFile
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
        Write-NightlyLog "[$Label] $RunMode/$RunSource PASS$stats"
        return [pscustomobject]@{ Passed = $true; Line = "$Label (VM $($Cfg.StandVmId)) [$RunMode/$RunSource]: PASS$stats" }
    }
    Write-NightlyLog "[$Label] $RunMode/$RunSource FAIL (exit $testExit)$stats"
    return [pscustomobject]@{ Passed = $false; Line = "$Label (VM $($Cfg.StandVmId)) [$RunMode/$RunSource]: FAIL$stats - artifacts: $(if ($runDir) { $runDir.Name } else { '?' })" }
}

# --- Discover the stand matrix ---
$configs = Get-ChildItem -Path $PSScriptRoot -Filter 'stand.config*.json' |
    Where-Object { $_.Name -ne 'stand.config.example.json' } | Sort-Object Name

if (-not $configs) {
    # v2.17 (p.28 of the audit): this used to exit silently - exactly the situation
    # where the Telegram channel is needed most, since a stand this broken cannot
    # produce its usual per-run report either.
    $msg = "No stand configs found in $PSScriptRoot - nightly matrix did not run"
    Write-NightlyLog $msg
    $null = Send-Telegram -Text "WinClean stand [FAIL] $(Get-Date -Format 'dd.MM HH:mm')`n$msg"
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

        # Run the configured source, and - unless it already IS release - a quick Report
        # pass against the PUBLISHED release asset too (p.30). Users get the release, not
        # main, so a broken release with a healthy main branch must not pass the night.
        $runs = @([pscustomobject]@{ Source = $Source; Mode = $Mode })
        if ($Source -ne 'release') {
            $runs += [pscustomobject]@{ Source = 'release'; Mode = 'Report' }
        }
        foreach ($run in $runs) {
            $res = Invoke-OneStandRun -ConfigPath $configFile.FullName -Cfg $cfg -Label $label `
                -RunSource $run.Source -RunMode $run.Mode
            $summaryLines += $res.Line
            if (-not $res.Passed) { $anyFailed = $true }
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

# Dead-man heartbeat (p.29): record that this run completed, for an independent
# -HeartbeatCheckOnly cron to read. A night that never ran leaves this file stale.
$heartbeat = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    Verdict   = $icon
    Mode      = $Mode
    Source    = $Source
    Delivered = $sent
    Stands    = $summaryLines
}
try {
    $heartbeat | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $heartbeatPath -Encoding utf8
} catch {
    Write-NightlyLog "Could not write heartbeat $($heartbeatPath): $_"
}

# Exit codes: 0 = all green and delivered; 1 = stand failure; 2 = report undelivered
if ($anyFailed) { exit 1 } elseif (-not $sent) { exit 2 } else { exit 0 }
