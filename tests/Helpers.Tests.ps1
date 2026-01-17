#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for WinClean.ps1 helper functions
.DESCRIPTION
    Tests safe, non-destructive helper functions that can run in CI/CD.
    These tests do not require Administrator rights or modify the system.
.NOTES
    Version: 2.13
    Requires: Pester 5.0+
#>

BeforeAll {
    # Define helper functions directly (extracted from WinClean.ps1)
    # This is more reliable than AST parsing in Pester context

    function Format-FileSize {
        param([long]$Bytes)
        if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "$Bytes B"
    }

    function ConvertFrom-HumanReadableSize {
        param([string]$SizeString)
        if (-not $SizeString) { return 0 }
        if ($SizeString -match '^([\d.,]+)\s*([KMGT]?B)$') {
            $value = [double]($Matches[1] -replace ',', '.')
            $unit = $Matches[2].ToUpper()
            $multiplier = switch ($unit) {
                'B'  { 1 }
                'KB' { 1KB }
                'MB' { 1MB }
                'GB' { 1GB }
                'TB' { 1TB }
                default { 1 }
            }
            return [long]($value * $multiplier)
        }
        return 0
    }

    function Get-FolderSize {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            return 0
        }
        try {
            $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            return [long]($size ?? 0)
        } catch {
            return 0
        }
    }

    function Test-PathProtected {
        param([string]$Path)
        $normalizedPath = $Path.TrimEnd('\', '/')
        foreach ($protected in $script:ProtectedPaths) {
            $normalizedProtected = $protected.TrimEnd('\', '/')
            if ($normalizedPath -ieq $normalizedProtected) {
                return $true
            }
        }
        return $false
    }

    function Test-InteractiveConsole {
        try {
            if ($Host.Name -ne 'ConsoleHost') { return $false }
            $null = [Console]::WindowWidth
            return $true
        } catch {
            return $false
        }
    }

    function Test-PendingReboot {
        $rebootRequired = $false
        $reasons = @()

        $wuKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        if (Test-Path $wuKey) {
            $rebootRequired = $true
            $reasons += "Windows Update"
        }

        $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        if (Test-Path $cbsKey) {
            $rebootRequired = $true
            $reasons += "Component Servicing"
        }

        $pfroKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        try {
            $pfroValue = Get-ItemProperty -Path $pfroKey -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($pfroValue.PendingFileRenameOperations) {
                $rebootRequired = $true
                $reasons += "File Rename Operations"
            }
        } catch { }

        $compNameKey = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName"
        try {
            $activeName = (Get-ItemProperty "$compNameKey\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
            $pendingName = (Get-ItemProperty "$compNameKey\ComputerName" -ErrorAction SilentlyContinue).ComputerName
            if ($activeName -ne $pendingName) {
                $rebootRequired = $true
                $reasons += "Computer Rename"
            }
        } catch { }

        return @{
            RebootRequired = $rebootRequired
            Reasons        = $reasons
        }
    }

    function Get-RecycleBinSize {
        $totalSize = [long]0
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            foreach ($item in $recycleBin.Items()) {
                try {
                    $itemSize = $item.ExtendedProperty("System.Size")
                    if ($itemSize) {
                        $totalSize += [long]$itemSize
                    } else {
                        $sizeStr = $recycleBin.GetDetailsOf($item, 2)
                        if ($sizeStr) {
                            $totalSize += ConvertFrom-HumanReadableSize $sizeStr
                        }
                    }
                } catch { }
            }
        } catch { }
        return $totalSize
    }

    function Write-Log {
        param(
            [Parameter(Mandatory)]
            [string]$Message,
            [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'TITLE', 'SECTION', 'DETAIL')]
            [string]$Level = 'INFO',
            [switch]$NoNewLine,
            [switch]$NoTimestamp,
            [switch]$NoLog
        )

        $indent = "  "
        $boxWidth = 70
        $timestamp = (Get-Date).ToString('HH:mm:ss')
        $logMessage = "[$timestamp] [$Level] $Message"

        if (-not $NoLog) {
            try {
                $logMessage | Out-File -FilePath $script:LogPath -Append -Encoding utf8 -ErrorAction SilentlyContinue
            } catch { }
        }

        $colors = @{
            INFO    = @{ Tag = 'Cyan';    Message = 'White' }
            SUCCESS = @{ Tag = 'Green';   Message = 'White' }
            WARNING = @{ Tag = 'Yellow';  Message = 'Yellow' }
            ERROR   = @{ Tag = 'Red';     Message = 'Red' }
            TITLE   = @{ Tag = 'Magenta'; Message = 'Magenta' }
            SECTION = @{ Tag = 'Cyan';    Message = 'Cyan' }
            DETAIL  = @{ Tag = 'DarkGray';Message = 'Gray' }
        }

        $tagColors = $colors[$Level]

        switch ($Level) {
            'TITLE' {
                $titleText = $Message.ToUpper()
                $padding = [math]::Max(0, $boxWidth - $titleText.Length)
                $leftPad = [math]::Floor($padding / 2)
                $rightPad = $padding - $leftPad
                $centeredTitle = (" " * $leftPad) + $titleText + (" " * $rightPad)
                Write-Host ""
                Write-Host "$indent╔$("═" * $boxWidth)╗" -ForegroundColor $tagColors.Tag
                Write-Host "$indent║$centeredTitle║" -ForegroundColor $tagColors.Tag
                Write-Host "$indent╚$("═" * $boxWidth)╝" -ForegroundColor $tagColors.Tag
            }
            'SECTION' {
                Write-Host ""
                Write-Host "$indent┌─ " -NoNewline -ForegroundColor DarkGray
                Write-Host $Message -ForegroundColor $tagColors.Message
                Write-Host "$indent└$("─" * 70)" -ForegroundColor DarkGray
            }
            'DETAIL' {
                Write-Host "$indent  │ " -NoNewline -ForegroundColor DarkGray
                Write-Host $Message -ForegroundColor $tagColors.Message -NoNewline:$NoNewLine
                if (-not $NoNewLine) { Write-Host "" }
            }
            default {
                Write-Host $indent -NoNewline
                if (-not $NoTimestamp) {
                    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
                }
                $tagText = switch ($Level) {
                    'INFO'    { '[INFO]  ' }
                    'SUCCESS' { '[OK]    ' }
                    'WARNING' { '[WARN]  ' }
                    'ERROR'   { '[ERROR] ' }
                }
                Write-Host $tagText -NoNewline -ForegroundColor $tagColors.Tag
                Write-Host $Message -ForegroundColor $tagColors.Message -NoNewline:$NoNewLine
                if (-not $NoNewLine) { Write-Host "" }
            }
        }
    }

    # Set up script-scope variables needed by some functions
    $script:ProtectedPaths = @(
        $env:SystemRoot,
        "$env:SystemRoot\System32",
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:USERPROFILE,
        "$env:SystemDrive\Users",
        "$env:SystemDrive\Program Files",
        "$env:SystemDrive\Program Files (x86)"
    )

    $script:LogPath = Join-Path $env:TEMP "WinClean_PesterTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

AfterAll {
    # Clean up test log file
    if (Test-Path $script:LogPath) {
        Remove-Item $script:LogPath -Force -ErrorAction SilentlyContinue
    }
}

#region Format-FileSize Tests

Describe "Format-FileSize" -Tag "Unit", "Helper" {

    It "Returns '<Expected>' for <Bytes> bytes" -ForEach @(
        @{ Bytes = 0;            Expected = "0 B" }
        @{ Bytes = 1;            Expected = "1 B" }
        @{ Bytes = 512;          Expected = "512 B" }
        @{ Bytes = 1023;         Expected = "1023 B" }
        @{ Bytes = 1024;         Expected = "1.00 KB" }
        @{ Bytes = 1536;         Expected = "1.50 KB" }
        @{ Bytes = 1048576;      Expected = "1.00 MB" }
        @{ Bytes = 1572864;      Expected = "1.50 MB" }
        @{ Bytes = 1073741824;   Expected = "1.00 GB" }
        @{ Bytes = 1610612736;   Expected = "1.50 GB" }
    ) {
        Format-FileSize -Bytes $Bytes | Should -Be $Expected
    }

    It "Handles large values (TB range)" {
        $result = Format-FileSize -Bytes (1GB * 1500)
        $result | Should -Match "^\d+\.\d{2} GB$"
    }

    It "Handles negative values gracefully" {
        # Negative bytes shouldn't happen, but function should not throw
        { Format-FileSize -Bytes -100 } | Should -Not -Throw
    }
}

#endregion

#region ConvertFrom-HumanReadableSize Tests

Describe "ConvertFrom-HumanReadableSize" -Tag "Unit", "Helper" {

    It "Converts '<Input>' to <Expected>" -ForEach @(
        @{ Input = "0 B";      Expected = 0 }
        @{ Input = "100 B";    Expected = 100 }
        @{ Input = "1 KB";     Expected = 1024 }
        @{ Input = "1KB";      Expected = 1024 }
        @{ Input = "1.5 KB";   Expected = 1536 }
        @{ Input = "512 KB";   Expected = 524288 }
        @{ Input = "1 MB";     Expected = 1048576 }
        @{ Input = "1MB";      Expected = 1048576 }
        @{ Input = "2.5 MB";   Expected = 2621440 }
        @{ Input = "1 GB";     Expected = 1073741824 }
        @{ Input = "1GB";      Expected = 1073741824 }
        @{ Input = "2.5 GB";   Expected = 2684354560 }
        @{ Input = "1 TB";     Expected = 1099511627776 }
    ) {
        ConvertFrom-HumanReadableSize -SizeString $Input | Should -Be $Expected
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
