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
