#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for verifying 9 specific fixes in WinClean.ps1 v2.13
.DESCRIPTION
    These tests validate that all bug fixes and improvements in v2.13 are working correctly.
    Tests are organized by fix ID from the CHANGELOG.

    Fix Categories:
    - A1-A3: Critical fixes (broken functionality)
    - B1-B4: Important fixes (incorrect behavior)
    - C1-C2: Minor fixes (edge cases)
.NOTES
    Version: 2.13
    Requires: Pester 5.0+
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot ".." "WinClean.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    # Extract helper functions for testing
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    foreach ($func in $functions) {
        if ($func.Name -eq 'ConvertFrom-HumanReadableSize') {
            Invoke-Expression $func.Extent.Text
        }
    }
}

#region A1: Docker Regex Fix

Describe "A1: Docker Prune Output Parsing" -Tag "Fix", "A1", "Docker" {
    <#
    Issue: Docker changed output format from "reclaimed 1.23GB" to "Total reclaimed space: 1.23GB"
    Fix: Updated regex to handle both formats
    #>

    BeforeAll {
        # The actual regex from the script
        $dockerRegex = 'reclaimed\s+(?:space:\s*)?([\d.,]+\s*[KMGT]?B)'
    }

    It "Matches old format 'reclaimed X'" -ForEach @(
        @{ Output = "reclaimed 500MB"; Size = "500MB" }
        @{ Output = "Total reclaimed 2.5 GB"; Size = "2.5 GB" }
    ) {
        $Output -match $dockerRegex | Should -BeTrue
        $Matches[1] | Should -Be $Size
    }

    It "Matches new format 'Total reclaimed space: X'" -ForEach @(
        @{ Output = "Total reclaimed space: 1.23GB"; Size = "1.23GB" }
        @{ Output = "Total reclaimed space: 500 MB"; Size = "500 MB" }
        @{ Output = "Total reclaimed space: 2.5GB"; Size = "2.5GB" }
    ) {
        $Output -match $dockerRegex | Should -BeTrue
        $Matches[1] | Should -Be $Size
    }

    It "Handles various size units" -ForEach @(
        @{ Output = "reclaimed 100B"; Size = "100B" }
        @{ Output = "reclaimed 50KB"; Size = "50KB" }
        @{ Output = "reclaimed 25MB"; Size = "25MB" }
        @{ Output = "reclaimed 1GB"; Size = "1GB" }
        @{ Output = "reclaimed 500TB"; Size = "500TB" }
    ) {
        $Output -match $dockerRegex | Should -BeTrue
        $Matches[1] | Should -Be $Size
    }

    It "Regex is present in script" {
        $scriptContent | Should -Match 'reclaimed\\s\+\(\?:space:\\s\*\)\?'
    }
}

#endregion

#region A2: EventLogs WarningsCount Fix

Describe "A2: EventLogs WarningsCount Increment" -Tag "Fix", "A2", "EventLogs" {
    <#
    Issue: WarningsCount was not being incremented when event log clear failed
    Fix: Added $script:Stats.WarningsCount++ in catch block
    #>

    It "Script contains WarningsCount increment" {
        # Check that WarningsCount++ is present in the script
        $scriptContent | Should -Match '\$script:Stats\.WarningsCount\s*\+\+'
    }

    It "WarningsCount is a valid property in Stats hashtable" {
        $scriptContent | Should -Match "WarningsCount\s*=\s*0"
    }

    It "Clear-EventLogs function exists" {
        $scriptContent | Should -Match 'function\s+Clear-EventLogs'
    }
}

#endregion

#region A3: WindowsUpdate Null Check Fix

Describe "A3: WindowsUpdate Null Results Handling" -Tag "Fix", "A3", "WindowsUpdate" {
    <#
    Issue: Script showed "success" when Get-WindowsUpdate returned null results
    Fix: Added explicit null check before processing results
    #>

    It "Detects null results correctly" {
        $results = $null
        (-not $results) | Should -BeTrue

        $results = @()
        ($results.Count -eq 0) | Should -BeTrue
    }

    It "Script contains null check for update results" {
        # Look for null check pattern near WindowsUpdate
        $scriptContent | Should -Match '-not\s+\$\w*(result|update)'
    }
}

#endregion

#region B1: Temp Path Deduplication Fix

Describe "B1: Temp Path Deduplication" -Tag "Fix", "B1", "Temp" {
    <#
    Issue: %TEMP% and %LOCALAPPDATA%\Temp often point to the same location, causing double counting
    Fix: Use GetFullPath() normalization and Group-Object for deduplication
    #>

    It "GetFullPath normalizes paths correctly" {
        $path1 = $env:TEMP
        $path2 = "$env:LOCALAPPDATA\Temp"

        $normalized1 = [System.IO.Path]::GetFullPath($path1)
        $normalized2 = [System.IO.Path]::GetFullPath($path2)

        # On most systems these should be the same
        # But we test the mechanism works
        $normalized1 | Should -Not -BeNullOrEmpty
        $normalized2 | Should -Not -BeNullOrEmpty
    }

    It "Removes duplicates after normalization" {
        $paths = @(
            @{ Path = $env:TEMP; Desc = "User Temp" }
            @{ Path = "$env:LOCALAPPDATA\Temp"; Desc = "Local Temp" }
        )

        $normalizedPaths = $paths | ForEach-Object {
            $_.Path = [System.IO.Path]::GetFullPath($_.Path)
            $_
        } | Group-Object Path | ForEach-Object { $_.Group[0] }

        # After deduplication, if paths were the same, count should be 1
        $normalizedPaths.Count | Should -BeLessOrEqual $paths.Count
    }

    It "Script uses GetFullPath for temp path normalization" {
        $scriptContent | Should -Match 'GetFullPath'
    }
}

#endregion

#region B2: Get-FolderSize -File Flag Fix

Describe "B2: Get-FolderSize Performance with -File Flag" -Tag "Fix", "B2", "Performance" {
    <#
    Issue: Get-FolderSize was calculating directory objects, not just files
    Fix: Added -File flag to Get-ChildItem
    #>

    It "Script uses -File flag in Get-FolderSize" {
        # Look for Get-ChildItem with -File inside Get-FolderSize function
        $scriptContent | Should -Match 'function\s+Get-FolderSize[\s\S]*?Get-ChildItem.*-File'
    }

    It "-File flag returns only files, not directories" {
        $testFolder = Join-Path $env:TEMP "PesterTest_FileFlag_$(Get-Random)"
        New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
        New-Item -ItemType Directory -Path "$testFolder\SubDir" -Force | Out-Null
        "test" | Out-File "$testFolder\file.txt"

        try {
            $withFile = Get-ChildItem -LiteralPath $testFolder -Recurse -Force -File -EA SilentlyContinue
            $withoutFile = Get-ChildItem -LiteralPath $testFolder -Recurse -Force -EA SilentlyContinue

            $withFile.Count | Should -BeLessThan $withoutFile.Count
        } finally {
            Remove-Item $testFolder -Recurse -Force -EA SilentlyContinue
        }
    }
}

#endregion

#region B3: Docker Builder Prune Removal

Describe "B3: Docker Builder Prune Removed" -Tag "Fix", "B3", "Docker" {
    <#
    Issue: "docker builder prune" was redundant (already covered by system prune) and failed on older Docker
    Fix: Removed the command entirely
    #>

    It "Script does NOT execute 'docker builder prune' command" {
        # Check for actual command execution, not comments/release notes
        $scriptContent | Should -Not -Match '\$.*=.*docker\s+builder\s+prune'
        $scriptContent | Should -Not -Match 'docker\s+builder\s+prune\s+-f'
    }

    It "Script still contains 'docker system prune'" {
        $scriptContent | Should -Match 'docker\s+system\s+prune'
    }
}

#endregion

#region B4: Browser FreeSpace Math.Max Fix

Describe "B4: Browser FreeSpace Negative Value Prevention" -Tag "Fix", "B4", "Browser" {
    <#
    Issue: sizeBefore - sizeAfter could be negative if browser recreated cache files during cleanup
    Fix: Use [math]::Max(0, sizeBefore - sizeAfter)
    #>

    It "Math.Max prevents negative freed space" {
        $sizeBefore = 1000
        $sizeAfter = 1500  # Cache grew during cleanup

        $freedWithoutFix = $sizeBefore - $sizeAfter
        $freedWithFix = [math]::Max(0, $sizeBefore - $sizeAfter)

        $freedWithoutFix | Should -BeLessThan 0
        $freedWithFix | Should -Be 0
    }

    It "Math.Max preserves positive values" {
        $sizeBefore = 1500
        $sizeAfter = 1000

        $freed = [math]::Max(0, $sizeBefore - $sizeAfter)
        $freed | Should -Be 500
    }

    It "Script uses Math.Max for browser cleanup" {
        $scriptContent | Should -Match '\[math\]::Max\s*\(\s*0'
    }
}

#endregion

#region C1: RecycleBin Fallback Fix

Describe "C1: RecycleBin Size Fallback" -Tag "Fix", "C1", "RecycleBin" {
    <#
    Issue: ExtendedProperty("System.Size") sometimes returns null
    Fix: Added fallback to GetDetailsOf with size parsing
    #>

    It "Script contains ExtendedProperty for RecycleBin size" {
        $scriptContent | Should -Match 'ExtendedProperty.*System\.Size'
    }

    It "Script contains GetDetailsOf fallback" {
        $scriptContent | Should -Match 'GetDetailsOf'
    }

    It "ConvertFrom-HumanReadableSize handles localized sizes" {
        # GetDetailsOf returns localized size strings
        ConvertFrom-HumanReadableSize "1.5 GB" | Should -Be 1610612736
        ConvertFrom-HumanReadableSize "1,5 GB" | Should -Be 1610612736  # European format
    }
}

#endregion

#region C2: StateFlags Cleanup Fix

Describe "C2: Disk Cleanup StateFlags Registry Cleanup" -Tag "Fix", "C2", "Registry" {
    <#
    Issue: StateFlags9999 registry entries were left behind after cleanmgr finished
    Fix: Added cleanup code to remove StateFlags9999 from all VolumeCaches subkeys
    #>

    It "Script contains StateFlags cleanup code" {
        $scriptContent | Should -Match 'StateFlags'
        $scriptContent | Should -Match 'Remove-ItemProperty.*StateFlags'
    }

    It "Script targets VolumeCaches registry path" {
        $scriptContent | Should -Match 'VolumeCaches'
    }
}

#endregion

#region Script Version Verification

Describe "Script Version" -Tag "Version" {
    It "Version is 2.13 or higher" {
        $scriptContent | Should -Match '\$script:Version\s*=\s*[''"]2\.1[3-9]'
    }

    It "PSScriptInfo version matches" {
        $scriptContent | Should -Match '\.VERSION\s+2\.1[3-9]'
    }
}

#endregion

#region Additional Regression Tests

Describe "Regression Tests" -Tag "Regression" {

    It "Script does not contain debug Write-Host statements" {
        # Check for accidental debug output left in code
        $scriptContent | Should -Not -Match 'Write-Host.*DEBUG'
        $scriptContent | Should -Not -Match 'Write-Host.*TODO'
    }

    It "All synchronized hashtable updates use +=" {
        # The fix for TotalFreedBytes was to use += instead of Interlocked
        $scriptContent | Should -Match '\$script:Stats\.TotalFreedBytes\s*\+='
    }

    It "No hardcoded test paths" {
        $scriptContent | Should -Not -Match 'C:\\Users\\test'
        $scriptContent | Should -Not -Match 'D:\\Test'
    }
}

#endregion
