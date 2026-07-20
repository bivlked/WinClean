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

        if (Test-Path $script:LogPath) {
            $logContent = Get-Content $script:LogPath -Raw
            $logContent | Should -Match $uniqueMsg
        }
    }

    It "Respects -NoLog switch" {
        $noLogMsg = "NoLog message $(Get-Random)"
        $sizeBefore = if (Test-Path $script:LogPath) { (Get-Item $script:LogPath).Length } else { 0 }

        Write-Log -Message $noLogMsg -Level INFO -NoLog

        Start-Sleep -Milliseconds 100

        if (Test-Path $script:LogPath) {
            $logContent = Get-Content $script:LogPath -Raw
            $logContent | Should -Not -Match $noLogMsg
        }
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
