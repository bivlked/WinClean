#Requires -Version 7.1

<#
.SYNOPSIS
    Deploys the nightly stand runner onto the Proxmox host
.DESCRIPTION
    Run from the workstation. Idempotent - re-run to update scripts/configs.
      1. Installs PowerShell 7 on the host (official tar.gz into /opt/powershell)
         if missing - Debian 13 has no Microsoft apt repo yet
      2. Copies the harness (StandCommon, Invoke-StandTest, Invoke-NightlyStand,
         BoxGeometry) and all stand configs (rewritten to SshHost='local') into
         /opt/winclean-stand
      3. Creates /root/.winclean-stand.env with Telegram credentials extracted
         host-side from a companion VPN-gateway container's healthcheck script -
         credentials never leave the host and are not stored in this repository
      4. Installs the cron job (03:30 nightly, flock-guarded)
.PARAMETER CronSchedule
    Cron time spec (default: "30 3 * * *")
.NOTES
    v2.17 (p.31 of the audit): the gateway container ID and its SOCKS proxy
    addresses used to be hardcoded here, leaking internal network topology into a
    public repository. They now come from the (gitignored) stand config -
    GatewayCtId and GatewaySocksProxies - see stand.config.example.json.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'stand.config.json'),
    [string]$CronSchedule = '30 3 * * *'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StandCommon.ps1')

$cfg = Get-StandConfig -ConfigPath $ConfigPath
if ($cfg.SshHost -eq 'local') { throw "Deploy must run from the workstation against a remote host config" }
if (-not $cfg.GatewayCtId -or -not $cfg.GatewaySocksProxies) {
    throw "Config is missing GatewayCtId/GatewaySocksProxies - see stand.config.example.json"
}
$target = "$($cfg.SshUser)@$($cfg.SshHost)"
$remoteDir = '/opt/winclean-stand'
$gatewayCtId = [int]$cfg.GatewayCtId
$gatewayProxies = @($cfg.GatewaySocksProxies)

Write-Host "Deploying nightly stand runner to $target..." -ForegroundColor Cyan

# 1. PowerShell 7 on the host
Write-Host "[1/4] Ensuring PowerShell 7 on the host..." -ForegroundColor Cyan
$pwshCheck = ssh -o BatchMode=yes $target 'test -x /usr/local/bin/pwsh && /usr/local/bin/pwsh --version' 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installing pwsh (official tar.gz)..." -ForegroundColor Yellow
    # GitHub asset downloads from the host are intermittently slow/blocked -
    # fall back to the vpn-gw SOCKS proxy (same transport chain as Telegram).
    # __GATEWAY_PROXIES__ is substituted below - kept as a placeholder here so the
    # heredoc can stay single-quoted (it also contains literal bash $variables).
    $installCmd = @'
set -e
command -v jq >/dev/null || { echo "jq is required on the host (apt install jq)"; exit 1; }
ARCH=linux-x64
fetch() { # $1=url $2=outfile
  for p in "" __GATEWAY_PROXIES__; do
    if [ -n "$p" ]; then
      curl -sSL --max-time 300 --proxy "$p" "$1" -o "$2" && return 0
    else
      curl -sSL --max-time 120 "$1" -o "$2" && return 0
    fi
    echo "fetch failed via ${p:-direct}, trying next transport" >&2
  done
  return 1
}
fetch "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" /tmp/pwsh-release.json
URL=$(jq -r ".assets[] | select(.name | test(\"powershell-.*-$ARCH.tar.gz$\")) | .browser_download_url" /tmp/pwsh-release.json | head -1)
test -n "$URL"
mkdir -p /opt/powershell
fetch "$URL" /tmp/pwsh.tar.gz
tar -xzf /tmp/pwsh.tar.gz -C /opt/powershell
chmod +x /opt/powershell/pwsh
ln -sf /opt/powershell/pwsh /usr/local/bin/pwsh
rm -f /tmp/pwsh.tar.gz /tmp/pwsh-release.json
/usr/local/bin/pwsh --version
'@
    $proxyListBash = ($gatewayProxies | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $installCmd = $installCmd -replace '__GATEWAY_PROXIES__', $proxyListBash
    $out = ssh -o BatchMode=yes $target $installCmd 2>&1
    if ($LASTEXITCODE -ne 0) { throw "pwsh installation failed:`n$($out -join "`n")" }
    Write-Host "  Installed: $($out | Select-Object -Last 1)" -ForegroundColor Green
} else {
    Write-Host "  Present: $($pwshCheck | Select-Object -Last 1)" -ForegroundColor Green
}

# 2. Harness files + configs (SshHost rewritten to 'local').
#    Remote configs are synced: stale stand.config*.json from renamed/removed
#    stands would otherwise stay in the nightly matrix forever.
Write-Host "[2/4] Copying harness and configs..." -ForegroundColor Cyan
$null = ssh -o BatchMode=yes $target "mkdir -p $remoteDir/results && rm -f $remoteDir/stand.config*.json"

$files = @(
    (Join-Path $PSScriptRoot 'StandCommon.ps1')
    (Join-Path $PSScriptRoot 'Invoke-StandTest.ps1')
    (Join-Path $PSScriptRoot 'Invoke-NightlyStand.ps1')
    (Join-Path $PSScriptRoot '..' 'BoxGeometry.ps1')
)
foreach ($f in $files) {
    scp -o BatchMode=yes -q $f "${target}:$remoteDir/" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "scp failed for $f" }
}

$stageDir = Join-Path ([System.IO.Path]::GetTempPath()) "winclean-stand-deploy-$(Get-Random)"
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
try {
    Get-ChildItem -Path $PSScriptRoot -Filter 'stand.config*.json' |
        Where-Object { $_.Name -ne 'stand.config.example.json' } | ForEach-Object {
            $c = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $c.SshHost = 'local'
            $staged = Join-Path $stageDir $_.Name
            $c | ConvertTo-Json | Set-Content -Path $staged -Encoding UTF8
            scp -o BatchMode=yes -q $staged "${target}:$remoteDir/" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "scp failed for $($_.Name)" }
            Write-Host "  $($_.Name) -> SshHost=local" -ForegroundColor DarkGray
        }
} finally {
    Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 3. Telegram env (extracted host-side from the gateway container; never passes
#    through here - see .NOTES for why the container ID is not hardcoded)
Write-Host "[3/4] Telegram credentials..." -ForegroundColor Cyan
$tgCmd = @'
set -e
ENV=/root/.winclean-stand.env
valid() { grep -qE '^BOT_TOKEN=.+' "$ENV" 2>/dev/null && grep -qE '^CHAT_ID=.+' "$ENV" 2>/dev/null; }
if valid; then
  chmod 600 "$ENV"
  echo exists
else
  pct exec __GATEWAY_CT_ID__ -- sh -c 'grep -E "^(BOT_TOKEN|CHAT_ID)=" /opt/xray/healthcheck.sh' > "$ENV"
  echo 'TG_PROXIES=__GATEWAY_PROXIES_CSV__' >> "$ENV"
  chmod 600 "$ENV"
  valid || { echo "env extraction produced an invalid file"; exit 1; }
  echo created
fi
'@
$proxyCsv = $gatewayProxies -join ','
$tgCmd = $tgCmd -replace '__GATEWAY_CT_ID__', $gatewayCtId -replace '__GATEWAY_PROXIES_CSV__', $proxyCsv
$tgResult = ssh -o BatchMode=yes $target $tgCmd 2>&1
if ($LASTEXITCODE -ne 0) { throw "Telegram env setup failed:`n$($tgResult -join "`n")" }
Write-Host "  /root/.winclean-stand.env: $($tgResult | Select-Object -Last 1)" -ForegroundColor Green

# 4. Cron job (flock-guarded so overlapping runs cannot double-start)
Write-Host "[4/4] Cron job..." -ForegroundColor Cyan
$cronLine = "$CronSchedule root /usr/bin/flock -n /run/winclean-stand.lock /usr/local/bin/pwsh -NoProfile -File $remoteDir/Invoke-NightlyStand.ps1 >> $remoteDir/results/cron.log 2>&1"
$cronCmd = "printf '%s\n' 'SHELL=/bin/bash' 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' '$cronLine' > /etc/cron.d/winclean-stand && chmod 644 /etc/cron.d/winclean-stand && cat /etc/cron.d/winclean-stand"
$cronResult = ssh -o BatchMode=yes $target $cronCmd 2>&1
if ($LASTEXITCODE -ne 0) { throw "Cron setup failed:`n$($cronResult -join "`n")" }

Write-Host ""
Write-Host "Deployed. Nightly schedule: $CronSchedule" -ForegroundColor Green
Write-Host "Manual run on host: ssh $target pwsh -NoProfile -File $remoteDir/Invoke-NightlyStand.ps1 -Mode Report" -ForegroundColor Cyan
