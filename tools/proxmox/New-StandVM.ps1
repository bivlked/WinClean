#Requires -Version 7.1

<#
.SYNOPSIS
    One-time setup of the WinClean test stand VM on Proxmox
.DESCRIPTION
    Creates a persistent test VM from the Windows 11 template:
      1. Full clone of the template VM
      2. Resize (memory/cores) + tag
      3. First boot, wait for qemu-guest-agent
      4. Ensure PowerShell 7 inside the guest (installs the latest MSI silently if missing)
      5. Clean shutdown and a "baseline" snapshot - the state every test run rolls back to
    Requires: SSH key auth to the Proxmox host, template with qemu-guest-agent installed.
.PARAMETER ConfigPath
    Path to stand.config.json (see stand.config.example.json)
.PARAMETER Force
    Destroy an existing VM with the same VMID first
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'stand.config.json'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StandCommon.ps1')

$cfg = Get-StandConfig -ConfigPath $ConfigPath
$vmid = $cfg.StandVmId

Write-Host "WinClean stand setup on $($cfg.SshHost) (template $($cfg.TemplateVmId) -> VM $vmid)" -ForegroundColor Cyan

# 1. Existing VM?
$null = Invoke-Pve -Config $cfg -Command "qm status $vmid" -AllowFail
if ($LASTEXITCODE -eq 0) {
    if (-not $Force) {
        throw "VM $vmid already exists. Use -Force to destroy and recreate it."
    }
    Write-Host "Destroying existing VM $vmid..." -ForegroundColor Yellow
    $null = Invoke-Pve -Config $cfg -Command "qm stop $vmid --skiplock 1" -AllowFail
    $null = Invoke-Pve -Config $cfg -Command "qm destroy $vmid --purge 1"
}

# 2. Clone + configure
Write-Host "Cloning template (full clone, may take a few minutes)..." -ForegroundColor Cyan
$null = Invoke-Pve -Config $cfg -Command "qm clone $($cfg.TemplateVmId) $vmid --name $($cfg.StandVmName) --full 1"
$null = Invoke-Pve -Config $cfg -Command "qm set $vmid --memory $($cfg.MemoryMB) --cores $($cfg.Cores) --tags winclean-stand"

# 3. First boot
Write-Host "Starting VM and waiting for the guest agent..." -ForegroundColor Cyan
$null = Invoke-Pve -Config $cfg -Command "qm start $vmid"
$null = Wait-GuestAgent -Config $cfg -TimeoutSeconds 420

# 4. PowerShell 7 inside the guest
Write-Host "Checking PowerShell 7 in the guest..." -ForegroundColor Cyan
$check = Invoke-GuestCommand -Config $cfg -Script "Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe'"
if ($check.Output -notmatch 'True') {
    Write-Host "Installing PowerShell 7 (latest MSI, silent)..." -ForegroundColor Yellow
    $install = Invoke-GuestCommand -Config $cfg -TimeoutSeconds 900 -Script @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
$asset = $rel.assets | Where-Object { $_.name -like 'PowerShell-*-win-x64.msi' } | Select-Object -First 1
$msi = 'C:\Windows\Temp\ps7.msi'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe'
'@
    if ($install.Output -notmatch 'True') {
        throw "PowerShell 7 installation failed: $($install.Error)"
    }
    Write-Host "PowerShell 7 installed." -ForegroundColor Green
} else {
    Write-Host "PowerShell 7 already present." -ForegroundColor Green
}

# 4.5 Optional locale conversion (e.g. RU template -> en-US stand for the locale matrix)
if ($cfg.PSObject.Properties.Name -contains 'ConvertLocaleTo' -and $cfg.ConvertLocaleTo) {
    $locale = $cfg.ConvertLocaleTo
    Write-Host "Converting guest locale to $locale (language pack via Windows Update, 10-25 min)..." -ForegroundColor Cyan

    $conv = Invoke-GuestCommand -Config $cfg -TimeoutSeconds 2400 -Script @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
Install-Language -Language $locale | Out-Null
Set-WinSystemLocale -SystemLocale $locale
Set-Culture $locale
Set-WinUILanguageOverride -Language $locale
Set-SystemPreferredUILanguage -Language $locale
Copy-UserInternationalSettingsToSystem -WelcomeScreen `$true -NewUser `$true
Write-Output 'CONVERT_OK'
"@
    if ($conv.ExitCode -ne 0 -or $conv.Output -notmatch 'CONVERT_OK') {
        throw "Locale conversion failed (exit $($conv.ExitCode)): $($conv.Error)`n$($conv.Output)"
    }

    Write-Host "Rebooting guest to apply the locale..." -ForegroundColor Cyan
    $null = Invoke-Pve -Config $cfg -Command "qm reboot $vmid --timeout 180"
    Start-Sleep -Seconds 20
    $null = Wait-GuestAgent -Config $cfg -TimeoutSeconds 420
    Start-Sleep -Seconds 15

    $verify = Invoke-GuestCommand -Config $cfg -Script @"
"SYSLOCALE=`$((Get-WinSystemLocale).Name);CULTURE=`$((Get-Culture).Name);PREFUI=`$(Get-SystemPreferredUILanguage);INSTALLED=`$((Get-InstalledLanguage -Language $locale -ErrorAction SilentlyContinue) -ne `$null)"
"@
    foreach ($marker in @("SYSLOCALE=$locale", "CULTURE=$locale", "PREFUI=$locale", 'INSTALLED=True')) {
        if ($verify.Output -notmatch [regex]::Escape($marker)) {
            throw "Locale verification failed at '$marker', guest reports: $($verify.Output)"
        }
    }
    Write-Host "Locale converted and verified: $locale" -ForegroundColor Green
}

# 5. Shutdown + baseline snapshot
Write-Host "Shutting down and creating '$($cfg.SnapshotName)' snapshot..." -ForegroundColor Cyan
$null = Invoke-Pve -Config $cfg -Command "qm shutdown $vmid --timeout 180"
$null = Invoke-Pve -Config $cfg -Command "qm snapshot $vmid $($cfg.SnapshotName) --description 'WinClean stand baseline (clean Win11 + PS7)'"

Write-Host ""
Write-Host "Stand ready: VM $vmid '$($cfg.StandVmName)', snapshot '$($cfg.SnapshotName)'" -ForegroundColor Green
Write-Host "Run tests with: pwsh tools/proxmox/Invoke-StandTest.ps1 -Mode Report" -ForegroundColor Cyan
