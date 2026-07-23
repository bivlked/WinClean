#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for WinClean.ps1 helper functions
.DESCRIPTION
    Tests safe, non-destructive helper functions that can run in CI/CD.
    These tests do not require Administrator rights or modify the system.
.NOTES
    Version: 2.14
    Requires: Pester 5.0+
#>

BeforeAll {
    # v2.17: the real WinClean.ps1 is dot-sourced instead of pasting copies of its
    # functions here. The copies were a tautology - they tested themselves, so a bug in
    # the product could never fail a test, and they had already drifted apart from it.
    # WinClean.ps1 guards its own entry point (`if ($MyInvocation.InvocationName -ne '.'`),
    # so dot-sourcing defines the functions without running any maintenance.
    $script:WinCleanPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'WinClean.ps1')).Path

    $script:IsElevated = ([Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # WinClean.ps1 declares #Requires -RunAsAdministrator, so without elevation the
    # dot-source throws a bare "requires elevation" error from Pester's container
    # loader. Say what is actually wrong instead. Failing loudly is deliberate: these
    # tests exist to check the product, and skipping them would hide that they did not.
    #
    # Note this also imports the script's process-level settings (console encoding and
    # $PSDefaultParameterValues) into the test session - acceptable here, and the price
    # of testing the real code rather than copies of it.
    if (-not $script:IsElevated) {
        throw "These tests dot-source WinClean.ps1, which requires administrator rights. Run Pester from an elevated shell."
    }
    . $script:WinCleanPath

    # Route the log somewhere disposable - the product picks %TEMP% by default and the
    # logging tests below write real entries
    $script:LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanTest_$(Get-Random).log"
}

AfterAll {
    # Clean up test log file
    if (Test-Path $script:LogPath) {
        Remove-Item $script:LogPath -Force -ErrorAction SilentlyContinue
    }
}

#region Format-FileSize Tests

Describe "Format-FileSize" -Tag "Unit", "Helper" {

    It "Returns correct format for <Bytes> bytes" -ForEach @(
        @{ Bytes = 0;            ExpectedPattern = "^0 B$" }
        @{ Bytes = 1;            ExpectedPattern = "^1 B$" }
        @{ Bytes = 512;          ExpectedPattern = "^512 B$" }
        @{ Bytes = 1023;         ExpectedPattern = "^1023 B$" }
        @{ Bytes = 1024;         ExpectedPattern = "^1[,.]00 KB$" }
        @{ Bytes = 1536;         ExpectedPattern = "^1[,.]50 KB$" }
        @{ Bytes = 1048576;      ExpectedPattern = "^1[,.]00 MB$" }
        @{ Bytes = 1572864;      ExpectedPattern = "^1[,.]50 MB$" }
        @{ Bytes = 1073741824;   ExpectedPattern = "^1[,.]00 GB$" }
        @{ Bytes = 1610612736;   ExpectedPattern = "^1[,.]50 GB$" }
    ) {
        # Use regex to handle both . and , decimal separators (localization)
        Format-FileSize -Bytes $Bytes | Should -Match $ExpectedPattern
    }

    It "Handles large values (TB range)" {
        $result = Format-FileSize -Bytes (1GB * 1500)
        # v2.17: the product formats terabytes as TB (the old in-test copy of this
        # function stopped at GB) and always uses the invariant culture, so the decimal
        # separator is a dot regardless of the system locale
        $result | Should -Be "1.46 TB"
    }

    It "Formats sizes independently of the system locale" {
        # A no-break space as the group separator (the ru-RU default for "{0:N2}") would
        # break our own log parsing in the smoke test and on the stand
        $result = Format-FileSize -Bytes 1234567890
        $result | Should -Be "1.15 GB"
        $result | Should -Not -Match " "
    }

    It "Handles negative values gracefully" {
        # Negative bytes shouldn't happen, but function should not throw
        { Format-FileSize -Bytes -100 } | Should -Not -Throw
    }
}

#endregion

#region ConvertFrom-HumanReadableSize Tests

Describe "ConvertFrom-HumanReadableSize" -Tag "Unit", "Helper" {

    It "Converts '0 B' to 0" {
        ConvertFrom-HumanReadableSize -SizeString "0 B" | Should -Be 0
    }

    It "Converts '100 B' to 100" {
        ConvertFrom-HumanReadableSize -SizeString "100 B" | Should -Be 100
    }

    It "Converts '1 KB' to 1024" {
        ConvertFrom-HumanReadableSize -SizeString "1 KB" | Should -Be 1024
    }

    It "Converts '1KB' (no space) to 1024" {
        ConvertFrom-HumanReadableSize -SizeString "1KB" | Should -Be 1024
    }

    It "Converts '1.5 KB' to 1536" {
        ConvertFrom-HumanReadableSize -SizeString "1.5 KB" | Should -Be 1536
    }

    It "Converts '512 KB' to 524288" {
        ConvertFrom-HumanReadableSize -SizeString "512 KB" | Should -Be 524288
    }

    It "Converts '1 MB' to 1048576" {
        ConvertFrom-HumanReadableSize -SizeString "1 MB" | Should -Be 1048576
    }

    It "Converts '2.5 MB' to 2621440" {
        ConvertFrom-HumanReadableSize -SizeString "2.5 MB" | Should -Be 2621440
    }

    It "Converts '1 GB' to 1073741824" {
        ConvertFrom-HumanReadableSize -SizeString "1 GB" | Should -Be 1073741824
    }

    It "Converts '2.5 GB' to 2684354560" {
        ConvertFrom-HumanReadableSize -SizeString "2.5 GB" | Should -Be 2684354560
    }

    It "Converts '1 TB' to 1099511627776" {
        ConvertFrom-HumanReadableSize -SizeString "1 TB" | Should -Be 1099511627776
    }

    It "Returns 0 for empty string" {
        ConvertFrom-HumanReadableSize -SizeString "" | Should -Be 0
    }

    It "Returns 0 for null" {
        ConvertFrom-HumanReadableSize -SizeString $null | Should -Be 0
    }

    It "Returns 0 for invalid format" {
        ConvertFrom-HumanReadableSize -SizeString "invalid" | Should -Be 0
        ConvertFrom-HumanReadableSize -SizeString "MB 100" | Should -Be 0
    }

    It "Handles comma as decimal separator (localization)" {
        # Some locales use comma: "2,5 GB"
        ConvertFrom-HumanReadableSize -SizeString "2,5 GB" | Should -Be 2684354560
    }

    Context "Widened localization (v2.17, p.17 of the audit)" {

        It "Handles a space-grouped thousands separator: '1 234 MB'" {
            ConvertFrom-HumanReadableSize -SizeString "1 234 MB" | Should -Be 1293942784
        }

        It "Handles EU-style dot-thousands/comma-decimal: '1.234,5 MB'" {
            ConvertFrom-HumanReadableSize -SizeString "1.234,5 MB" | Should -Be 1294467072
        }

        It "Handles US-style comma-thousands/dot-decimal: '1,234.5 MB'" {
            ConvertFrom-HumanReadableSize -SizeString "1,234.5 MB" | Should -Be 1294467072
        }

        It "Does not throw on an ambiguous separator format that used to raise an exception" {
            # Old implementation blindly replaced ',' with '.', turning "1.234,5" into the
            # unparseable "1.234.5" and letting [double] throw instead of returning 0
            { ConvertFrom-HumanReadableSize -SizeString "1.234,5 MB" } | Should -Not -Throw
        }

        It "Converts the word form of bytes: '<SizeString>'" -ForEach @(
            @{ SizeString = "976 bytes"; Expected = 976 }
            @{ SizeString = "1 byte";    Expected = 1 }
            @{ SizeString = "976 байт";  Expected = 976 }
            @{ SizeString = "976 байта"; Expected = 976 }
        ) {
            ConvertFrom-HumanReadableSize -SizeString $SizeString | Should -Be $Expected
        }

        It "Reads the en-US thousands form instead of dividing it by a thousand (v2.20)" {
            # The defect: a lone separator was always taken for the decimal point, so the
            # ordinary "1,234 KB" from an en-US shell was read as 1.234 KB
            $enUS = [cultureinfo]::GetCultureInfo('en-US')
            ConvertFrom-HumanReadableSize -SizeString "1,234 KB" -Culture $enUS | Should -Be 1263616
        }

        It "Still reads the same string as a decimal where the culture says so" {
            # ru-RU writes 1.234 as "1,234" and groups thousands with a no-break space,
            # so the identical text means something else there
            $ruRU = [cultureinfo]::GetCultureInfo('ru-RU')
            ConvertFrom-HumanReadableSize -SizeString "1,234 KB" -Culture $ruRU | Should -Be 1264
        }

        It "Does not let the culture override a shape that cannot be a grouping" {
            # Guards the repair that would have been worse than the defect: .NET's
            # AllowThousands does not validate grouping, so a culture-first parse reads
            # "1,5" as 15 on en-US. Three digits are required after the separator.
            $enUS = [cultureinfo]::GetCultureInfo('en-US')
            ConvertFrom-HumanReadableSize -SizeString "1,5 GB" -Culture $enUS | Should -Be 1610612736
            ConvertFrom-HumanReadableSize -SizeString "1,2345 MB" -Culture $enUS | Should -Be 1294467
        }

        It "Handles repeated grouping: '12,345,678 B' on en-US" {
            $enUS = [cultureinfo]::GetCultureInfo('en-US')
            ConvertFrom-HumanReadableSize -SizeString "12,345,678 B" -Culture $enUS | Should -Be 12345678
        }

        It "Applies the same rule to a lone dot: '<Culture>' reads '1.234 KB' as <Expected>" -ForEach @(
            @{ Culture = 'en-US'; Expected = 1264 }      # dot is the decimal point there
            @{ Culture = 'de-DE'; Expected = 1263616 }   # dot groups thousands there
        ) {
            ConvertFrom-HumanReadableSize -SizeString "1.234 KB" -Culture ([cultureinfo]::GetCultureInfo($Culture)) |
                Should -Be $Expected
        }

        It "Falls back to the invariant reading when the culture uses the mark for neither purpose" {
            # ru-RU: decimal is ',' and thousands are grouped with a no-break space, so a
            # lone '.' matches neither rule. Without the fallback the code would treat it
            # as grouping and read "1.234 KB" as 1234 KB - a thousandfold over-read on the
            # maintainer's own default locale, and no other test reaches this branch.
            $ruRU = [cultureinfo]::GetCultureInfo('ru-RU')
            $ruRU.NumberFormat.NumberDecimalSeparator | Should -Be ','
            $ruRU.NumberFormat.NumberGroupSeparator | Should -Not -Be '.'
            ConvertFrom-HumanReadableSize -SizeString "1.234 KB" -Culture $ruRU | Should -Be 1264
        }

        It "Leaves an unambiguous two-separator string alone whatever the culture" {
            # Both marks present means the last one is the decimal point, and no culture
            # can make that ambiguous
            foreach ($c in 'en-US', 'ru-RU', 'de-DE') {
                ConvertFrom-HumanReadableSize -SizeString "1,234.5 MB" -Culture ([cultureinfo]::GetCultureInfo($c)) |
                    Should -Be 1294467072
                ConvertFrom-HumanReadableSize -SizeString "1.234,5 MB" -Culture ([cultureinfo]::GetCultureInfo($c)) |
                    Should -Be 1294467072
            }
        }

        It "Converts binary-unit spellings: '<SizeString>'" -ForEach @(
            @{ SizeString = "1 MiB";   Expected = 1048576 }
            @{ SizeString = "1.5 GiB"; Expected = 1610612736 }
            @{ SizeString = "1KiB";    Expected = 1024 }
        ) {
            ConvertFrom-HumanReadableSize -SizeString $SizeString | Should -Be $Expected
        }
    }

    Context "Localized units (v2.14: Shell GetDetailsOf on Russian Windows)" {

        It "Converts Cyrillic units: '<SizeString>'" -ForEach @(
            @{ SizeString = "816 КБ";  Expected = 835584 }
            @{ SizeString = "1,52 МБ"; Expected = 1593836 }
            @{ SizeString = "2,5 ГБ";  Expected = 2684354560 }
            @{ SizeString = "1 ТБ";    Expected = 1099511627776 }
            @{ SizeString = "100 Б";   Expected = 100 }
        ) {
            ConvertFrom-HumanReadableSize -SizeString $SizeString | Should -Be $Expected
        }

        It "Handles no-break space between value and unit" {
            $nbsp = [char]0x00A0
            ConvertFrom-HumanReadableSize -SizeString "1,5${nbsp}ГБ" | Should -Be 1610612736
        }

        It "Handles narrow no-break space between value and unit" {
            $nnbsp = [char]0x202F
            ConvertFrom-HumanReadableSize -SizeString "1,5${nnbsp}MB" | Should -Be 1572864
        }
    }
}

#endregion

#region Get-SupersededDriverCandidate Tests

Describe "Get-SupersededDriverCandidate" -Tag "Unit", "Helper" {
    <#
    v2.17 (p.6/p.23 of the audit): fixture-based tests for the pure candidate-selection
    logic extracted from Get-RedundantDriverPackage. No pnputil.exe, no FileRepository -
    just hand-built package objects shaped like the parsed pnputil XML.
    #>

    BeforeAll {
        # Pester 5: a bare `function` statement in a Describe body only runs during
        # Discovery, not Run - It blocks would not see it. Must live in BeforeAll.
        function New-DriverPackage {
            param($Oem, $Inf, $Provider = 'Acme', $Class = 'Net', $Version, $Date = '2024-01-01', $InUse = $false)
            [pscustomobject]@{
                Oem = $Oem; Inf = $Inf; Provider = $Provider; Class = $Class
                Version = [version]$Version; Date = [datetime]$Date; InUse = [bool]$InUse
            }
        }
    }

    It "Flags the older package as a candidate when a newer sibling exists" {
        $pkgs = @(
            New-DriverPackage -Oem 'oem10.inf' -Inf 'sample.inf' -Version '1.0.0.0'
            New-DriverPackage -Oem 'oem11.inf' -Inf 'sample.inf' -Version '2.0.0.0'
        )
        $result = @(Get-SupersededDriverCandidate -Packages $pkgs)
        $result.Count | Should -Be 1
        $result[0].Oem | Should -Be 'oem10.inf'
        $result[0].KeptVersion | Should -Be ([version]'2.0.0.0')
        $result[0].Bytes | Should -Be 0
    }

    It "Never flags a package that has no newer sibling, even if unused" {
        $pkgs = @(New-DriverPackage -Oem 'oem10.inf' -Inf 'lonely.inf' -Version '1.0.0.0' -InUse $false)
        @(Get-SupersededDriverCandidate -Packages $pkgs).Count | Should -Be 0
    }

    It "Never flags a package currently in use, even when superseded" {
        # This is the guard that separates this from an aggressive driver cleaner: a
        # device that is merely unplugged right now must not lose its driver package
        $pkgs = @(
            New-DriverPackage -Oem 'oem10.inf' -Inf 'sample.inf' -Version '1.0.0.0' -InUse $true
            New-DriverPackage -Oem 'oem11.inf' -Inf 'sample.inf' -Version '2.0.0.0'
        )
        @(Get-SupersededDriverCandidate -Packages $pkgs).Count | Should -Be 0
    }

    It "Does not cross-supersede identical INF names shipped by different vendors" {
        # usbaudio.inf/hidusb.inf-style generic names: grouping by Inf name alone would
        # let one vendor's newer package declare a different vendor's package superseded
        $pkgs = @(
            New-DriverPackage -Oem 'oem20.inf' -Inf 'usbaudio.inf' -Provider 'VendorA' -Version '1.0.0.0'
            New-DriverPackage -Oem 'oem21.inf' -Inf 'usbaudio.inf' -Provider 'VendorB' -Version '5.0.0.0'
        )
        @(Get-SupersededDriverCandidate -Packages $pkgs).Count | Should -Be 0
    }

    It "Does not flag same-version packages even when their dates differ" {
        # v2.18: 'superseded' requires a STRICTLY newer version. Two packages tied at the
        # same version are both kept - a newer date alone is not obsolescence, and deleting
        # one would be wider than the documented safety contract. (Replaces the old
        # date-tie-breaker test, which asserted exactly the behavior now removed.)
        $pkgs = @(
            New-DriverPackage -Oem 'oem30.inf' -Inf 'x.inf' -Version '1.0.0.0' -Date '2020-01-01'
            New-DriverPackage -Oem 'oem31.inf' -Inf 'x.inf' -Version '1.0.0.0' -Date '2025-01-01'
        )
        @(Get-SupersededDriverCandidate -Packages $pkgs).Count | Should -Be 0
    }

    It "Flags a strictly older version but keeps a same-version sibling" {
        # Mixed group: v1 is strictly older (flagged), the two v2 packages are tied at the
        # max version (both kept). If the guard regressed to comparing Oem instead of
        # Version, the older-dated v2 package would be wrongly flagged and Count would be 2.
        $pkgs = @(
            New-DriverPackage -Oem 'oem50.inf' -Inf 'x.inf' -Version '1.0.0.0'
            New-DriverPackage -Oem 'oem51.inf' -Inf 'x.inf' -Version '2.0.0.0' -Date '2020-01-01'
            New-DriverPackage -Oem 'oem52.inf' -Inf 'x.inf' -Version '2.0.0.0' -Date '2025-01-01'
        )
        $result = @(Get-SupersededDriverCandidate -Packages $pkgs)
        $result.Count | Should -Be 1
        $result[0].Oem | Should -Be 'oem50.inf'
    }

    It "Flags every older version, not just one, when there are several" {
        $pkgs = @(
            New-DriverPackage -Oem 'oem40.inf' -Inf 'x.inf' -Version '1.0.0.0'
            New-DriverPackage -Oem 'oem41.inf' -Inf 'x.inf' -Version '2.0.0.0'
            New-DriverPackage -Oem 'oem42.inf' -Inf 'x.inf' -Version '3.0.0.0'
        )
        $result = @(Get-SupersededDriverCandidate -Packages $pkgs)
        $result.Count | Should -Be 2
        ($result.Oem | Sort-Object) | Should -Be @('oem40.inf', 'oem41.inf')
    }

    It "Returns nothing for an empty package list" {
        @(Get-SupersededDriverCandidate -Packages @()).Count | Should -Be 0
    }
}

#endregion

#region Recovery Marker Tests (v2.17, p.13 of the audit)

Describe "Set-RunMarker / Clear-RunMarker / Invoke-StaleMarkerRecovery" -Tag "Unit", "Helper" {
    <#
    Only the marker lifecycle (write/read/detect-foreign-pid/clean-up) is tested here.
    The per-phase RECOVERY ACTIONS themselves (resetting a real registry value,
    restarting real wuauserv/bits) touch actual OS state that a unit test must not
    mutate - same reasoning as the sandboxed-vs-shadowed split in
    Integration.Tests.ps1. A bogus, unrecognized phase name exercises the same
    detect/warn/clean-up path without going anywhere near the registry or services.
    #>

    BeforeAll {
        $markerPath = Get-RunMarkerPath
    }

    AfterEach {
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    }

    It "Writes a marker with Phase, Pid and any extra data" {
        Set-RunMarker -Phase 'TestPhase' -Data @{ PreviousValue = 42 }
        Test-Path $markerPath | Should -BeTrue
        $marker = Get-Content $markerPath -Raw | ConvertFrom-Json
        $marker.Phase | Should -Be 'TestPhase'
        $marker.Pid | Should -Be $PID
        $marker.PreviousValue | Should -Be 42
    }

    It "Clear-RunMarker removes the file" {
        Set-RunMarker -Phase 'TestPhase'
        Clear-RunMarker
        Test-Path $markerPath | Should -BeFalse
    }

    It "Does nothing when no marker file exists" {
        { Invoke-StaleMarkerRecovery } | Should -Not -Throw
    }

    It "Ignores a marker written by this same process (not evidence of a crash)" {
        Set-RunMarker -Phase 'TestPhase'
        $before = $script:Stats.WarningsCount
        Invoke-StaleMarkerRecovery
        $script:Stats.WarningsCount | Should -Be $before
        Test-Path $markerPath | Should -BeTrue   # left alone - this run still owns it
    }

    It "Removes a marker with an unrecognized phase from a foreign pid without throwing" {
        # A pid that is certainly not this process
        [pscustomobject]@{ Phase = 'SomePhaseThisVersionDoesNotKnow'; Pid = 999999; Timestamp = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
        { Invoke-StaleMarkerRecovery } | Should -Not -Throw
        Test-Path $markerPath | Should -BeFalse
    }

    It "Warns when it finds a marker from a foreign pid" {
        [pscustomobject]@{ Phase = 'SomePhaseThisVersionDoesNotKnow'; Pid = 999999; Timestamp = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
        $before = $script:Stats.WarningsCount
        Invoke-StaleMarkerRecovery
        $script:Stats.WarningsCount | Should -BeGreaterThan $before
    }

    It "Removes a corrupted marker file instead of throwing" {
        "not valid json {{{" | Set-Content -LiteralPath $markerPath -Encoding utf8
        { Invoke-StaleMarkerRecovery } | Should -Not -Throw
        Test-Path $markerPath | Should -BeFalse
    }

    It "Restarts only the services the marker names, not every stopped service" {
        # Found by external review: recovery used to start any stopped wuauserv/bits,
        # which would fight an administrator who disabled one deliberately. The marker
        # now carries the exact list, and a name that matches no real service proves
        # the loop is driven by that list (Get-Service finds nothing, nothing happens).
        [pscustomobject]@{
            Phase = 'WUServiceStop'; Pid = 999999; Timestamp = (Get-Date).ToString('o')
            ServicesToRestart = @('WinCleanNoSuchService_ForTest')
        } | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8

        { Invoke-StaleMarkerRecovery } | Should -Not -Throw
        # Nothing to repair -> recovery counts as successful -> marker cleaned up
        Test-Path $markerPath | Should -BeFalse
    }

    It "Tolerates a WUServiceStop marker with no service list (older format)" {
        [pscustomobject]@{ Phase = 'WUServiceStop'; Pid = 999999; Timestamp = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
        { Invoke-StaleMarkerRecovery } | Should -Not -Throw
        Test-Path $markerPath | Should -BeFalse
    }
}

Describe "Restore-RestorePointFrequency" -Tag "Unit", "Helper" {
    <#
    Only the "nothing to do" path is exercised - it is the one that must never touch
    the registry. The repair path itself writes to HKLM, which a unit test must not do
    on the machine it runs on.
    #>

    It "Reports success and changes nothing when the value is not our 0 override" {
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $before = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency

        # Skip only in the rare case the live machine really is sitting at 0: the test
        # would then be asking the function to perform a real repair
        if ($before -eq 0) {
            Set-ItResult -Skipped -Because 'this machine currently has the override value 0 set'
            return
        }

        Restore-RestorePointFrequency -PreviousValue 1440 | Should -BeTrue

        $after = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        $after | Should -Be $before
    }
}

#endregion

#region Get-FolderSize Tests

Describe "Get-FolderSize" -Tag "Unit", "Helper" {

    BeforeAll {
        $testRoot = Join-Path $env:TEMP "PesterTest_FolderSize_$(Get-Random)"
    }

    AfterAll {
        if (Test-Path $testRoot) {
            Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Returns 0 for non-existent path" {
        Get-FolderSize -Path "C:\NonExistent\Path\12345\67890" | Should -Be 0
    }

    It "Returns 0 for empty folder" {
        $emptyFolder = Join-Path $testRoot "EmptyFolder"
        New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null

        Get-FolderSize -Path $emptyFolder | Should -Be 0
    }

    It "Calculates size correctly for single file" {
        $singleFileFolder = Join-Path $testRoot "SingleFile"
        New-Item -ItemType Directory -Path $singleFileFolder -Force | Out-Null

        # Create a file with known content (13 bytes for "test content\n" or similar)
        $testContent = "test content"
        $testFile = Join-Path $singleFileFolder "file.txt"
        [System.IO.File]::WriteAllText($testFile, $testContent)
        $expectedSize = (Get-Item $testFile).Length

        Get-FolderSize -Path $singleFileFolder | Should -Be $expectedSize
    }

    It "Calculates size recursively" {
        $recursiveFolder = Join-Path $testRoot "Recursive"
        $subFolder = Join-Path $recursiveFolder "SubFolder"
        New-Item -ItemType Directory -Path $subFolder -Force | Out-Null

        $content1 = "file1 content"
        $content2 = "file2 content in subfolder"

        [System.IO.File]::WriteAllText((Join-Path $recursiveFolder "file1.txt"), $content1)
        [System.IO.File]::WriteAllText((Join-Path $subFolder "file2.txt"), $content2)

        $file1Size = (Get-Item (Join-Path $recursiveFolder "file1.txt")).Length
        $file2Size = (Get-Item (Join-Path $subFolder "file2.txt")).Length
        $expectedTotal = $file1Size + $file2Size

        Get-FolderSize -Path $recursiveFolder | Should -Be $expectedTotal
    }

    It "Uses -File flag (B2 fix verification)" {
        # Verify the function definition includes -File flag
        $scriptPath = Join-Path $PSScriptRoot ".." "WinClean.ps1"
        $content = Get-Content $scriptPath -Raw

        # The fix adds -File flag to Get-ChildItem in Get-FolderSize
        $content | Should -Match 'Get-ChildItem.*-File'
    }
}

Describe "Test-DiskpartCompactionFailed" -Tag "Unit", "Helper" {
    # v2.18 (#1 of the external review): the diskpart failure decision, unit-tested
    # without a real VHDX. A non-zero exit OR an English error marker means failure.

    It "Treats a non-zero exit code as failure regardless of output" {
        Test-DiskpartCompactionFailed -Output 'DiskPart successfully compacted the virtual disk file.' -ExitCode 1 | Should -BeTrue
    }

    It "Treats exit 0 with clean output as success" {
        Test-DiskpartCompactionFailed -Output "DiskPart successfully compacted the virtual disk file.`n" -ExitCode 0 | Should -BeFalse
    }

    It "Treats exit 0 with empty output as success" {
        Test-DiskpartCompactionFailed -Output '' -ExitCode 0 | Should -BeFalse
    }

    It "Catches an error marker even when the exit code is 0" -ForEach @(
        @{ Text = 'DiskPart has encountered an error: The parameter is incorrect.' }
        @{ Text = 'Virtual Disk Service error: The volume is not offline.' }
        @{ Text = 'There is no virtual disk selected.' }
        @{ Text = 'Access is denied.' }
    ) {
        Test-DiskpartCompactionFailed -Output $Text -ExitCode 0 | Should -BeTrue
    }
}

Describe "Get-FolderSizeChecked" -Tag "Unit", "Helper" {
    # v2.18 (+A of the external review): distinguishes "empty" (0) from "could not
    # measure" ($null). A genuinely absent path must be 0, not $null.

    BeforeAll {
        $fscRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wc-fsc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fscRoot -Force | Out-Null
    }
    AfterAll {
        Remove-Item $fscRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Returns 0 (not null) for a genuinely absent path" {
        # A NotFound must read as 'empty', never as 'unmeasurable' - Should -Be 0 also
        # fails on $null, so it pins both the value and the not-null contract.
        Get-FolderSizeChecked -Path (Join-Path $fscRoot 'no-such-dir') | Should -Be 0
    }

    It "Returns 0 for an empty folder" {
        $empty = Join-Path $fscRoot 'empty'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        Get-FolderSizeChecked -Path $empty | Should -Be 0
    }

    It "Sums file sizes across subfolders" {
        $tree = Join-Path $fscRoot 'tree'
        $sub = Join-Path $tree 'sub'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $tree 'a.txt'), 'hello')
        [System.IO.File]::WriteAllText((Join-Path $sub 'b.txt'), 'world!!')
        $expected = (Get-Item (Join-Path $tree 'a.txt')).Length + (Get-Item (Join-Path $sub 'b.txt')).Length
        Get-FolderSizeChecked -Path $tree | Should -Be $expected
    }
}

#endregion

#region New-RunStats Tests (v2.20)

Describe "New-RunStats" -Tag "Unit", "Helper", "V220" {
    <#
    v2.19 reset only the phase buckets and the step counter while claiming to handle
    "dot-source and call Start-WinClean twice". Everything else survived into the second
    run's summary and JSON. These tests pin the whole object, not just the three arrays.
    #>
    It "Returns a fresh object rather than the live one" {
        $saved = $script:Stats
        try {
            $script:Stats.TotalFreedBytes = 123456
            $script:Stats.WarningsCount = 7
            $script:Stats.ErrorsCount = 3
            $script:Stats.Aborted = 'PendingRebootDeclined'
            $script:Stats.PhasesCompleted = @('Preparation')

            $fresh = New-RunStats

            $fresh.TotalFreedBytes | Should -Be 0
            $fresh.WarningsCount | Should -Be 0
            $fresh.ErrorsCount | Should -Be 0
            $fresh.Aborted | Should -BeNullOrEmpty
            @($fresh.PhasesCompleted).Count | Should -Be 0
            @($fresh.FreedByCategory.Keys).Count | Should -Be 0
        } finally {
            $script:Stats = $saved
        }
    }

    It "Starts the clock at creation, not at dot-source time" {
        # DurationSeconds in the result JSON is computed from StartTime; a stale value
        # made the second run in a session look hours long
        $before = Get-Date
        Start-Sleep -Milliseconds 20
        (New-RunStats).StartTime | Should -BeGreaterThan $before
    }

    It "Is still a synchronized hashtable" {
        # Parallel cleanup blocks rely on this
        (New-RunStats).GetType().Name | Should -Be 'SyncHashtable'
    }
}

#endregion

#region Get-RegistryValueCount Tests (v2.20)

Describe "Get-RegistryValueCount" -Tag "Unit", "Helper" {
    <#
    Extracted in v2.20 so privacy cleanup can confirm a deletion instead of announcing it.
    Tested against a key this suite creates itself - never against the user's real Explorer
    history, which the product function does touch.
    #>
    BeforeAll {
        $script:probeKey = "HKCU:\Software\WinCleanTest_$(Get-Random)"
        New-Item -Path $script:probeKey -Force | Out-Null
    }

    AfterAll {
        Remove-Item -LiteralPath $script:probeKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Counts nothing for a key that holds no values" {
        # The PowerShell metadata (PSPath, PSProvider and friends) must not be counted,
        # or an emptied key would look like it still holds five entries
        Get-RegistryValueCount -Key $script:probeKey | Should -Be 0
    }

    It "Counts the real values" {
        Set-ItemProperty -Path $script:probeKey -Name 'url1' -Value 'a'
        Set-ItemProperty -Path $script:probeKey -Name 'url2' -Value 'b'
        Get-RegistryValueCount -Key $script:probeKey | Should -Be 2
    }

    It "Returns 0 for a key that does not exist" {
        Get-RegistryValueCount -Key "HKCU:\Software\WinCleanTest_NoSuchKey_$(Get-Random)" | Should -Be 0
    }

    It "Returns null - not 0 - for a key that exists but cannot be read" {
        # The distinction is the whole point. The first draft of this helper returned 0
        # for an unreadable key, which recreated the bug it was written to fix: a delete
        # that failed followed by an unreadable check would have counted as "cleared".
        # Mocked rather than ACL-denied: creating a genuinely unreadable HKCU key on the
        # developer's own machine is a side effect a unit test has no business leaving.
        Mock Get-ItemProperty { throw [System.UnauthorizedAccessException]::new('denied') }
        # Strictly $null, not "null or empty": the caller decides with `$null -eq $before`,
        # and an empty array satisfies BeNullOrEmpty while failing that test, so the
        # unreadable key would have fallen through and been reported as cleared.
        $count = Get-RegistryValueCount -Key $script:probeKey
        ($null -eq $count) | Should -BeTrue
    }
}

#endregion

#region Test-PathProtected Tests

Describe "Test-PathProtected" -Tag "Unit", "Helper", "Security" {

    It "Returns true for <Path>" -ForEach @(
        @{ Path = $env:SystemRoot }
        @{ Path = "$env:SystemRoot\System32" }
        @{ Path = $env:ProgramFiles }
        @{ Path = $env:USERPROFILE }
    ) {
        Test-PathProtected -Path $Path | Should -BeTrue
    }

    It "Returns false for temp paths" {
        Test-PathProtected -Path "$env:TEMP\test" | Should -BeFalse
        Test-PathProtected -Path "$env:LOCALAPPDATA\Temp\test" | Should -BeFalse
    }

    It "Returns false for arbitrary paths" {
        Test-PathProtected -Path "C:\SomeRandomFolder" | Should -BeFalse
        Test-PathProtected -Path "D:\Projects\Test" | Should -BeFalse
    }

    Context "Reparse points (v2.20)" {
        <#
        Measured, not assumed: [System.IO.Path]::GetFullPath does NOT resolve a junction,
        so every textual check above passes for a link whose target is protected, while
        Get-ChildItem on that link lists the TARGET's children. The guard must resolve the
        link. The second test is the one that keeps the fix honest - refusing every link
        would be trivially "safe" and would break anyone who redirected a cache folder.
        #>
        BeforeAll {
            $script:linkSandbox = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanLinkTest_$(Get-Random)"
            $script:innocentTarget = Join-Path $script:linkSandbox 'innocent-target'
            New-Item -ItemType Directory -Path $script:innocentTarget -Force | Out-Null

            $script:linkToProtected = Join-Path $script:linkSandbox 'looks-harmless'
            $script:linkToInnocent  = Join-Path $script:linkSandbox 'redirected-cache'
            $script:linkToDrive     = Join-Path $script:linkSandbox 'volume-link'
            New-Item -ItemType Junction -Path $script:linkToProtected -Target $env:ProgramFiles -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Junction -Path $script:linkToInnocent -Target $script:innocentTarget -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Junction -Path $script:linkToDrive -Target "$env:SystemDrive\" -ErrorAction SilentlyContinue | Out-Null
        }

        AfterAll {
            # Deleting a junction removes the link and leaves the target alone (measured),
            # but remove the links explicitly anyway before the sandbox
            foreach ($l in $script:linkToProtected, $script:linkToInnocent, $script:linkToDrive) {
                if ($l -and (Test-Path -LiteralPath $l)) {
                    Remove-Item -LiteralPath $l -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -LiteralPath $script:linkSandbox -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Refuses a junction that points at a protected root" {
            Test-Path -LiteralPath $script:linkToProtected | Should -BeTrue -Because 'without the junction this test proves nothing'
            Test-PathProtected -Path $script:linkToProtected | Should -BeTrue
        }

        It "Still allows a junction that points somewhere harmless" {
            Test-Path -LiteralPath $script:linkToInnocent | Should -BeTrue -Because 'without the junction this test proves nothing'
            Test-PathProtected -Path $script:linkToInnocent | Should -BeFalse
        }

        It "Refuses a path whose ANCESTOR is a junction into a protected area" {
            # The case the first version of this fix missed, found by review and measured:
            # the leaf carries no reparse attribute, GetFullPath does not resolve the link
            # above it, and 120 real C:\Windows children were visible through it.
            $throughLink = Join-Path $script:linkToDrive 'Windows'
            Test-Path -LiteralPath $throughLink | Should -BeTrue -Because 'the path must really resolve through the junction'
            Test-PathProtected -Path $throughLink | Should -BeTrue
        }

        It "Does not refuse a deep path under a harmless junction" {
            # The other half: refusing everything under any link would be trivially safe
            # and would break anyone whose cache folder is redirected
            $deep = Join-Path $script:linkToInnocent 'sub'
            New-Item -ItemType Directory -Path $deep -Force | Out-Null
            Test-PathProtected -Path $deep | Should -BeFalse
        }

        It "Refuses a path whose links could not be resolved at all" {
            # Resolve-PathThroughLinks answers $null for "I could not work out where this
            # really points" - an unreadable ancestor, or a chain deeper than the loop
            # bound. Both used to return a partially resolved path instead, which was then
            # judged on its text and came back "safe to empty".
            Mock Resolve-PathThroughLinks { $null }
            Test-PathProtected -Path $script:linkToInnocent | Should -BeTrue
        }

        It "Treats a drive that is not mounted as absent, not as unexaminable" {
            # DriveNotFoundException is a not-found answer. Landing in the refuse arm made
            # every cleanup target on an unmapped drive a "Protected path skipped" WARNING,
            # which is noise in the channel this release uses as its failure alarm.
            $free = 'QWXYZJ'.ToCharArray() | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
            $free | Should -Not -BeNullOrEmpty -Because 'the test needs a drive letter that is genuinely unmapped'
            Test-PathProtected -Path "${free}:\SomeFolder" | Should -BeFalse
        }
    }

    It "Handles trailing slashes correctly" {
        # Path with trailing slash should match protected path without trailing slash
        Test-PathProtected -Path "$env:SystemRoot\" | Should -BeTrue
        Test-PathProtected -Path "$env:SystemRoot/" | Should -BeTrue
    }

    It "Is case-insensitive" {
        $upperPath = $env:SystemRoot.ToUpper()
        $lowerPath = $env:SystemRoot.ToLower()

        Test-PathProtected -Path $upperPath | Should -BeTrue
        Test-PathProtected -Path $lowerPath | Should -BeTrue
    }
}

#endregion

#region Test-InteractiveConsole Tests

Describe "Test-InteractiveConsole" -Tag "Unit", "Helper" {

    It "Does not throw" {
        { Test-InteractiveConsole } | Should -Not -Throw
    }

    It "Returns a boolean" {
        $result = Test-InteractiveConsole
        $result | Should -BeOfType [bool]
    }

    # Note: The actual return value depends on the test environment
    # In CI (GitHub Actions), it typically returns $false
    # In interactive console, it returns $true
}

#endregion

#region Test-PendingReboot Tests

Describe "Test-PendingReboot" -Tag "Unit", "Helper" {

    It "Returns a hashtable with expected keys" {
        $result = Test-PendingReboot

        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain 'RebootRequired'
        $result.Keys | Should -Contain 'Reasons'
    }

    It "RebootRequired is boolean" {
        $result = Test-PendingReboot
        $result.RebootRequired | Should -BeOfType [bool]
    }

    It "Reasons is enumerable (array or single value)" {
        $result = Test-PendingReboot
        # Reasons can be empty array, single string, or array of strings
        # We just verify it exists and can be iterated
        { @($result.Reasons) } | Should -Not -Throw
    }

    It "Does not throw without admin rights" {
        # The function should handle access denied gracefully
        { Test-PendingReboot } | Should -Not -Throw
    }
}

#endregion

#region Write-Log Tests

Describe "Write-Log" -Tag "Unit", "Helper" {

    BeforeAll {
        $testLogPath = Join-Path $env:TEMP "PesterTest_WriteLog_$(Get-Random).log"
        $script:LogPath = $testLogPath
    }

    AfterAll {
        if (Test-Path $testLogPath) {
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "Does not throw for any log level" -ForEach @(
        @{ Level = 'INFO' }
        @{ Level = 'SUCCESS' }
        @{ Level = 'WARNING' }
        @{ Level = 'ERROR' }
        @{ Level = 'TITLE' }
        @{ Level = 'SECTION' }
        @{ Level = 'DETAIL' }
    ) {
        { Write-Log -Message "Test message" -Level $Level } | Should -Not -Throw
    }

    It "Writes to log file" {
        $uniqueMsg = "Unique test message $(Get-Random)"
        Write-Log -Message $uniqueMsg -Level INFO

        # Allow small delay for file write
        Start-Sleep -Milliseconds 100

        # v2.20: the assertion used to sit inside `if (Test-Path $script:LogPath)`, so a
        # missing log file made this test pass. A missing log file is exactly the defect
        # it exists to catch (v2.14: the log was deleted by the script's own temp cleanup),
        # which made it a test that could not fail for its own bug. Assert the
        # precondition instead of hiding behind it.
        Test-Path $script:LogPath | Should -BeTrue -Because 'Write-Log must create the log file'
        (Get-Content $script:LogPath -Raw) | Should -Match $uniqueMsg
    }

    It "Respects -NoLog switch" {
        $noLogMsg = "NoLog message $(Get-Random)"

        # Anchor write: without an existing log file "the message is absent from the log"
        # is true for the boring reason that there is no log at all
        Write-Log -Message "Anchor $(Get-Random)" -Level INFO
        Start-Sleep -Milliseconds 100
        Test-Path $script:LogPath | Should -BeTrue -Because 'the -NoLog check is meaningless without a real log file'
        $sizeBefore = (Get-Item $script:LogPath).Length

        Write-Log -Message $noLogMsg -Level INFO -NoLog
        Start-Sleep -Milliseconds 100

        # Two independent facts. The size comparison is what $sizeBefore was computed for
        # since the test was written and never actually used until v2.20: it catches a
        # -NoLog that writes something else to the file, which a text match would miss.
        (Get-Content $script:LogPath -Raw) | Should -Not -Match $noLogMsg
        (Get-Item $script:LogPath).Length | Should -Be $sizeBefore
    }
}

#endregion

#region Write-LogFileLine Tests (v2.22 - log init must never kill the run)

Describe "Write-LogFileLine" -Tag "Unit", "Helper", "V222" {

    BeforeEach {
        $script:prevLogPath  = $script:LogPath
        $script:prevWarnings = $script:Stats.WarningsCount
        $script:prevFailed   = $script:LogWriteFailed
        if ($script:LogWriter) { $script:LogWriter.Dispose(); $script:LogWriter = $null; $script:LogWriterPath = $null }
        $script:LogWriteFailed = $false
        $script:testLog = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanLogLine_$(Get-Random).log"
        $script:LogPath = $script:testLog
    }

    AfterEach {
        if ($script:LogWriter) { $script:LogWriter.Dispose(); $script:LogWriter = $null; $script:LogWriterPath = $null }
        Remove-Item -LiteralPath $script:testLog -Force -ErrorAction SilentlyContinue
        $script:LogPath              = $script:prevLogPath
        $script:Stats.WarningsCount  = $script:prevWarnings
        $script:LogWriteFailed       = $script:prevFailed
    }

    It "Writes the line verbatim, without adding a timestamp or level" {
        # The header is not a log entry: it must land exactly as composed. Write-Log's
        # "[HH:mm:ss] [LEVEL] " prefix belongs to Write-Log, not to this primitive.
        Write-LogFileLine -Line 'WinClean v9.99 - Started at whenever' -StartNewFile
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Match ([regex]::Escape('WinClean v9.99 - Started at whenever'))
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Not -Match '^\['
    }

    It "Appends by default and truncates only with -StartNewFile" {
        # -StartNewFile preserves what the replaced Out-File (no -Append) did. Losing it
        # would silently merge every run sharing a custom -LogPath into one file.
        Write-LogFileLine -Line 'first run'  -StartNewFile
        Write-LogFileLine -Line 'same run'
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Match 'first run'
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Match 'same run'

        Write-LogFileLine -Line 'second run' -StartNewFile
        $after = Get-Content -LiteralPath $script:testLog -Raw
        $after | Should -Match 'second run'
        $after | Should -Not -Match 'first run' -Because '-StartNewFile must truncate, matching the Out-File it replaced'
    }

    # The defect this whole function exists for. Measured in review: six of seven bad log
    # paths make Out-File throw a TERMINATING error even at ErrorActionPreference=Continue,
    # and the header is written before Start-WinClean's try/finally exists - so the run
    # died with no result JSON and no maintenance because of the log file.
    It "Never throws on a log path that cannot be opened - <Case>" -ForEach @(
        @{ Case = 'missing directory';    Path = { Join-Path ([System.IO.Path]::GetTempPath()) "nope_$(Get-Random)\sub\a.log" } }
        @{ Case = 'path is a directory';  Path = { [System.IO.Path]::GetTempPath() } }
        @{ Case = 'invalid characters';   Path = { Join-Path ([System.IO.Path]::GetTempPath()) 'a:b:c.log' } }
        @{ Case = 'over-long path';       Path = { Join-Path ([System.IO.Path]::GetTempPath()) (('x' * 300) + '.log') } }
        # An unreachable UNC path was measured too (IOException, same as the two above) but
        # is deliberately not a case here: it is the only one that depends on network
        # resolution, took 8.3s locally, and would be this suite's one flake-prone test.
    ) {
        $script:LogPath = & $Path
        { Write-LogFileLine -Line 'header' -StartNewFile } | Should -Not -Throw -Because 'a log that cannot be written is a degraded run, never a failed one'
    }

    It "Reports the failure instead of swallowing it - LoggingDegraded reaches the result JSON" {
        # Not throwing must not become not telling. LogWriteFailed is what surfaces as
        # LoggingDegraded in the result JSON, so an automated consumer can see the run's
        # log is incomplete rather than trusting a silent success.
        $script:LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "nope_$(Get-Random)\sub\a.log"
        $before = $script:Stats.WarningsCount

        Write-LogFileLine -Line 'header' -StartNewFile 3>$null 6>$null

        $script:LogWriteFailed          | Should -BeTrue -Because 'LoggingDegraded in the result JSON is driven by this flag'
        $script:Stats.WarningsCount     | Should -Be ($before + 1)
    }

    It "Latches the warning - a failing log costs one warning, not one per line" {
        $script:LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "nope_$(Get-Random)\sub\a.log"
        $before = $script:Stats.WarningsCount

        1..5 | ForEach-Object { Write-LogFileLine -Line "line $_" 3>$null 6>$null }

        $script:Stats.WarningsCount | Should -Be ($before + 1) -Because 'Write-Log fires hundreds of times per run'
    }

    It "Recovers when the path becomes writable again" {
        # The v2.20 lesson kept: drop the dead writer so a later call reopens it, instead
        # of leaving the guard satisfied by a broken object and discarding the rest.
        $script:LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "nope_$(Get-Random)\sub\a.log"
        Write-LogFileLine -Line 'lost' -StartNewFile 3>$null 6>$null
        $script:LogWriter | Should -BeNullOrEmpty -Because 'a failed writer must not be reused'

        $script:LogPath = $script:testLog
        Write-LogFileLine -Line 'recovered' -StartNewFile
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Match 'recovered'
    }

    It "Drops a writer whose stream broke mid-run, so later lines are not discarded" {
        # Added after a mutation survived: the test above only covers a writer that never
        # opened, and in that case the field is already $null - so deleting the reset would
        # not have failed anything. This covers the case the reset actually exists for: an
        # open writer whose stream dies later (the v2.14 shape, where the run's own temp
        # cleanup deleted the log out from under it). Without the reset, the guard stays
        # satisfied by a dead object and every remaining line is silently thrown away.
        Write-LogFileLine -Line 'opened fine' -StartNewFile
        $script:LogWriter | Should -Not -BeNullOrEmpty

        # Break the stream underneath the writer without touching the script's bookkeeping
        $script:LogWriter.BaseStream.Dispose()

        Write-LogFileLine -Line 'this write fails' 3>$null 6>$null
        $script:LogWriter | Should -BeNullOrEmpty -Because 'a broken writer must be dropped, not kept and reused'

        # And the very next line must actually reach the file again
        Write-LogFileLine -Line 'back in business'
        (Get-Content -LiteralPath $script:testLog -Raw) | Should -Match 'back in business'
    }
}

#endregion

#region Get-RecycleBinSize Tests

Describe "Get-RecycleBinSize" -Tag "Unit", "Helper" {

    It "Returns a number" {
        $result = Get-RecycleBinSize
        $result | Should -BeOfType [long]
    }

    It "Returns non-negative value" {
        $result = Get-RecycleBinSize
        $result | Should -BeGreaterOrEqual 0
    }

    It "Does not throw" {
        { Get-RecycleBinSize } | Should -Not -Throw
    }
}

#endregion

#region Invoke-Phase Tests (v2.19)

Describe "Invoke-Phase dispatch status" -Tag "Unit", "Helper" {

    BeforeEach {
        # Invoke-Phase records into the shared run stats and the run log; start clean
        $script:Stats.PhasesCompleted = @()
        $script:Stats.PhasesFailed    = @()
        $script:Stats.PhasesSkipped   = @()
        $script:Stats.ErrorsCount     = 0
    }

    It "Records a normal phase as Completed and runs its action" {
        $marker = [pscustomobject]@{ Ran = $false }
        Invoke-Phase -Name 'Normal' -Action { $marker.Ran = $true }

        $marker.Ran                   | Should -BeTrue
        $script:Stats.PhasesCompleted | Should -Contain 'Normal'
        $script:Stats.PhasesSkipped   | Should -Not -Contain 'Normal'
        $script:Stats.PhasesFailed    | Should -Not -Contain 'Normal'
    }

    It "Records a throwing phase as Failed and counts the error" {
        $before = [int]$script:Stats.ErrorsCount
        Invoke-Phase -Name 'Boom' -Action { throw "kaboom" }

        $script:Stats.PhasesFailed     | Should -Contain 'Boom'
        $script:Stats.PhasesCompleted  | Should -Not -Contain 'Boom'
        $script:Stats.PhasesSkipped    | Should -Not -Contain 'Boom'
        [int]$script:Stats.ErrorsCount | Should -BeGreaterThan $before
    }

    It "Records a -Skip phase as Skipped and never runs its action" {
        $marker = [pscustomobject]@{ Ran = $false }
        Invoke-Phase -Name 'Off' -Skip:$true -Action { $marker.Ran = $true }

        $marker.Ran                   | Should -BeFalse
        $script:Stats.PhasesSkipped   | Should -Contain 'Off'
        $script:Stats.PhasesCompleted | Should -Not -Contain 'Off'
        $script:Stats.PhasesFailed    | Should -Not -Contain 'Off'
    }

    It "Runs the phase normally when -Skip is false" {
        $marker = [pscustomobject]@{ Ran = $false }
        Invoke-Phase -Name 'On' -Skip:$false -Action { $marker.Ran = $true }

        $marker.Ran                   | Should -BeTrue
        $script:Stats.PhasesCompleted | Should -Contain 'On'
    }

    It "Logs the skip reason so the operational evidence survives (R1)" {
        # Hermetic log: other tests in this file reassign $script:LogPath, so pin our own
        # and let Write-Log reopen its writer on the new path (it reopens when the path
        # differs from the writer's). AutoFlush + FileShare.ReadWrite make it readable now.
        $prevPath = $script:LogPath
        $logFile  = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanPhaseLog_$(Get-Random).log"
        $script:LogPath = $logFile
        try {
            Invoke-Phase -Name 'LoggedSkip' -Skip:$true -Action { }
            (Get-Content -LiteralPath $logFile -Raw) | Should -Match "Phase 'LoggedSkip' skipped \(parameter\)"
        } finally {
            if ($script:LogWriter) { $script:LogWriter.Dispose(); $script:LogWriter = $null; $script:LogWriterPath = $null }
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
            $script:LogPath = $prevPath
        }
    }

    It "Routes every phase into exactly one bucket - buckets disjoint, union complete" {
        # Mechanism-level check of the tri-state invariant the result JSON relies on:
        # for a non-aborted run the three arrays are disjoint and their union is the
        # full dispatched set. Drive a representative mix through the same wrapper.
        $plan = @(
            @{ Name = 'A'; Skip = $false; Throws = $false }  # -> Completed
            @{ Name = 'B'; Skip = $true;  Throws = $false }  # -> Skipped
            @{ Name = 'C'; Skip = $false; Throws = $true  }  # -> Failed
            @{ Name = 'D'; Skip = $true;  Throws = $false }  # -> Skipped
            @{ Name = 'E'; Skip = $false; Throws = $false }  # -> Completed
        )
        foreach ($p in $plan) {
            Invoke-Phase -Name $p.Name -Skip:$p.Skip -Action { if ($p.Throws) { throw 'x' } }
        }

        $completed = @($script:Stats.PhasesCompleted)
        $skipped   = @($script:Stats.PhasesSkipped)
        $failed    = @($script:Stats.PhasesFailed)
        $union     = @($completed + $skipped + $failed)

        # disjoint: no name in two buckets (distinct count == total count)
        ($union | Sort-Object -Unique).Count | Should -Be $union.Count
        # complete: union is exactly the dispatched set
        (($union | Sort-Object -Unique) -join ',') | Should -Be 'A,B,C,D,E'
        # and each landed where intended
        ($completed -join ',') | Should -Be 'A,E'
        ($skipped   -join ',') | Should -Be 'B,D'
        ($failed    -join ',') | Should -Be 'C'
    }
}

#endregion

#region Update-Progress / Measure-FreeSpaceGain / Show-Banner Tests (v2.19, dtx8 p.22)

Describe "Update-Progress" -Tag "Unit", "Helper", "V219" {

    BeforeEach {
        $script:Stats.CurrentStep  = 0
        $script:Stats.TotalSteps   = 10
        $script:ProgressActivities = @()
    }

    It "increments the step counter on each call" {
        Mock Write-Progress {}
        Update-Progress -Activity 'A'
        $script:Stats.CurrentStep | Should -Be 1
        Update-Progress -Activity 'A'
        $script:Stats.CurrentStep | Should -Be 2
    }

    It "records each distinct activity once" {
        Mock Write-Progress {}
        Update-Progress -Activity 'A'
        Update-Progress -Activity 'A'
        Update-Progress -Activity 'B'
        (@($script:ProgressActivities) -join ',') | Should -Be 'A,B'
    }

    It "caps the reported percent at 100 when steps exceed the total" {
        # Without the min(100, ...) guard this would report 500% and misdraw the bar
        $script:Stats.TotalSteps  = 2
        $script:Stats.CurrentStep = 9
        Mock Write-Progress {}
        Update-Progress -Activity 'A'
        Should -Invoke Write-Progress -Times 1 -Exactly -ParameterFilter { $PercentComplete -eq 100 }
    }
}

Describe "Measure-FreeSpaceGain" -Tag "Unit", "Helper", "V219" {

    BeforeEach {
        $script:Stats.TotalFreedBytes = [long]0
        $script:Stats.FreedByCategory = @{}
    }

    It "always runs the operation" {
        Mock Get-PSDrive { [pscustomobject]@{ Free = [long]1000 } }
        $marker = [pscustomobject]@{ Ran = $false }
        Measure-FreeSpaceGain -Category 'X' -Operation { $marker.Ran = $true }
        $marker.Ran | Should -BeTrue
    }

    It "attributes a positive free-space gain to the category" {
        $script:mfsgCalls = 0
        Mock Get-PSDrive {
            $script:mfsgCalls++
            [pscustomobject]@{ Free = if ($script:mfsgCalls -eq 1) { [long]1000 } else { [long]1500 } }
        }
        Measure-FreeSpaceGain -Category 'DISM' -Operation { }
        $script:Stats.FreedByCategory['DISM'] | Should -Be 500
        [long]$script:Stats.TotalFreedBytes   | Should -Be 500
    }

    It "discards a negative delta when the drive shrank during the operation" {
        $script:mfsgCalls = 0
        Mock Get-PSDrive {
            $script:mfsgCalls++
            [pscustomobject]@{ Free = if ($script:mfsgCalls -eq 1) { [long]1500 } else { [long]1000 } }
        }
        Measure-FreeSpaceGain -Category 'DISM' -Operation { }
        $script:Stats.FreedByCategory.ContainsKey('DISM') | Should -BeFalse
        [long]$script:Stats.TotalFreedBytes | Should -Be 0
    }
}

Describe "Show-Banner" -Tag "Unit", "Helper", "V219" {
    It "renders without throwing" {
        { Show-Banner *> $null } | Should -Not -Throw
    }
}

# The Storage Sense decision logic. Until v2.20 this branch was unreachable (it looked
# the task up under a folder it does not live in), so the whole of it shipped for six
# versions without a single test - and the first defect found in it after it came alive
# was "exit code 0 counted as proof that a cleanup happened". These cover the rules that
# decide whether all 23 cleanmgr handlers get skipped.

Describe "Select-StorageSenseTask" -Tag "Unit", "Helper", "V220" {

    It "returns the single task when exactly one was found" {
        $one = [pscustomobject]@{ TaskName = 'StorageSense'; TaskPath = '\Microsoft\Windows\DiskFootprint\' }
        $result = Select-StorageSenseTask -Tasks @($one)
        $result.Reason | Should -Be 'ok'
        $result.Task.TaskPath | Should -Be '\Microsoft\Windows\DiskFootprint\'
    }

    It "reports 'none' and no task when nothing was found" {
        $result = Select-StorageSenseTask -Tasks @()
        $result.Reason | Should -Be 'none'
        $result.Task | Should -BeNullOrEmpty
    }

    It "refuses to guess when several tasks share the name" {
        # Starting the first of several same-named tasks means starting something nobody
        # identified. The rule is "take none", not "take one".
        $tasks = @(
            [pscustomobject]@{ TaskName = 'StorageSense'; TaskPath = '\Microsoft\Windows\DiskFootprint\' }
            [pscustomobject]@{ TaskName = 'StorageSense'; TaskPath = '\Custom\' }
        )
        $result = Select-StorageSenseTask -Tasks $tasks
        $result.Reason | Should -Be 'ambiguous'
        $result.Task | Should -BeNullOrEmpty
    }

    It "ignores null entries in the lookup result" {
        $one = [pscustomobject]@{ TaskName = 'StorageSense'; TaskPath = '\Microsoft\Windows\DiskFootprint\' }
        $result = Select-StorageSenseTask -Tasks @($null, $one, $null)
        $result.Reason | Should -Be 'ok'
    }
}

Describe "Get-StorageSenseVerdict" -Tag "Unit", "Helper", "V220" {

    It "does NOT accept a successful exit code as proof that anything was cleaned" {
        # The defect this whole rule exists for: Storage Sense obeys its own settings, so
        # when it is switched off in Settings the task starts, does nothing and exits 0.
        # Treating that as done suppresses every cleanmgr handler and frees nothing.
        $verdict = Get-StorageSenseVerdict -TaskResult 0 -FreedBytes 0
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'nothing-freed'
    }

    It "accepts success only when free space actually grew" {
        $verdict = Get-StorageSenseVerdict -TaskResult 0 -FreedBytes ([long]5MB)
        $verdict.Done | Should -BeTrue
        $verdict.Reason | Should -Be 'success'
    }

    It "is fail-closed on a non-zero task result IN THE TYPE WINDOWS ACTUALLY SUPPLIES" {
        # LastTaskResult is a UInt32. Every HRESULT failure has the high bit set, so its
        # unsigned value exceeds Int32.MaxValue: 0x80040154 arrives as 2147746132 and the
        # old [int] cast THREW on it, taking down the whole DeepSystemCleanup phase.
        #
        # The first version of this test wrote the PowerShell literal 0x80040154, which the
        # parser types as Int32 -2147221164. The cast succeeded, the test was green, and it
        # was green BECAUSE of the defect. Passing the production type is the entire point.
        $realValue = [uint32]2147746132
        $realValue | Should -BeOfType [uint32]
        $verdict = Get-StorageSenseVerdict -TaskResult $realValue -FreedBytes ([long]5MB)
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'failed'
    }

    It "does not throw on the full UInt32 range" {
        { Get-StorageSenseVerdict -TaskResult ([uint32]::MaxValue) -FreedBytes ([long]5MB) } | Should -Not -Throw
    }

    It "treats a result that is not a number as unreadable rather than throwing" {
        $verdict = Get-StorageSenseVerdict -TaskResult 'not-a-number' -FreedBytes ([long]5MB)
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'unreadable'
    }

    It "is fail-closed when the task result could not be read" {
        $verdict = Get-StorageSenseVerdict -TaskResult $null -FreedBytes ([long]5MB)
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'unreadable'
    }

    It "distinguishes 'could not measure' from 'freed nothing'" {
        $verdict = Get-StorageSenseVerdict -TaskResult 0 -FreedBytes $null
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'not-measured'
    }

    It "treats a shrinking drive as no cleanup rather than as success" {
        $verdict = Get-StorageSenseVerdict -TaskResult 0 -FreedBytes ([long](-1MB))
        $verdict.Done | Should -BeFalse
        $verdict.Reason | Should -Be 'nothing-freed'
    }
}

Describe "Wait-StorageSenseTask" -Tag "Unit", "Helper", "V220" {

    # No real waiting: the wait itself is injected, which is the reason this loop was
    # split out of Invoke-StorageSense at all.
    BeforeEach {
        $script:wssCalls = 0
        $script:noWait = { }
    }

    It "reports 'finished' once a running task stops" {
        $getTask = {
            $script:wssCalls++
            if ($script:wssCalls -lt 3) {
                [pscustomobject]@{ State = 'Running' }
            } else {
                [pscustomobject]@{ State = 'Ready' }
            }
        }
        $result = Wait-StorageSenseTask -GetTask $getTask -GetTaskInfo { param($t) $null } `
            -LastRunBefore ([datetime]'2026-07-22 10:00') -TimeoutSeconds 60 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'finished'
        $result.Elapsed | Should -Be 15
    }

    It "reports 'vanished' with the real elapsed time, not the full timeout" {
        # The bug this covers: the loop used to break on a disappearing task while leaving
        # its finished flag false, so the caller announced "did not finish within 120
        # seconds" after ten - a number that never happened on that run.
        $getTask = {
            $script:wssCalls++
            if ($script:wssCalls -eq 1) { [pscustomobject]@{ State = 'Running' } } else { $null }
        }
        $result = Wait-StorageSenseTask -GetTask $getTask -GetTaskInfo { param($t) $null } `
            -LastRunBefore $null -TimeoutSeconds 120 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'vanished'
        $result.Elapsed | Should -Be 10
        $result.Task | Should -BeNullOrEmpty
    }

    It "reports 'timeout' when the task never stops running" {
        $result = Wait-StorageSenseTask -GetTask { [pscustomobject]@{ State = 'Running' } } `
            -GetTaskInfo { param($t) $null } -LastRunBefore $null `
            -TimeoutSeconds 20 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'timeout'
        $result.Elapsed | Should -Be 20
    }

    It "accepts a moved LastRunTime as evidence for a task too quick to be seen running" {
        $result = Wait-StorageSenseTask -GetTask { [pscustomobject]@{ State = 'Ready' } } `
            -GetTaskInfo { param($t) [pscustomobject]@{ LastRunTime = [datetime]'2026-07-22 11:00' } } `
            -LastRunBefore ([datetime]'2026-07-22 10:00') -TimeoutSeconds 60 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'finished'
        # Not before the 10-second mark: a task that was never seen running needs the
        # evidence, and the first poll is too early to distinguish it from a slow start
        $result.Elapsed | Should -Be 10
    }

    It "refuses to call a task finished when there is no baseline to compare against" {
        # The fail-open this replaced: '-not $LastRunBefore' is TRUE when the pre-run read
        # failed, so the disjunction short-circuited and ANY readable task info returned
        # 'finished' for a task that may never have started. That false success went on to
        # skip all 23 cleanmgr handlers.
        $result = Wait-StorageSenseTask -GetTask { [pscustomobject]@{ State = 'Ready' } } `
            -GetTaskInfo { param($t) [pscustomobject]@{ LastRunTime = [datetime]'2026-07-22 11:00' } } `
            -LastRunBefore $null -TimeoutSeconds 60 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'unverifiable'
        # The whole window is used to watch. The first repair returned at ten seconds,
        # which gave a slow-starting task no chance to be seen and let Disk Cleanup start
        # alongside it (raised in the next review round).
        $result.Elapsed | Should -Be 60
    }

    It "still accepts being seen running as evidence when there is no baseline" {
        # Direct observation needs no comparison: if the task was Running and then was not,
        # it ran, whether or not its previous run time could be read.
        $script:wssCalls = 0
        $getTask = {
            $script:wssCalls++
            if ($script:wssCalls -lt 3) { [pscustomobject]@{ State = 'Running' } } else { [pscustomobject]@{ State = 'Ready' } }
        }
        $result = Wait-StorageSenseTask -GetTask $getTask -GetTaskInfo { param($t) $null } `
            -LastRunBefore $null -TimeoutSeconds 60 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'finished'
        $result.Elapsed | Should -Be 15
    }

    It "actually waits when no wait scriptblock is injected" {
        # Every other test here injects a no-op wait, so the default was unpinned: changing
        # it to an empty block left all of them green while production spun through its
        # whole timeout in microseconds and fell back to Disk Cleanup on every run.
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Wait-StorageSenseTask -GetTask { $null } -GetTaskInfo { param($t) $null } `
            -LastRunBefore $null -TimeoutSeconds 2 -CheckInterval 1
        $sw.Stop()
        $result.Outcome | Should -Be 'vanished'
        $sw.Elapsed.TotalMilliseconds | Should -BeGreaterThan 800
    }

    It "does not call a task finished when LastRunTime never moved" {
        $sameTime = [datetime]'2026-07-22 10:00'
        $result = Wait-StorageSenseTask -GetTask { [pscustomobject]@{ State = 'Ready' } } `
            -GetTaskInfo { param($t) [pscustomobject]@{ LastRunTime = $sameTime } } `
            -LastRunBefore $sameTime -TimeoutSeconds 20 -CheckInterval 5 -Wait $script:noWait
        $result.Outcome | Should -Be 'timeout'
    }
}

#endregion

#region v2.21 self-update targeting

Describe "Test-PathInsideRoot" -Tag "Unit", "Helper", "V221" {
    It "accepts a file inside the root" {
        Test-PathInsideRoot -Path 'C:\Program Files\WinClean\WinClean.ps1' -Root 'C:\Program Files\WinClean' |
            Should -BeTrue
    }

    It "does not treat a sibling with a shared prefix as inside the root" {
        # A plain StartsWith without the separator would call C:\Temp2 a child of C:\Temp,
        # labelling a manual copy as the one-liner's temporary download and printing an
        # instruction that does nothing for it
        Test-PathInsideRoot -Path 'C:\Temp2\WinClean.ps1' -Root 'C:\Temp' | Should -BeFalse
    }

    It "ignores case, as the file system does" {
        Test-PathInsideRoot -Path 'c:\program files\winclean\WinClean.ps1' -Root 'C:\Program Files\WinClean' |
            Should -BeTrue
    }

    It "tolerates a trailing separator on the root" {
        Test-PathInsideRoot -Path 'C:\Tools\WinClean\WinClean.ps1' -Root 'C:\Tools\WinClean\' | Should -BeTrue
    }

    It "answers false for <name> instead of throwing" -ForEach @(
        @{ name = 'an empty path'; path = ''; root = 'C:\Temp' }
        @{ name = 'a null path'; path = $null; root = 'C:\Temp' }
        @{ name = 'an empty root'; path = 'C:\Temp\x.ps1'; root = '' }
        @{ name = 'a null root'; path = 'C:\Temp\x.ps1'; root = $null }
    ) {
        Test-PathInsideRoot -Path $path -Root $root | Should -BeFalse
    }
}

Describe "Get-ScriptUpdateChannel" -Tag "Unit", "Helper", "V221" {
    It "calls the running file the gallery copy when it is the gallery copy" {
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Users\u\Documents\PowerShell\Scripts\WinClean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts') | Should -Be 'gallery'
    }

    It "matches the gallery copy regardless of case" {
        Get-ScriptUpdateChannel -ExecutingPath 'c:\users\u\documents\powershell\scripts\winclean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts') | Should -Be 'gallery'
    }

    It "REGRESSION: a gallery copy elsewhere does not make the Program Files copy updatable" {
        # The reported defect exactly: both installs exist, the shortcut starts the
        # Program Files one, and the old code auto-updated the Documents one and told the
        # user to run WinClean again for the new version - which kept starting the old file
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Program Files\WinClean\WinClean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts') `
            -ProgramFilesRoot 'C:\Program Files' | Should -Be 'installer'
    }

    It "refuses the automatic path when several gallery installations exist" {
        # It IS the gallery copy, but Update-Script has no -Scope: with AllUsers and
        # CurrentUser copies present, nothing aims the updater at this one. Modifying the
        # unused copy and only then discovering the miss is worse than declining
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Program Files\WindowsPowerShell\Scripts\WinClean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts', 'C:\Program Files\WindowsPowerShell\Scripts') `
            -ProgramFilesRoot 'C:\NoSuchProgramFiles' | Should -Be 'gallery-ambiguous'
    }

    It "still allows the automatic path when both providers report the same single install" {
        # Duplicates are not ambiguity: PowerShellGet and PSResourceGet each report the
        # other's install, so the same path arriving twice must not disable self-update
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Users\u\Documents\PowerShell\Scripts\WinClean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts', 'C:\Users\u\Documents\PowerShell\Scripts\') `
            | Should -Be 'gallery'
    }

    It "collapses duplicates that differ only in case" {
        # Select-Object -Unique is case-SENSITIVE (verified 22.07.2026), while the match
        # below is case-insensitive. With the two mismatched, one install reported with
        # different casing by the two providers looked like two and silently cost the
        # machine its self-update
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Users\u\Documents\PowerShell\Scripts\WinClean.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts', 'c:\users\u\documents\powershell\scripts') `
            | Should -Be 'gallery'
    }

    It "does not claim a differently named script sharing the gallery folder" {
        # InstalledLocation is a shared Scripts folder; the provider owns WinClean.ps1
        # inside it, not everything that happens to sit there
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Users\u\Documents\PowerShell\Scripts\WinClean-test.ps1' `
            -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts') `
            -ProgramFilesRoot 'C:\Program Files' -TempRoot 'C:\Temp' | Should -Be 'manual'
    }

    It "recognises the temporary copy that get.ps1 downloads" {
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Temp\WinClean-0123abcd\WinClean.ps1' `
            -GalleryLocation @() -ProgramFilesRoot 'C:\Program Files' -TempRoot 'C:\Temp' |
            Should -Be 'oneliner'
    }

    It "returns unknown when the executing path is <name>" -ForEach @(
        @{ name = 'empty'; path = '' }
        @{ name = 'null'; path = $null }
        @{ name = 'whitespace'; path = '   ' }
    ) {
        Get-ScriptUpdateChannel -ExecutingPath $path -GalleryLocation @('C:\Users\u\Documents\PowerShell\Scripts') |
            Should -Be 'unknown'
    }

    It "falls back to manual with no gallery install at all" {
        Get-ScriptUpdateChannel -ExecutingPath 'D:\Downloads\WinClean.ps1' -GalleryLocation @() `
            -ProgramFilesRoot 'C:\Program Files' -TempRoot 'C:\Temp' | Should -Be 'manual'
    }

    It "survives a null location array and null roots" {
        Get-ScriptUpdateChannel -ExecutingPath 'D:\Downloads\WinClean.ps1' -GalleryLocation $null `
            -ProgramFilesRoot $null -TempRoot $null | Should -Be 'manual'
    }

    It "ignores empty entries among the locations" {
        Get-ScriptUpdateChannel -ExecutingPath 'D:\Downloads\WinClean.ps1' -GalleryLocation @('', $null) `
            -ProgramFilesRoot 'C:\Program Files' -TempRoot 'C:\Temp' | Should -Be 'manual'
    }

    It "uses real roots by default, since production never passes them" {
        # Test-ScriptUpdate calls this with no roots at all, yet every other test here
        # supplies them - so mutating either default survived the whole suite. The negative
        # case matters most: a TempRoot collapsing to a drive root would classify every
        # copy on C: as a one-liner download
        $temp = [System.IO.Path]::GetTempPath()
        $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)

        Get-ScriptUpdateChannel -ExecutingPath (Join-Path $temp 'WinClean-abc\WinClean.ps1') `
            -GalleryLocation @() | Should -Be 'oneliner'
        Get-ScriptUpdateChannel -ExecutingPath (Join-Path $programFiles 'WinClean\WinClean.ps1') `
            -GalleryLocation @() | Should -Be 'installer'
        Get-ScriptUpdateChannel -ExecutingPath 'C:\Tools\WinClean\WinClean.ps1' `
            -GalleryLocation @() | Should -Be 'manual'
    }

    It "matches a gallery copy reached over UNC" {
        Get-ScriptUpdateChannel -ExecutingPath '\\fileserver\profiles\u\Documents\PowerShell\Scripts\WinClean.ps1' `
            -GalleryLocation @('\\fileserver\profiles\u\Documents\PowerShell\Scripts') | Should -Be 'gallery'
    }

    It "does not confuse two UNC shares with a shared prefix" {
        Get-ScriptUpdateChannel -ExecutingPath '\\fileserver\profiles2\WinClean.ps1' `
            -GalleryLocation @('\\fileserver\profiles') `
            -ProgramFilesRoot 'C:\Program Files' -TempRoot 'C:\Temp' | Should -Be 'manual'
    }
}

Describe "Get-UpdateVerification" -Tag "Unit", "Helper", "V221" {
    It "confirms an update when the file reports the expected version" {
        $v = Get-UpdateVerification -ExpectedVersion '2.21' -ObservedVersion '2.21'
        $v.Applied | Should -BeTrue
        $v.Reason | Should -Be 'applied'
    }

    It "confirms an update when the file is newer than expected" {
        (Get-UpdateVerification -ExpectedVersion '2.21' -ObservedVersion '2.22').Applied | Should -BeTrue
    }

    It "reports unchanged when the file kept the old version" {
        $v = Get-UpdateVerification -ExpectedVersion '2.21' -ObservedVersion '2.19'
        $v.Applied | Should -BeFalse
        $v.Reason | Should -Be 'unchanged'
    }

    It "never reports applied when the observed version is <name>" -ForEach @(
        @{ name = 'null'; observed = $null }
        @{ name = 'empty'; observed = '' }
        @{ name = 'unparsable'; observed = 'not-a-version' }
    ) {
        $v = Get-UpdateVerification -ExpectedVersion '2.21' -ObservedVersion $observed
        $v.Applied | Should -BeFalse
        $v.Reason | Should -Be 'unreadable'
    }

    It "never reports applied when the expected version is unusable" {
        (Get-UpdateVerification -ExpectedVersion $null -ObservedVersion '2.21').Applied | Should -BeFalse
    }

    It "treats <observed> and <expected> as the same release" -ForEach @(
        @{ observed = '2.21'; expected = '2.21.0' }
        @{ observed = '2.21.0'; expected = '2.21' }
        @{ observed = '2.21.0.0'; expected = '2.21' }
    ) {
        # [Version] fills missing components with -1, not 0, so plain -lt calls "2.21"
        # OLDER than "2.21.0". The Gallery may report either form for the same release, and
        # without normalisation a good update would be announced as not applied
        $v = Get-UpdateVerification -ExpectedVersion $expected -ObservedVersion $observed
        $v.Applied | Should -BeTrue
        $v.Reason | Should -Be 'applied'
    }

    It "still reports unchanged across component-count differences when genuinely older" {
        (Get-UpdateVerification -ExpectedVersion '2.21.0' -ObservedVersion '2.20').Reason | Should -Be 'unchanged'
    }
}

Describe "Get-InstalledWinCleanLocation" -Tag "Unit", "Helper", "V221" {
    It "keeps querying the second provider when the first one throws" {
        # -ErrorAction SilentlyContinue only covers non-terminating errors. A broken
        # PowerShellGet used to abort the whole lookup, so PSResourceGet was never asked
        # and the answer became "no Gallery copy exists" - the wrong answer for a caller
        # that decides whether the running file can update itself
        Mock Get-InstalledScript { throw "provider is broken" }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Users\u\Documents\PowerShell\Scripts' } }

        Get-InstalledWinCleanLocation | Should -Contain 'C:\Users\u\Documents\PowerShell\Scripts'
    }

    It "throws when nothing was found AND a provider failed" {
        # "Could not read the machine" must not look like "no Gallery copy installed":
        # the latter classifies the running file as 'manual' and prints an installer
        # command, which would add a SECOND installation next to the unreadable one
        Mock Get-InstalledScript { throw "broken" }
        Mock Get-PSResource { throw "also broken" }

        { Get-InstalledWinCleanLocation } | Should -Throw
    }

    It "stays silent when no provider exists at all, which is not a failure" {
        # A machine with no package provider legitimately has no Gallery copy
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Get-InstalledScript', 'Get-PSResource' }

        @(Get-InstalledWinCleanLocation).Count | Should -Be 0
    }

    It "treats 'nothing installed' as an answer rather than a provider outage" {
        # PowerShellGet is hidden so only PSResourceGet answers, and PSResourceGet is left
        # UNMOCKED: it really raises its typed ResourceNotFoundException here. Without that
        # classification this throws, and every machine with no Gallery copy would then be
        # told its running copy is not Gallery-managed - and pointed at the installer
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-InstalledScript' }

        { Get-InstalledWinCleanLocation } | Should -Not -Throw
    }

    It "reports a non-terminating PowerShellGet failure, not just a thrown one" {
        # The other mocks use `throw`, which behaves the same under Stop and
        # SilentlyContinue - so they would pass even if the query went back to suppressing
        # errors. This is the shape that used to slip through as "no copy installed"
        Mock Get-InstalledScript { Write-Error "provider is unwell" }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-PSResource' }

        { Get-InstalledWinCleanLocation } | Should -Throw
    }

    It "ignores other installed scripts now that the name is filtered locally" {
        # The query no longer passes -Name, so the filter is ours to get right
        Mock Get-InstalledScript {
            @([pscustomobject]@{ Name = 'SomethingElse'; InstalledLocation = 'C:\Other' },
              [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Scripts' })
        }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-PSResource' }

        $result = @(Get-InstalledWinCleanLocation)
        $result | Should -Contain 'C:\Scripts'
        $result | Should -Not -Contain 'C:\Other'
    }

    It "reports failure even when the readable scope did return a copy" {
        # A partial list is not a smaller answer: a hidden AllUsers install turns
        # 'gallery-ambiguous' back into 'gallery' and re-enables the very automatic update
        # whose target cannot be resolved
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-InstalledScript' }
        Mock Get-PSResource { throw "AllUsers unreadable" } -ParameterFilter { $Scope -eq 'AllUsers' }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Users\u\Documents\PowerShell\Scripts' } }

        { Get-InstalledWinCleanLocation } | Should -Throw
    }

    It "reports failure when the AllUsers half specifically could not be read" {
        # A single "somebody answered" flag let a successful CurrentUser query mask this,
        # and AllUsers is the half the scope query exists to read
        Mock Get-InstalledScript { throw "broken" }
        Mock Get-PSResource { throw "AllUsers unreadable" } -ParameterFilter { $Scope -eq 'AllUsers' }
        Mock Get-PSResource { }

        { Get-InstalledWinCleanLocation } | Should -Throw
    }

    It "asks PSResourceGet for AllUsers as well as the default scope" {
        # Get-PSResource's -Scope is not nullable, so an unbound call means CurrentUser and
        # never sees an AllUsers install - the natural scope for an admin-only script
        Mock Get-InstalledScript { }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Program Files\WindowsPowerShell\Scripts' } } `
            -ParameterFilter { $Scope -eq 'AllUsers' }
        Mock Get-PSResource { }

        Get-InstalledWinCleanLocation | Should -Contain 'C:\Program Files\WindowsPowerShell\Scripts'
    }

    It "ignores a PSResourceGet module that shares the name" {
        Mock Get-InstalledScript { }
        Mock Get-PSResource {
            @([pscustomobject]@{ Type = 'Module'; InstalledLocation = 'C:\Modules\WinClean\1.0' },
              [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Scripts' })
        }

        $result = @(Get-InstalledWinCleanLocation)
        $result | Should -Contain 'C:\Scripts'
        $result | Should -Not -Contain 'C:\Modules\WinClean\1.0'
    }

    It "drops duplicates reported by both providers" {
        Mock Get-InstalledScript { [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Scripts' } }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Scripts' } }

        @(Get-InstalledWinCleanLocation).Count | Should -Be 1
    }

    It "drops duplicates that the two providers spell with different casing" {
        Mock Get-InstalledScript { [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Scripts' } }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'c:\scripts' } }

        @(Get-InstalledWinCleanLocation).Count | Should -Be 1
    }

    It "keeps querying the first provider's result when the second one throws" {
        # The mirror of the case above: isolation has to hold in both directions
        Mock Get-InstalledScript { [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Scripts' } }
        Mock Get-PSResource { throw "provider is broken" }

        Get-InstalledWinCleanLocation | Should -Contain 'C:\Scripts'
    }

    It "collapses locations that differ only by a trailing separator" {
        Mock Get-InstalledScript { [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Scripts' } }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Scripts\' } }

        @(Get-InstalledWinCleanLocation).Count | Should -Be 1
    }

    It "keeps two genuinely different locations" {
        Mock Get-InstalledScript { [pscustomobject]@{ Name = 'WinClean'; InstalledLocation = 'C:\Users\u\Documents\PowerShell\Scripts' } }
        Mock Get-PSResource { [pscustomobject]@{ Type = 'Script'; InstalledLocation = 'C:\Program Files\WindowsPowerShell\Scripts' } }

        @(Get-InstalledWinCleanLocation).Count | Should -Be 2
    }
}

Describe "Get-ScriptFileVersion" -Tag "Unit", "Helper", "V221" {
    It "reads the version out of the real WinClean.ps1" {
        # Ties verification to the product: if the PSScriptInfo layout ever changes, this
        # fails instead of silently returning $null forever, which would quietly turn
        # every future update into "could not be verified"
        Get-ScriptFileVersion -Path $script:WinCleanPath | Should -Be $script:Version
    }

    It "returns null for a file that does not exist" {
        Get-ScriptFileVersion -Path (Join-Path ([System.IO.Path]::GetTempPath()) "no-such-$(Get-Random).ps1") |
            Should -BeNullOrEmpty
    }

    It "returns null for a file without a .VERSION line" {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanVer_$(Get-Random).ps1"
        try {
            Set-Content -LiteralPath $tmp -Value @('# nothing here', 'Write-Host "hi"') -Encoding UTF8
            Get-ScriptFileVersion -Path $tmp | Should -BeNullOrEmpty
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }

    It "reads a version from a synthetic PSScriptInfo block" {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanVer_$(Get-Random).ps1"
        try {
            Set-Content -LiteralPath $tmp -Value @('<#PSScriptInfo', '.VERSION 9.9', '.GUID x', '#>') -Encoding UTF8
            Get-ScriptFileVersion -Path $tmp | Should -Be '9.9'
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }

    It "returns null for <name> instead of throwing" -ForEach @(
        @{ name = 'a null path'; path = $null }
        @{ name = 'an empty path'; path = '' }
    ) {
        Get-ScriptFileVersion -Path $path | Should -BeNullOrEmpty
    }
}

Describe "Get-UpdateInstruction" -Tag "Unit", "Helper", "V221" {
    It "tells the gallery copy to use Update-Script" {
        ((Get-UpdateInstruction -Channel 'gallery') -join "`n").Contains('Update-Script') | Should -BeTrue
    }

    It "names Update-PSResource instead on a machine without PowerShellGet" {
        # Advice that cannot be run is not advice
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Update-Script' }

        $text = (Get-UpdateInstruction -Channel 'gallery') -join "`n"
        $text.Contains('Update-PSResource') | Should -BeTrue
        $text.Contains('Update-Script') | Should -BeFalse
    }

    It "honours the answering provider even when both updaters are installed" {
        # The realistic broken-PowerShellGet machine: both commands exist, so presence
        # alone cannot choose. Ignoring Provider here would advise the command that just
        # failed, and no other test would notice
        $text = (Get-UpdateInstruction -Channel 'gallery' -Provider 'PSResourceGet') -join "`n"
        $text.Contains('Update-PSResource') | Should -BeTrue
        $text.Contains('Update-Script') | Should -BeFalse
    }

    It "names no updater at all when neither provider is installed" {
        # Naming a command that does not exist is the same mistake as naming the wrong one
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Update-Script', 'Update-PSResource' }

        $text = (Get-UpdateInstruction -Channel 'gallery') -join "`n"
        $text.Contains('Update-Script') | Should -BeFalse
        $text.Contains('Update-PSResource') | Should -BeFalse
        $text.Contains('releases/latest') | Should -BeTrue
    }

    It "REGRESSION: never advises Install-Script for <channel>, which would add a second copy" -ForEach @(
        @{ channel = 'installer' }
        @{ channel = 'oneliner' }
        @{ channel = 'manual' }
        @{ channel = 'unknown' }
        @{ channel = 'gallery-unverified' }
    ) {
        # The old code showed "Install-Script -Name WinClean" to every non-gallery copy.
        # Following it builds the two-install state that made the update silently target
        # the wrong file: the advice created the very configuration it could not handle.
        ((Get-UpdateInstruction -Channel $channel) -join "`n").Contains('Install-Script') | Should -BeFalse
    }

    It "points <channel> at <expected>" -ForEach @(
        @{ channel = 'installer'; expected = 'install.ps1' }
        @{ channel = 'oneliner'; expected = 'get.ps1' }
        @{ channel = 'manual'; expected = 'install.ps1' }
    ) {
        ((Get-UpdateInstruction -Channel $channel) -join "`n").Contains($expected) | Should -BeTrue
    }

    It "says the location is unknown only for the unknown channel" {
        ((Get-UpdateInstruction -Channel 'unknown') -join "`n").Contains('could not be determined') | Should -BeTrue
        ((Get-UpdateInstruction -Channel 'manual') -join "`n").Contains('could not be determined') | Should -BeFalse
    }

    It "returns usable advice for an unforeseen channel value" {
        $text = Get-UpdateInstruction -Channel 'something-new'
        $text | Should -Not -BeNullOrEmpty
        ($text -join "`n").Contains('install.ps1') | Should -BeTrue
    }

    It "REGRESSION: does not tell a Gallery copy it came from somewhere else" {
        # Shown when an update reported success but the running file did not change. This
        # branch used to print the 'manual' text, which denies the copy's own provenance
        # and points at install.ps1 - adding a second installation, the state that caused
        # the wrong-target defect to begin with
        $text = (Get-UpdateInstruction -Channel 'gallery-unverified') -join "`n"
        # Positive invariants, not the absence of one phrasing: an assertion that hunts a
        # string the product no longer contains can never fail, and looks like protection
        $text.Contains('does not match') | Should -BeFalse    # provenance is not denied
        $text.Contains('install.ps1') | Should -BeFalse       # no second installation
        $text.Contains('Get-InstalledScript') | Should -BeTrue
        $text.Contains('Get-PSResource') | Should -BeTrue
    }
}

Describe "Find-GalleryWinClean" -Tag "Unit", "Helper", "V221" {
    It "asks PSResourceGet when PowerShellGet's Find-Script is not installed" {
        # REGRESSION: discovery called Find-Script unconditionally. On a PSResourceGet-only
        # machine it does not exist, discovery threw, the caller's catch turned that into
        # "no update available", and the updater fallback below it could never be reached -
        # the whole update path was dead while every surrounding test stayed green
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Find-Script' }
        Mock Find-PSResource { [pscustomobject]@{ Type = 'Script'; Version = '9.9'; ReleaseNotes = 'notes' } }

        $found = Find-GalleryWinClean
        $found.Version | Should -Be '9.9'
        $found.ReleaseNotes | Should -Be 'notes'
    }

    It "ignores a module of the same name when asking PSResourceGet" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Find-Script' }
        Mock Find-PSResource {
            @([pscustomobject]@{ Type = 'Module'; Version = '99.0' },
              [pscustomobject]@{ Type = 'Script'; Version = '9.9' })
        }

        (Find-GalleryWinClean).Version | Should -Be '9.9'
    }

    It "returns null when neither provider can be asked" {
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Find-Script', 'Find-PSResource' }

        Find-GalleryWinClean | Should -BeNullOrEmpty
    }

    It "returns null when the Gallery knows nothing about WinClean" {
        # Both must be silenced: an empty answer from one provider is not an answer for
        # the other, so discovery goes on to ask it
        Mock Find-Script { }
        Mock Find-PSResource { }

        Find-GalleryWinClean | Should -BeNullOrEmpty
    }

    It "asks PSResourceGet when Find-Script answers with nothing" {
        # Pinned with -Invoke: an empty answer from one provider is not authoritative for
        # the other, and a test where both are empty would pass either way
        Mock Find-Script { }
        Mock Find-PSResource { [pscustomobject]@{ Type = 'Script'; Version = '9.9'; ReleaseNotes = 'n' } }

        (Find-GalleryWinClean).Version | Should -Be '9.9'
        Should -Invoke Find-PSResource -Times 1
    }

    It "reports which provider answered" {
        Mock Find-Script { throw "broken" }
        Mock Find-PSResource { [pscustomobject]@{ Type = 'Script'; Version = '9.9'; ReleaseNotes = 'n' } }

        (Find-GalleryWinClean).Provider | Should -Be 'PSResourceGet'
    }

    It "tries PSResourceGet when Find-Script exists but fails" {
        # Falling back only on ABSENCE let a present-but-broken PowerShellGet (an
        # unregistered PSGallery, say) mask a PSResourceGet that would have answered.
        # Each provider keeps its own repository registration
        Mock Find-Script { throw "PSGallery is not registered for PowerShellGet" }
        Mock Find-PSResource { [pscustomobject]@{ Type = 'Script'; Version = '9.9'; ReleaseNotes = 'n' } }

        (Find-GalleryWinClean).Version | Should -Be '9.9'
    }

    It "REGRESSION: throws when both providers failed, instead of resembling 'up to date'" {
        # The per-provider catches introduced for fallback swallowed the last error too, so
        # an unregistered PSGallery, a TLS or proxy failure and an unpublished script all
        # returned $null - which the caller reads as "asked, nothing newer" and prints
        # nothing at all. Before those catches, the exception reached the caller and was
        # logged. Failing to ask is not an answer
        Mock Find-Script { throw "broken" }
        Mock Find-PSResource { throw "also broken" }

        { Find-GalleryWinClean } | Should -Throw
    }

    It "returns null when PSResourceGet only knows a module of that name" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Find-Script' }
        Mock Find-PSResource { [pscustomobject]@{ Type = 'Module'; Version = '99.0' } }

        Find-GalleryWinClean | Should -BeNullOrEmpty
    }
}

Describe "Select-UpdateCommand" -Tag "Unit", "Helper", "V221" {
    It "prefers PowerShellGet when discovery answered through it" {
        Select-UpdateCommand -Provider 'PowerShellGet' | Should -Be 'Update-Script'
    }

    It "prefers PSResourceGet when discovery answered through it, even with both installed" {
        # The point of carrying the provider: on a machine where PowerShellGet exists but
        # is broken, discovery succeeds through PSResourceGet and the updater must not go
        # straight back to the provider that just failed
        Select-UpdateCommand -Provider 'PSResourceGet' | Should -Be 'Update-PSResource'
    }

    It "falls back to the other provider when the preferred one has no updater" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Update-PSResource' }

        Select-UpdateCommand -Provider 'PSResourceGet' | Should -Be 'Update-Script'
    }

    It "defaults to PowerShellGet when the provider is <name>" -ForEach @(
        @{ name = 'unknown'; provider = $null }
        @{ name = 'empty'; provider = '' }
        @{ name = 'unrecognised'; provider = 'SomethingElse' }
    ) {
        Select-UpdateCommand -Provider $provider | Should -Be 'Update-Script'
    }

    It "returns null when neither updater exists" {
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Update-Script', 'Update-PSResource' }

        Select-UpdateCommand -Provider 'PowerShellGet' | Should -BeNullOrEmpty
    }
}

Describe "Test-ScriptUpdate" -Tag "Unit", "Helper", "V221" {
    It "reports an update with the channel of the running copy" {
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { @{ Version = '99.9'; ReleaseNotes = 'notes' } }

        $info = Test-ScriptUpdate
        $info | Should -Not -BeNullOrEmpty
        $info.LatestVersion | Should -Be '99.9'
        $info.CurrentVersion | Should -Be ([Version]$script:Version).ToString()
        # dot-sourced from the repository, so the running file is not a Gallery install
        $info.Channel | Should -BeIn @('manual', 'installer', 'oneliner', 'gallery', 'gallery-ambiguous')
    }

    It "classifies the channel from the installations actually found" {
        # A positive control (raised in review): the -BeIn assertion above accepts five of
        # six values, so replacing the real lookup with an empty list survived it. That
        # mutation kills self-update outright and sends every user the installer advice,
        # which is the exact "second installation" outcome this release removes
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { @{ Version = '99.9'; ReleaseNotes = 'n'; Provider = 'PowerShellGet' } }
        Mock Get-InstalledWinCleanLocation { @((Split-Path -Parent $script:WinCleanPath)) }

        (Test-ScriptUpdate).Channel | Should -Be 'gallery'
    }

    It "carries the answering provider through to the caller" {
        # Without this, dropping Provider here would silently send every machine back to
        # PowerShellGet-first selection - including the ones where it is broken
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { @{ Version = '99.9'; ReleaseNotes = 'n'; Provider = 'PSResourceGet' } }

        (Test-ScriptUpdate).Provider | Should -Be 'PSResourceGet'
    }

    It "reports nothing when the Gallery is not newer" {
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { @{ Version = '0.1'; ReleaseNotes = '' } }

        Test-ScriptUpdate | Should -BeNullOrEmpty
    }

    It "reports nothing when no provider can answer" {
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { $null }

        Test-ScriptUpdate | Should -BeNullOrEmpty
    }

    It "turns a <name> failure into a counted warning rather than silence" -ForEach @(
        @{ name = 'discovery'; target = 'Find-GalleryWinClean' }
        @{ name = 'installed-copy lookup'; target = 'Get-InstalledWinCleanLocation' }
    ) {
        # Both helpers now throw when they could not ask at all. That is only useful if the
        # caller converts it into something a human or a log reader can see
        Mock Test-PSGalleryConnection { $true }
        Mock Find-GalleryWinClean { @{ Version = '99.9'; ReleaseNotes = 'n'; Provider = 'PowerShellGet' } }
        Mock $target { throw "provider unavailable" }
        $script:Stats.WarningsCount = 0

        Test-ScriptUpdate | Should -BeNullOrEmpty
        [int]$script:Stats.WarningsCount | Should -Be 1
    }
}

Describe "Invoke-ScriptUpdate branches" -Tag "Unit", "Helper", "V221" {
    # These branches were unreachable by the helper tests, which only proved that the
    # instruction TEXT exists - not that Invoke-ScriptUpdate ever prints it (raised in
    # review). Every branch here returns rather than completing an update.
    # v2.22: the function no longer calls exit at all, so the successful path is testable
    # too - it is covered in the V222 region below, which is why this note no longer says
    # the suite is only safe because that path is never reached.

    BeforeEach {
        $script:Stats.WarningsCount = 0
        $script:Stats.ErrorsCount = 0
        $script:Stats.Aborted = $null
        $script:printed = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { if ($Object) { $script:printed.Add([string]$Object) } }
        # Without this the interactive branches block on a real console waiting for a
        # keypress, which hung the whole suite until the process was killed
        Mock Wait-ForKeyPress { }
        # Pester 5 runs a Describe body during discovery only, so a variable declared there
        # is gone by the time the tests run - it must be built per test
        $script:info = @{ CurrentVersion = '2.20'; LatestVersion = '2.21'; Channel = 'installer' }
    }

    It "prints the applicable instruction in ReportOnly mode instead of staying silent" {
        $ReportOnly = $true
        Invoke-ScriptUpdate -UpdateInfo $script:info

        ($script:printed -join "`n").Contains('install.ps1') | Should -BeTrue
    }

    It "forwards the provider into the <mode> instruction" -ForEach @(
        @{ mode = 'ReportOnly'; reportOnly = $true; interactive = $true }
        @{ mode = 'non-interactive'; reportOnly = $false; interactive = $false }
    ) {
        # These two call sites pass -Provider; dropping it from either would advise
        # Update-Script on a machine that just proved PowerShellGet does not work, and
        # the direct Get-UpdateInstruction test would not notice
        $ReportOnly = $reportOnly
        Mock Test-InteractiveConsole { $interactive }
        # Not optional (raised in review): this case is Channel='gallery' and interactive,
        # so if the ReportOnly early return is ever lost, an unmocked run would call the
        # real Update-Script on whatever machine executes the suite
        Mock Read-Host { 'n' }
        Mock Update-Script { }
        Mock Update-PSResource { }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery'; Provider = 'PSResourceGet' }

        Should -Invoke Update-Script -Times 0
        Should -Invoke Update-PSResource -Times 0
        $text = $script:printed -join "`n"
        $text.Contains('Update-PSResource') | Should -BeTrue
        $text.Contains('Update-Script') | Should -BeFalse
    }

    It "prints the running path in the <channel> instruction" -ForEach @(
        @{ channel = 'gallery-ambiguous'; interactive = $true }
        @{ channel = 'installer'; interactive = $false }
    ) {
        # -ExecutingPath was pinned at one call site only, so dropping it from the other
        # three survived every test - including the ambiguous branch, where the printed
        # path is the only way a reader can tell the installations apart
        Mock Test-InteractiveConsole { $interactive }
        Mock Read-Host { 'n' }
        Mock Update-Script { }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = $channel; Provider = 'PowerShellGet' }

        if ($channel -eq 'gallery-ambiguous') {
            ($script:printed -join "`n").Contains($script:WinCleanPath) | Should -BeTrue
        } else {
            # 'installer' does not print the path, and the docs must not claim it does
            ($script:printed -join "`n").Contains('install.ps1') | Should -BeTrue
        }
    }

    It "verifies the update against the file that is running" {
        # Dropping -Path $PSCommandPath survived every test, because they all mock
        # Get-ScriptFileVersion and none checks what it was asked about. The effect would be
        # a false "could not be read back" on every genuinely successful update
        # Captured directly rather than via -ParameterFilter: the filter form passed even
        # with the path mutated to a nonsense value, so it was proving nothing
        $script:askedPath = 'never set'
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { $script:askedPath = $Path; '2.20' }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery'; Provider = 'PowerShellGet' }

        $script:askedPath | Should -Be $script:WinCleanPath
    }

    It "pauses before handing the run back, so the user reads the outcome" {
        # v2.22 rewrote this test. It used to assert that the function wrote the result
        # JSON itself, which was only ever true because its own `exit` bypassed the
        # finally that should have done it. That workaround is gone: the artefact is now
        # the caller's job (covered in the V222 region), and what is worth pinning here is
        # the interactive behaviour that survived - the pause. Without it the window of a
        # double-clicked shortcut closes on "Update complete" before it can be read.
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { '2.21' }

        $null = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = 'gallery'; Provider = 'PowerShellGet' }

        Should -Invoke Wait-ForKeyPress -Times 1
        $script:Stats.Aborted | Should -Be 'UpdatedAndExited'
        ($script:printed -join "`n").Contains('Update complete') | Should -BeTrue
    }

    It "never calls an updater for a copy that is not Gallery-managed" {
        Mock Test-InteractiveConsole { $false }
        Mock Update-Script { }
        Mock Update-PSResource { }

        Invoke-ScriptUpdate -UpdateInfo $script:info

        Should -Invoke Update-Script -Times 0
        Should -Invoke Update-PSResource -Times 0
        ($script:printed -join "`n").Contains('install.ps1') | Should -BeTrue
    }

    It "declines to update when several Gallery installations exist, in an interactive session" {
        # Interactive on purpose: with a non-interactive console the function returns
        # earlier, so a regression treating 'gallery-ambiguous' as updatable would only
        # show up here. Read-Host would say yes if it were ever asked
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Update-PSResource { }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery-ambiguous' }

        Should -Invoke Update-Script -Times 0
        Should -Invoke Update-PSResource -Times 0
        $text = $script:printed -join "`n"
        $text.Contains('cannot tell which one an automatic update would change') | Should -BeTrue
        # this copy IS Gallery-managed; saying otherwise contradicts the reason it is here
        $text.Contains('does not match a Gallery installation') | Should -BeFalse
        # and the advice must end somewhere the reader can actually act
        $text.Contains('releases/latest') | Should -BeTrue
    }

    It "prints the path of the running copy so the installations can be told apart" {
        # Every production call passes -ExecutingPath; without this assertion, dropping it
        # from all four call sites would leave the suite green
        Mock Test-InteractiveConsole { $false }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery-ambiguous' }

        ($script:printed -join "`n").Contains($script:WinCleanPath) | Should -BeTrue
    }

    It "counts a failed update as a warning, so the run does not exit non-zero for it" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { throw "gallery unreachable" }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 1
    }

    It "REGRESSION: an update that changed nothing is reported, not announced as complete" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }                       # reports success, changes nothing
        Mock Get-ScriptFileVersion { '2.20' }        # the running file stayed old

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        [int]$script:Stats.WarningsCount | Should -Be 1
        $text = $script:printed -join "`n"
        $text.Contains('Update complete') | Should -BeFalse
        $text.Contains('still reports v2.20') | Should -BeTrue
        # and it must not deny this copy's provenance or advise a second installation
        $text.Contains('does not match a PowerShell Gallery installation') | Should -BeFalse
        $text.Contains('install.ps1') | Should -BeFalse
    }

    It "names the version actually read back, not the one the process started with" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { '2.13' }        # a third copy, older than either

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        ($script:printed -join "`n").Contains('still reports v2.13') | Should -BeTrue
    }

    It "does not update when the user declines" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'n' }
        Mock Update-Script { }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        Should -Invoke Update-Script -Times 0
    }

    It "treats an empty answer as yes, as the Y/n prompt promises" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { '' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { '2.20' }   # keeps the test out of the exit 0 path

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        Should -Invoke Update-Script -Times 1
    }

    It "uses Update-PSResource when Update-Script is unavailable" {
        # Named for what it proves: the updater layer alone. Reaching this on a real
        # PSResourceGet-only machine also needs discovery to work there, which is pinned
        # separately by the Find-GalleryWinClean tests
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Update-Script' }
        Mock Update-PSResource { }
        Mock Get-ScriptFileVersion { '2.20' }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        Should -Invoke Update-PSResource -Times 1
    }

    It "updates through the provider that answered discovery, not the one that failed" {
        # End to end for the broken-PowerShellGet machine: discovery fell back to
        # PSResourceGet, so the update must use it too even though Update-Script exists
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Update-PSResource { }
        Mock Get-ScriptFileVersion { '2.20' }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery'; Provider = 'PSResourceGet' }

        Should -Invoke Update-PSResource -Times 1
        Should -Invoke Update-Script -Times 0
    }

    It "reports a counted warning when no update provider exists at all" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Update-Script', 'Update-PSResource' }

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 1
    }

    It "says the version could not be read back rather than claiming success" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { $null }     # the file cannot be read after the update

        Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                           Channel = 'gallery' }

        [int]$script:Stats.WarningsCount | Should -Be 1
        $text = $script:printed -join "`n"
        $text.Contains('could not be read back') | Should -BeTrue
        $text.Contains('Update complete') | Should -BeFalse
    }
}

#region v2.22 Disk Cleanup idle detection

Describe "Update-IdleStreak" -Tag "Unit", "Helper", "V222" {
    # The rule that decides when a resident cleanmgr is declared finished. Pure, so the
    # decision can be exercised without a process - the measured case (finished in ~10s,
    # then frozen for the remaining ~890) is otherwise only reproducible on a live machine.

    It "counts consecutive identical fingerprints" {
        $s = 0
        $s = Update-IdleStreak -Previous 'a' -Current 'a' -Streak $s
        $s | Should -Be 1
        $s = Update-IdleStreak -Previous 'a' -Current 'a' -Streak $s
        $s | Should -Be 2
    }

    It "resets the moment the process does anything" {
        # One counter moving is enough: a process mid-delete is not idle.
        Update-IdleStreak -Previous 'cpu|1|2|3|4' -Current 'cpu|1|2|3|5' -Streak 11 | Should -Be 0
    }

    It "treats an unreadable fingerprint as 'cannot tell', never as idle - <Case>" -ForEach @(
        @{ Case = 'previous unreadable'; Prev = $null; Curr = 'a' }
        @{ Case = 'current unreadable';  Prev = 'a';   Curr = $null }
        @{ Case = 'both unreadable';     Prev = $null; Curr = $null }
        @{ Case = 'previous empty';      Prev = '';    Curr = 'a' }
        @{ Case = 'current empty';       Prev = 'a';   Curr = '' }
    ) {
        # The safety property. Get-ProcessActivityFingerprint returns $null when WMI cannot
        # answer, and if that accumulated towards the threshold a machine with broken WMI
        # would cut every Disk Cleanup short after two minutes and call it complete.
        Update-IdleStreak -Previous $Prev -Current $Curr -Streak 11 |
            Should -Be 0 -Because 'not being able to measure work is not evidence that work finished'
    }

    It "compares case-sensitively, so counters differing only in case still count as work" {
        # Fingerprints are numeric today, but -eq in PowerShell is case-INSENSITIVE by
        # default and this comparison decides whether to stop waiting. Pinned deliberately.
        Update-IdleStreak -Previous 'A|1' -Current 'a|1' -Streak 5 | Should -Be 0
    }
}

Describe "Get-ProcessActivityFingerprint" -Tag "Unit", "Helper", "V222" {

    It "returns a comparable fingerprint for a live process" {
        $fp = Get-ProcessActivityFingerprint -ProcessId $PID
        $fp | Should -Not -BeNullOrEmpty
        # CPU kernel + CPU user + three I/O counters
        ($fp -split '\|').Count | Should -Be 5
    }

    It "changes after the process does measurable work" {
        # Proves the fingerprint actually tracks activity. If it were built from cached or
        # constant values, everything would look idle and every cleanmgr would be cut short
        # at two minutes - the failure mode that matters most here.
        $before = Get-ProcessActivityFingerprint -ProcessId $PID
        $sink = 0
        1..200000 | ForEach-Object { $sink += $_ }
        $null = Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue | Select-Object -First 50
        $after = Get-ProcessActivityFingerprint -ProcessId $PID

        $after | Should -Not -Be $before
    }

    It "returns null for a process id that does not exist, rather than throwing" {
        # cleanmgr can exit between two checks; the caller must get "cannot tell", and
        # Update-IdleStreak turns that into a reset rather than a false completion.
        Get-ProcessActivityFingerprint -ProcessId 999999 | Should -BeNullOrEmpty
    }

    It "returns null - never a constant - when the counters cannot be read at all" {
        # Added after a mutation survived. The test above exercises the "no such process"
        # branch, where Get-CimInstance returns nothing; it never reached the catch, which
        # is where a broken WMI lands. Returning any FIXED value there would be the worst
        # possible answer: two consecutive unreadable checks would compare equal, the idle
        # streak would build on pure ignorance, and a machine with broken WMI would cut
        # every Disk Cleanup short and call it finished.
        Mock Get-CimInstance { throw 'WMI is unavailable' }

        $first  = Get-ProcessActivityFingerprint -ProcessId $PID
        $second = Get-ProcessActivityFingerprint -ProcessId $PID

        $first | Should -BeNullOrEmpty
        Update-IdleStreak -Previous $first -Current $second -Streak 11 |
            Should -Be 0 -Because 'two unreadable samples must not look like two identical ones'
    }
}

Describe "Wait-CleanmgrCompletion" -Tag "Unit", "Helper", "V222" {
    # The whole wait, exercised without a process and without waiting fifteen minutes -
    # the caller injects exit state, activity and the sleep. This is the part that could
    # previously only be observed on a live machine, which is why the defect it fixes
    # survived into a release: on the stand cleanmgr exits normally.

    BeforeEach {
        $script:progressAt = [System.Collections.Generic.List[int]]::new()
        $script:noWait = { param($seconds) }
        $script:onProgress = { param($seconds) $script:progressAt.Add($seconds) }
    }

    It "returns 'exited' as soon as the process leaves" {
        $script:calls = 0
        $r = Wait-CleanmgrCompletion `
                -HasExited { $script:calls++; $script:calls -gt 3 } `
                -GetFingerprint { "moving-$($script:calls)" } `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'exited'
        $r.Elapsed | Should -BeLessThan 900
    }

    It "declares 'idle-resident' once the process has been completely still for the threshold" {
        # The measured case: never exits, never does anything again.
        $r = Wait-CleanmgrCompletion `
                -HasExited { $false } `
                -GetFingerprint { 'frozen' } `
                -CheckInterval 10 -IdleChecksRequired 12 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'idle-resident'
        $r.Elapsed | Should -Be 120 -Because '12 checks of 10 seconds, and not one second longer'
    }

    It "waits the full timeout when the process keeps working" {
        # Every check shows movement, so the idle streak never builds - this must still
        # behave exactly as it did before v2.22.
        $script:n = 0
        $r = Wait-CleanmgrCompletion `
                -HasExited { $false } `
                -GetFingerprint { $script:n++; "busy-$($script:n)" } `
                -MaxWaitSeconds 900 -CheckInterval 10 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'timeout'
        $r.Elapsed | Should -Be 900
    }

    It "does not call a busy process idle just because it pauses briefly" {
        # Stillness must be CONSECUTIVE. A process that goes quiet for a while and then
        # resumes is working, and cutting it short would truncate a real cleanup.
        $script:n = 0
        $r = Wait-CleanmgrCompletion `
                -HasExited { $false } `
                -GetFingerprint {
                    $script:n++
                    # quiet for 8 checks, then a burst of work, repeatedly
                    if ($script:n % 10 -lt 8) { 'quiet-block-' + [math]::Floor($script:n / 10) } else { "work-$($script:n)" }
                } `
                -MaxWaitSeconds 900 -CheckInterval 10 -IdleChecksRequired 12 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'timeout' -Because 'the streak never reached 12 consecutive still checks'
    }

    It "never declares idle when activity cannot be measured at all" {
        # Broken WMI must not look like a finished cleanup. Without this, such a machine
        # would silently cut every Disk Cleanup off after two minutes.
        $r = Wait-CleanmgrCompletion `
                -HasExited { $false } `
                -GetFingerprint { $null } `
                -MaxWaitSeconds 900 -CheckInterval 10 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'timeout'
        $r.Elapsed | Should -Be 900
    }

    It "reports progress once a minute, not on every check" {
        $r = Wait-CleanmgrCompletion `
                -HasExited { $false } `
                -GetFingerprint { $script:n++; "busy-$($script:n)" } `
                -MaxWaitSeconds 300 -CheckInterval 10 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'timeout'
        $script:progressAt | Should -Be @(60, 120, 180, 240, 300)
    }

    It "prefers 'exited' over 'timeout' when the process leaves during the final interval" {
        # Same instant, two possible labels; the accurate one is that it exited.
        $script:n = 0
        $r = Wait-CleanmgrCompletion `
                -HasExited { $script:n -ge 30 } `
                -GetFingerprint { $script:n++; "busy-$($script:n)" } `
                -MaxWaitSeconds 300 -CheckInterval 10 `
                -Wait $script:noWait -OnProgress $script:onProgress

        $r.Outcome | Should -Be 'exited'
    }
}

#endregion

#region v2.22 single end-of-run path

Describe "Invoke-ScriptUpdate stop/continue contract" -Tag "Unit", "Helper", "V222" {
    # v2.22: the function used to end the process itself, so its most important branch -
    # the successful update - could not be tested at all without killing the suite. It now
    # answers a question ("is the run over?") and the caller ends the run. That answer is
    # the whole contract: get it wrong in the false direction and a run continues doing
    # maintenance with a replaced script file underneath it; wrong in the true direction
    # and an ordinary run stops before doing any work.

    BeforeEach {
        $script:Stats.WarningsCount = 0
        $script:Stats.ErrorsCount = 0
        $script:Stats.Aborted = $null
        $script:printed = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { if ($Object) { $script:printed.Add([string]$Object) } }
        Mock Wait-ForKeyPress { }
    }

    It "returns true after an update it verified, so the caller ends the run" {
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Select-UpdateCommand { 'Update-Script' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { '2.21' }

        $stop = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = 'gallery'; Provider = 'PowerShellGet' }

        $stop | Should -BeOfType [bool] -Because 'a leaked pipeline object here would make the caller decide on an array'
        $stop | Should -BeTrue
        $script:Stats.Aborted | Should -Be 'UpdatedAndExited'
        ($script:printed -join "`n").Contains('Update complete') | Should -BeTrue
    }

    It "stays a plain boolean even when the update provider writes to the pipeline" {
        # Added after a mutation survived: dropping the `$null =` in front of the provider
        # switch changed nothing, because every mock returns nothing. A real provider that
        # emitted an object would make this function return an array, and the caller's
        # `if (...)` would then be judging the array rather than the answer. Update-Script
        # and Update-PSResource are documented as returning nothing, but "documented as"
        # is not "guaranteed to", and the cost of the guard is one assignment.
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Select-UpdateCommand { 'Update-Script' }
        Mock Update-Script { [pscustomobject]@{ Name = 'WinClean'; Version = '2.21' } }
        Mock Get-ScriptFileVersion { '2.21' }

        $stop = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = 'gallery'; Provider = 'PowerShellGet' }

        @($stop).Count | Should -Be 1 -Because 'provider output must not be part of the answer'
        $stop | Should -BeOfType [bool]
        $stop | Should -BeTrue
    }

    It "does not write the result JSON itself - that belongs to the shared end-of-run path" {
        # The v2.21 shape: this function hand-copied the JSON write because its own exit
        # bypassed the finally. Copying it back would recreate two owners of one artefact.
        Mock Test-InteractiveConsole { $true }
        Mock Read-Host { 'y' }
        Mock Select-UpdateCommand { 'Update-Script' }
        Mock Update-Script { }
        Mock Get-ScriptFileVersion { '2.21' }
        Mock Write-ResultJson { }

        $null = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = 'gallery'; Provider = 'PowerShellGet' }

        Should -Invoke Write-ResultJson -Times 0
    }

    It "returns false so the run continues - <Case>" -ForEach @(
        @{ Case = 'report-only';        Setup = { $script:ReportOnly = $true } }
        @{ Case = 'non-interactive';    Setup = { Mock Test-InteractiveConsole { $false } } }
        @{ Case = 'user declines';      Setup = { Mock Test-InteractiveConsole { $true }; Mock Read-Host { 'n' } } }
        @{ Case = 'update command failed'; Setup = {
                Mock Test-InteractiveConsole { $true }; Mock Read-Host { 'y' }
                Mock Select-UpdateCommand { 'Update-Script' }
                Mock Update-Script { throw 'gallery exploded' } } }
        @{ Case = 'version did not change'; Setup = {
                Mock Test-InteractiveConsole { $true }; Mock Read-Host { 'y' }
                Mock Select-UpdateCommand { 'Update-Script' }
                Mock Update-Script { }
                Mock Get-ScriptFileVersion { '2.20' } } }
    ) {
        $ReportOnly = $false
        & $Setup

        $stop = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = 'gallery'; Provider = 'PowerShellGet' }

        $stop | Should -BeFalse -Because 'the maintenance the user asked for must still run'
        $script:Stats.Aborted | Should -BeNullOrEmpty
    }

    It "returns false for a copy it cannot aim an update at - <Channel>" -ForEach @(
        @{ Channel = 'installer' }
        @{ Channel = 'oneliner' }
        @{ Channel = 'manual' }
        @{ Channel = 'unknown' }
        @{ Channel = 'gallery-ambiguous' }
    ) {
        $ReportOnly = $false
        Mock Test-InteractiveConsole { $true }

        $stop = Invoke-ScriptUpdate -UpdateInfo @{ CurrentVersion = '2.20'; LatestVersion = '2.21'
                                                   Channel = $Channel; Provider = 'PowerShellGet' }

        $stop | Should -BeFalse
    }
}

Describe "Complete-WinCleanRun" -Tag "Unit", "Helper", "V222" {
    # One end-of-run path for the normal finally and for both abort branches. Before this
    # the list of things a run must do on the way out existed in three places, and v2.21
    # shipped two separate fixes to the copies rather than one fix to the list.

    BeforeEach {
        $script:Stats.Aborted = $null
        $script:RunCompleted = $false
        Mock Write-ResultJson { }
        Mock Show-FinalStatistics { }
    }

    It "writes the result JSON and shows the summary for an ordinary run" {
        Complete-WinCleanRun -ResultPath 'C:\some\result.json'

        # -Exactly throughout this block, established by experiment: Pester treats
        # `-Times 0` as "never" but `-Times N` (N>0) as "AT LEAST N", so the plain form
        # cannot see a duplicate. That is exactly what the latch below has to prevent, and
        # a mutation run proved the non-exact assertion could not catch its removal.
        Should -Invoke Write-ResultJson -Exactly -Times 1
        Should -Invoke Show-FinalStatistics -Exactly -Times 1
    }

    It "still writes the JSON for an aborted run but shows no summary - <Aborted>" -ForEach @(
        @{ Aborted = 'UpdatedAndExited' }
        @{ Aborted = 'PendingRebootDeclined' }
    ) {
        # Automation must always get the artefact; a human must not be told
        # "COMPLETED SUCCESSFULLY" about a run that deliberately did nothing.
        $script:Stats.Aborted = $Aborted

        Complete-WinCleanRun -ResultPath 'C:\some\result.json'

        Should -Invoke Write-ResultJson -Exactly -Times 1
        Should -Invoke Show-FinalStatistics -Exactly -Times 0
    }

    It "is latched - an abort path that also unwinds through the finally writes once" {
        # Both abort paths call this explicitly and then return; the finally calls it again
        # for every other run. Without the latch the JSON would be written twice and the
        # summary shown twice for the ordinary case.
        Complete-WinCleanRun -ResultPath 'C:\some\result.json'
        Complete-WinCleanRun -ResultPath 'C:\some\result.json'
        Complete-WinCleanRun -ResultPath 'C:\some\result.json'

        Should -Invoke Write-ResultJson -Exactly -Times 1
        Should -Invoke Show-FinalStatistics -Exactly -Times 1
    }

    It "releases the log handle so the log can be moved right after the run" {
        $logFile = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanComplete_$(Get-Random).log"
        $prevPath = $script:LogPath
        $script:LogPath = $logFile
        try {
            Write-LogFileLine -Line 'held open' -StartNewFile
            $script:LogWriter | Should -Not -BeNullOrEmpty -Because 'the test needs a real open handle to prove it gets released'

            Complete-WinCleanRun -ResultPath 'C:\some\result.json'

            $script:LogWriter | Should -BeNullOrEmpty
            # The operational point of releasing it, asserted as behaviour rather than as
            # a null check: a still-open handle would make this fail on Windows.
            { Remove-Item -LiteralPath $logFile -Force -ErrorAction Stop } | Should -Not -Throw
        } finally {
            if ($script:LogWriter) { $script:LogWriter.Dispose(); $script:LogWriter = $null; $script:LogWriterPath = $null }
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
            $script:LogPath = $prevPath
        }
    }
}

#endregion

Describe "Update-Applications when winget is absent" -Tag "Unit", "Helper", "V221" {

    BeforeEach {
        $script:Stats.ErrorsCount = 0
        $script:Stats.WarningsCount = 0
    }

    It "counts a machine without winget as a warning, so the run can still exit 0" {
        # The exit code is computed from ErrorsCount alone. Counting a missing optional
        # tool as an error made every run on such a machine exit 1 with all nine phases
        # completed, which any scheduler or CI job reads as a failed run.
        # ReportOnly as a safety net (raised in review): this is the only test that calls a
        # top-level phase function rather than a pure helper, and its safety otherwise rests
        # entirely on two -ParameterFilter mocks continuing to match. If either stops
        # matching after a refactor, the unguarded version would run `winget upgrade --all`
        # for real on whatever machine runs the suite - including the workstation where the
        # release gate runs Pester. The winget-not-found branch is reached identically.
        $ReportOnly = $true
        Mock Test-InternetConnection { $true }
        Mock Update-Progress { }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock Test-Path { $false } -ParameterFilter { "$Path".Contains('winget.exe') }

        Update-Applications

        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 1
        # The count alone is ambiguous now that this no longer fails the run: 0 offered
        # means "nothing to upgrade" only when the check actually happened
        $script:Stats.AppUpdatesStatus | Should -Be 'skipped-no-winget'
    }

    It "records the parameter skip distinctly from a missing winget" {
        $SkipUpdates = $true
        Mock Update-Progress { }

        Update-Applications

        $script:Stats.AppUpdatesStatus | Should -Be 'skipped-parameter'
    }

    It "sets the parameter skip where production can reach it, not only inside the function" {
        # Structural, because the behavioural test above enters Update-Applications
        # directly while production never does when -SkipUpdates is passed: Invoke-Phase
        # -Skip stops the dispatch, so the in-function branch is unreachable there and the
        # status would stay 'not-run'. This pins the assignment that Start-WinClean makes
        # before the phase, which no behavioural test in this suite can reach.
        $source = Get-Content $script:WinCleanPath -Raw
        $dispatch = $source.IndexOf("Invoke-Phase -Name 'Updates'")
        $dispatch | Should -BeGreaterThan 0
        $preamble = $source.Substring([math]::Max(0, $dispatch - 400), [math]::Min(400, $dispatch))
        $preamble.Contains("AppUpdatesStatus = 'skipped-parameter'") | Should -BeTrue
    }

    It "keeps a present-but-failing winget an ERROR, and does not call that check 'checked'" {
        # Two things the docs promise and nothing pinned: the upgrade check exiting non-zero
        # stays an error (unlike a MISSING winget), and the status must not read 'checked'
        # for a check that produced no list - which is the ambiguity the field exists to end.
        # ReportOnly keeps the source-update branch out of it; every external call is mocked.
        $ReportOnly = $true
        Mock Update-Progress { }
        Mock Test-InternetConnection { $true }
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\fake\winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
        Mock Start-Process {
            $proc = [pscustomobject]@{ ExitCode = 1 }
            $proc | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
            $proc | Add-Member -MemberType ScriptMethod -Name Kill -Value { param($tree) }
            $proc
        }
        Mock Get-Content { '' }
        Mock Remove-Item { }

        Update-Applications

        [int]$script:Stats.ErrorsCount | Should -Be 1
        $script:Stats.AppUpdatesStatus | Should -Be 'check-failed'
    }

    It "counts an offline machine as a warning too, so the run can still exit 0" {
        # v2.21 extends the missing-winget reasoning to connectivity: an offline laptop
        # used to end every run with code 1 no matter how completely the cleanup worked.
        # The state stays visible through the status field rather than the exit code
        Mock Update-Progress { }
        Mock Test-InternetConnection { $false }

        Update-Applications

        $script:Stats.AppUpdatesStatus | Should -Be 'skipped-offline'
        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 1
    }

    It "counts the Windows half of an offline run as a warning as well" {
        # Both update functions read the same memoised connectivity check, so leaving one
        # of them an error would keep the exit code at 1 and make the change pointless
        Mock Update-Progress { }
        Mock Test-InternetConnection { $false }

        Update-WindowsSystem

        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 1
    }

    It "runs both halves offline through the real shared cache and still exits clean" {
        # The premise that lets one status field describe both halves is the SHARED cache,
        # which the two tests above bypass by mocking the check itself. Here the cache is
        # primed directly and both functions are called in the order Start-WinClean uses,
        # so a regression in the caching or in status propagation shows up. It does NOT
        # exercise the dispatcher itself: reordering the two calls inside Start-WinClean
        # would still pass, and running the real phase would run real maintenance
        $previousCache = $script:InternetConnectionCache
        $script:InternetConnectionCache = $false
        Mock Update-Progress { }
        try {
            Update-WindowsSystem
            Update-Applications
        } finally { $script:InternetConnectionCache = $previousCache }

        $script:Stats.AppUpdatesStatus   | Should -Be 'skipped-offline'
        [int]$script:Stats.ErrorsCount   | Should -Be 0
        [int]$script:Stats.WarningsCount | Should -Be 2
    }
}

#endregion
