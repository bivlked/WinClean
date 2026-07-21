# Shared helpers for the Proxmox test stand (dot-sourced by New-StandVM.ps1
# and Invoke-StandTest.ps1). Requires: OpenSSH client with key auth to the
# Proxmox host, qemu-guest-agent inside the guest VM.

# ssh output (qm JSON with possible non-ASCII) must be decoded as UTF-8;
# a redirected pwsh may otherwise default to the legacy OEM codepage
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function ConvertTo-PsSingleQuoted {
    <# Escapes a string for safe embedding into single-quoted PowerShell source #>
    param([Parameter(Mandatory)][string]$Value)
    "'" + ($Value -replace "'", "''") + "'"
}

function Get-StandConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        throw "Stand config not found: $ConfigPath`nCopy stand.config.example.json to stand.config.json and adjust it."
    }
    Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Invoke-Pve {
    <#
    .SYNOPSIS
        Runs a command on the Proxmox host; throws on failure unless -AllowFail
    .DESCRIPTION
        Remote mode (default): over SSH with key auth.
        Local mode (SshHost = 'local'): executed directly via bash - used when the
        harness itself runs ON the Proxmox host (nightly cron runner).
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Command,
        [switch]$AllowFail
    )

    if ($Config.SshHost -eq 'local') {
        $out = bash -c $Command 2>&1
    } else {
        $out = ssh -o BatchMode=yes -o ConnectTimeout=10 "$($Config.SshUser)@$($Config.SshHost)" $Command 2>&1
    }
    if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
        throw "qm command failed (exit $LASTEXITCODE): $Command`n$($out -join "`n")"
    }
    $out
}

function Invoke-GuestCommand {
    <#
    .SYNOPSIS
        Executes a PowerShell snippet inside the guest via qemu-guest-agent
    .DESCRIPTION
        The snippet is passed as -EncodedCommand (base64 UTF-16LE), which avoids
        every layer of ssh/qm/cmd quoting. Returns @{ ExitCode; Output }.
        Runs as SYSTEM (guest agent service context).
    .PARAMETER UsePwsh
        Run under PowerShell 7 (pwsh.exe) instead of Windows PowerShell 5.1
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Script,
        [int]$TimeoutSeconds = 300,
        [switch]$UsePwsh
    )

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
    $shell = if ($UsePwsh) { 'C:\Program Files\PowerShell\7\pwsh.exe' } else { 'powershell.exe' }

    $raw = Invoke-Pve -Config $Config -Command (
        "qm guest exec $($Config.StandVmId) --timeout $TimeoutSeconds -- `"$shell`" -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    )

    $json = ($raw -join "`n") | ConvertFrom-Json
    [pscustomobject]@{
        ExitCode = $json.exitcode
        Output   = $json.'out-data'
        Error    = $json.'err-data'
    }
}

function Wait-GuestAgent {
    <# Waits until the guest agent answers ping #>
    param(
        [Parameter(Mandatory)]$Config,
        [int]$TimeoutSeconds = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $null = Invoke-Pve -Config $Config -Command "qm agent $($Config.StandVmId) ping" -AllowFail
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 5
    }
    throw "Guest agent did not respond within $TimeoutSeconds seconds"
}

function Copy-FileToGuest {
    <#
    .SYNOPSIS
        Copies a local file into the guest via chunked base64 through guest exec
    .DESCRIPTION
        No network path into the guest is required. The file is base64-encoded,
        appended in ~8KB chunks (command line length limits), then decoded inside
        the guest. Slow (~1s per chunk) but fully deterministic.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$GuestPath
    )

    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LocalPath))
    $qGuest = ConvertTo-PsSingleQuoted $GuestPath
    $qB64File = ConvertTo-PsSingleQuoted "$GuestPath.b64"

    # v2.17: was 8000, which silently stopped working - every chunk failed with
    # "the value supplied to -EncodedCommand is not properly Base64 encoded", i.e. a
    # TRUNCATED command line, not a malformed one. The budget is the ~8191-character
    # Windows command line limit inside the guest, and the payload is inflated ~2.67x
    # on the way there: the chunk goes into a PowerShell snippet, which is encoded as
    # UTF-16LE (2 bytes per character) and then Base64'd (+33%). 3000 characters
    # already produce ~8160 and fail; 2000 produce ~5500 and work. Measured against
    # the live stand, not derived on paper.
    $chunkSize = 2000

    $null = Invoke-GuestCommand -Config $Config -Script "Remove-Item -LiteralPath $qB64File -Force -ErrorAction SilentlyContinue"

    for ($offset = 0; $offset -lt $b64.Length; $offset += $chunkSize) {
        $chunk = $b64.Substring($offset, [math]::Min($chunkSize, $b64.Length - $offset))
        $r = Invoke-GuestCommand -Config $Config -Script "Add-Content -LiteralPath $qB64File -Value '$chunk' -NoNewline"
        if ($r.ExitCode -ne 0) { throw "Chunk upload failed at offset $offset : $($r.Error)" }
    }

    $r = Invoke-GuestCommand -Config $Config -Script @"
[System.IO.File]::WriteAllBytes($qGuest, [Convert]::FromBase64String((Get-Content -LiteralPath $qB64File -Raw)))
Remove-Item -LiteralPath $qB64File -Force
(Get-Item $qGuest).Length
"@
    if ($r.ExitCode -ne 0) { throw "Decode failed: $($r.Error)" }

    $expected = (Get-Item $LocalPath).Length
    if ([long]($r.Output.Trim()) -ne $expected) {
        throw "Size mismatch after upload: guest $($r.Output.Trim()) vs local $expected"
    }
}

function Get-GuestFile {
    <#
    .SYNOPSIS
        Reads a UTF-8 text file from the guest, returns its content (or $null)
    .DESCRIPTION
        Transports the file as base64: plain text would be re-decoded by every
        console layer in the chain (guest powershell OEM codepage -> qm -> ssh)
        and non-ASCII content (box-drawing, Cyrillic) arrives garbled. Base64 is
        ASCII-only and survives all of it.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$GuestPath
    )

    $qGuest = ConvertTo-PsSingleQuoted $GuestPath
    $r = Invoke-GuestCommand -Config $Config -Script @"
if (Test-Path -LiteralPath $qGuest) {
    [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($qGuest))
} else { Write-Output '__MISSING__' }
"@
    $payload = if ($r.Output) { $r.Output.Trim() } else { '' }
    if (-not $payload -or $payload -eq '__MISSING__') { return $null }

    try {
        $bytes = [Convert]::FromBase64String($payload)
        # Strip a UTF-8 BOM if present
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bytes = $bytes[3..($bytes.Length - 1)]
        }
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $null
    }
}

function Test-HeartbeatStale {
    <#
    .SYNOPSIS
        Pure decision for the nightly dead-man switch: is the last run too old?
    .DESCRIPTION
        A night the matrix never ran leaves no per-run report and is otherwise
        indistinguishable from a healthy silent night. An independent cron reads the
        heartbeat written by Invoke-NightlyStand and calls this to decide whether to
        alert. Missing, empty or unparseable timestamps count as stale - the whole point
        is to fail loud when there is no proof a run happened.
    #>
    param(
        # Parsed heartbeat object (from last-run.json) or $null when the file is absent
        $Heartbeat,
        [Parameter(Mandatory)][datetime]$Now,
        [int]$MaxAgeHours = 26
    )

    if (-not $Heartbeat -or -not $Heartbeat.Timestamp) { return $true }

    $ts = [datetime]::MinValue
    $parsed = [datetime]::TryParse(
        [string]$Heartbeat.Timestamp, [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$ts)
    if (-not $parsed) { return $true }

    # Stale when older than the window, OR implausibly in the future. The checker always
    # runs hours after the heartbeat, so a genuine one is comfortably in the past; a
    # future timestamp means the clock ran backwards or the file is corrupt, and must not
    # be read as proof a recent run happened (that would silently suppress the alert).
    $age = ($Now.ToUniversalTime() - $ts.ToUniversalTime()).TotalHours
    return ($age -gt $MaxAgeHours) -or ($age -lt -1)
}
