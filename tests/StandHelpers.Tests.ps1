#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for pure helpers in tools/proxmox/StandCommon.ps1
.DESCRIPTION
    These test only side-effect-free logic (no SSH, no VM, no admin), so they run
    anywhere the rest of the suite does. Currently: the nightly dead-man decision.
#>

BeforeAll {
    $common = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'proxmox' 'StandCommon.ps1')).Path
    . $common

    # Fixed reference instant so the tests never depend on the real clock
    $script:Now = [datetime]::Parse(
        '2026-07-21T12:00:00Z', [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind)

    function New-Heartbeat {
        param([double]$HoursAgo)
        [pscustomobject]@{ Timestamp = $script:Now.AddHours(-$HoursAgo).ToString('o'); Verdict = 'OK' }
    }
}

Describe "Test-HeartbeatStale (nightly dead-man switch)" -Tag "Unit", "Stand", "V219" {

    It "treats a missing heartbeat as stale" {
        Test-HeartbeatStale -Heartbeat $null -Now $script:Now -MaxAgeHours 26 | Should -BeTrue
    }

    It "treats a heartbeat with no timestamp as stale" {
        Test-HeartbeatStale -Heartbeat ([pscustomobject]@{ Verdict = 'OK' }) -Now $script:Now -MaxAgeHours 26 | Should -BeTrue
    }

    It "treats an unparseable timestamp as stale" {
        $hb = [pscustomobject]@{ Timestamp = 'not-a-date' }
        Test-HeartbeatStale -Heartbeat $hb -Now $script:Now -MaxAgeHours 26 | Should -BeTrue
    }

    It "is not stale for a run within the window" {
        Test-HeartbeatStale -Heartbeat (New-Heartbeat -HoursAgo 1) -Now $script:Now -MaxAgeHours 26 | Should -BeFalse
    }

    It "is stale for a run older than the window" {
        Test-HeartbeatStale -Heartbeat (New-Heartbeat -HoursAgo 30) -Now $script:Now -MaxAgeHours 26 | Should -BeTrue
    }

    It "uses the boundary exclusively: exactly MaxAgeHours old is still fresh" {
        Test-HeartbeatStale -Heartbeat (New-Heartbeat -HoursAgo 26) -Now $script:Now -MaxAgeHours 26 | Should -BeFalse
    }

    It "treats an implausible future timestamp as stale (clock ran backwards)" {
        # A future heartbeat is not proof a recent run happened; without this guard a
        # negative age would read as 'fresh' indefinitely and suppress the alert.
        Test-HeartbeatStale -Heartbeat (New-Heartbeat -HoursAgo -5) -Now $script:Now -MaxAgeHours 26 | Should -BeTrue
    }

    It "works on a heartbeat actually round-tripped through ConvertFrom-Json" {
        # Mirrors the real path: the checker reads last-run.json, not an in-memory object
        $obj = [ordered]@{ Timestamp = $script:Now.AddHours(-2).ToString('o'); Verdict = 'OK' }
        $hb = $obj | ConvertTo-Json | ConvertFrom-Json
        Test-HeartbeatStale -Heartbeat $hb -Now $script:Now -MaxAgeHours 26 | Should -BeFalse
    }

    It "parses an ISO timestamp regardless of the current culture" {
        # ru-RU formats dates as dd.MM.yyyy; the round-trip parse must ignore that
        $prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]'ru-RU'
            Test-HeartbeatStale -Heartbeat (New-Heartbeat -HoursAgo 1) -Now $script:Now -MaxAgeHours 26 | Should -BeFalse
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev
        }
    }
}
