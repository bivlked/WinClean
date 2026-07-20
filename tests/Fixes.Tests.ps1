#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for verifying specific fixes in WinClean.ps1 (v2.13 and v2.14)
.DESCRIPTION
    These tests validate that bug fixes and improvements are working correctly.
    Tests are organized by fix ID from the CHANGELOG.

    Fix Categories:
    - A1-A3: Critical fixes v2.13 (broken functionality)
    - B1-B4: Important fixes v2.13 (incorrect behavior)
    - C1-C2: Minor fixes v2.13 (edge cases)
    - V214: Regression tests for v2.14 fixes
.NOTES
    Version: 2.14
    Requires: Pester 5.0+
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot ".." "WinClean.ps1"
    $scriptContent = Get-Content $scriptPath -Raw

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $script:AllFunctions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    # v2.17: scopes a regex to one function. A match over the whole file stays green
    # even when the code under test is deleted, because the same string also lives in a
    # comment, in .RELEASENOTES or in another function. Verified case: the TEMP age
    # filter test was matching the kernel dump cleanup instead.
    function Get-FunctionBody {
        param([Parameter(Mandatory)][string]$Name)
        $fn = $script:AllFunctions | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $fn) { throw "Function '$Name' not found in WinClean.ps1" }
        return $fn.Extent.Text
    }

    # v2.17: dot-source the product instead of Invoke-Expression on an extracted
    # function. Same effect for the few tests that call a helper directly, but without
    # re-implementing PowerShell's own loading and without the analyzer warning.
    # WinClean.ps1 guards its entry point, so nothing is executed by loading it.
    . $scriptPath
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

    It "Clear-EventLogs increments the warning counter on failure" {
        # v2.17: scoped to the function. The bare string occurs about 37 times in the
        # file, so the old whole-file check stayed green even with the increment
        # removed from this very function.
        $body = Get-FunctionBody -Name 'Clear-EventLogs'
        $body | Should -Match '\$script:Stats\.WarningsCount\s*\+\+'
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
        # v2.17: scoped - the loose pattern matched any variable whose name contains
        # "result" or "update", anywhere in 3700 lines
        $body = Get-FunctionBody -Name 'Update-WindowsSystem'
        $body | Should -Match '-not\s+\$results'
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

#region v2.14 Fixes

Describe "v2.14: Log file protected from temp cleanup" -Tag "Fix", "V214" {
    It "Remove-FolderContent supports ExcludeFile parameter" {
        $scriptContent | Should -Match '\[string\[\]\]\$ExcludeFile'
    }

    It "Clear-TempFiles excludes the active log file" {
        # The call is wrapped across lines since v2.16, so allow a backtick continuation
        $scriptContent | Should -Match '(?s)Remove-FolderContent[^\r\n]*(`\r?\n\s*)?-ExcludeFile \$script:LogPath'
    }
}

Describe "v2.14: Cache path corrections" -Tag "Fix", "V214" {
    It "npm cache checks LOCALAPPDATA (npm v7+) before APPDATA" {
        $scriptContent | Should -Match '\$env:LOCALAPPDATA\\npm-cache'
    }

    It "Firefox cache is looked up under LOCALAPPDATA" {
        $scriptContent | Should -Match '\$env:LOCALAPPDATA\\Mozilla\\Firefox\\Profiles'
    }

    It "uv cache cleanup is present" {
        $scriptContent | Should -Match '\$env:LOCALAPPDATA\\uv\\cache'
    }
}

Describe "v2.14: Dead internet probe replaced" -Tag "Fix", "V214" {
    It "winget.azureedge.net (retired CDN) is no longer probed" {
        # Check the probe target list specifically (the name may legitimately
        # appear in release notes)
        $scriptContent | Should -Not -Match "Host = 'winget\.azureedge\.net'"
    }

    It "cdn.winget.microsoft.com is probed instead" {
        $scriptContent | Should -Match "Host = 'cdn\.winget\.microsoft\.com'"
    }
}

Describe "v2.14: DISM analyze-first optimization" -Tag "Fix", "V214" {
    It "AnalyzeComponentStore runs with /English for parseable output" {
        $scriptContent | Should -Match '"/English",\s*"/Cleanup-Image",\s*"/AnalyzeComponentStore"'
    }

    It "Cleanup recommendation is parsed" {
        $scriptContent | Should -Match 'Component Store Cleanup Recommended'
    }
}

Describe "v2.14: Restore point 24h limit bypass" -Tag "Fix", "V214" {
    It "SystemRestorePointCreationFrequency is temporarily lifted and restored" {
        $scriptContent | Should -Match 'SystemRestorePointCreationFrequency'
        # Must restore the previous value afterwards
        $scriptContent | Should -Match 'prevFreq'
    }
}

Describe "v2.14: Safer cleanmgr categories" -Tag "Fix", "V214" {
    BeforeAll {
        # v2.17: both checks are scoped to the $categories array. The previous patterns
        # ran against the whole file, where the same names appear in the explanatory
        # comment above the array - and the ESD one used "$" in single-line mode, so it
        # anchored to the end of the entire file and could never match at all.
        $categoriesBlock = [regex]::Match(
            (Get-FunctionBody -Name 'Invoke-StorageSense'), '(?s)\$categories = @\((.*?)\n\s*\)'
        ).Groups[1].Value
    }

    It "The category list was found" {
        $categoriesBlock | Should -Not -BeNullOrEmpty
    }

    It "Does not auto-delete Previous Installations (Windows.old needs confirmation)" {
        $categoriesBlock | Should -Not -Match 'Previous Installations'
    }

    It "Does not delete Windows ESD installation files (needed for Reset this PC)" {
        $categoriesBlock | Should -Not -Match 'Windows ESD installation files'
    }
}

Describe "v2.14: Event log enumeration" -Tag "Fix", "V214" {
    It "Uses Get-WinEvent -ListLog with RecordCount/IsEnabled/LogType filter" {
        $scriptContent | Should -Match 'Get-WinEvent -ListLog \*'
        $scriptContent | Should -Match 'RecordCount -gt 0'
        $scriptContent | Should -Match "LogType -in @\('Administrative', 'Operational'\)"
    }
}

Describe "v2.14: winget hardening" -Tag "Fix", "V214" {
    It "Upgrade check runs with --disable-interactivity and --accept-source-agreements" {
        $scriptContent | Should -Match '"--accept-source-agreements", "--disable-interactivity"'
    }
}

Describe "v2.15: positional binding hardening" -Tag "Fix", "V215" {
    It "CmdletBinding disables positional binding (stray args must fail loudly)" {
        $scriptContent | Should -Match 'PositionalBinding\s*=\s*\$false'
    }

    It "get.ps1 uses hashtable splatting for parameter passthrough" {
        $getContent = Get-Content (Join-Path $PSScriptRoot '..' 'get.ps1') -Raw
        $getContent | Should -Match '& \$destPath @splat'
        $getContent | Should -Not -Match '& \$destPath @WinCleanArgs'
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

#region v2.16 Fixes

Describe "v2.16: Delivery Optimization cache path" -Tag "Fix", "V216" {
    It "Probes the NetworkService profile location" {
        # The ProgramData path does not exist on Windows 11, so every size read returned 0
        $scriptContent | Should -Match 'ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization'
    }

    It "Keeps the legacy path as a fallback" {
        $scriptContent | Should -Match '\$env:ProgramData\\Microsoft\\Windows\\DeliveryOptimization'
    }

    It "Only uses locations that actually exist" {
        $scriptContent | Should -Match '\$doPaths\s*=\s*@\('
        $scriptContent | Should -Match 'Where-Object \{ Test-Path \$_ -ErrorAction SilentlyContinue \}'
    }
}

Describe "v2.16: TEMP age filter" -Tag "Fix", "V216" {
    It "Remove-FolderContent accepts MinAgeDays" {
        # v2.17: scoped to the function - Clear-KernelDumps declares a parameter of the
        # same name, so a whole-file match passed even with the TEMP filter deleted
        $body = Get-FunctionBody -Name 'Remove-FolderContent'
        $body | Should -Match '\[int\]\$MinAgeDays'
    }

    It "Clear-TempFiles passes MinAgeDays 1" {
        $scriptContent | Should -Match '-MinAgeDays 1'
    }

    It "Age filter compares LastWriteTime against the cutoff" {
        $scriptContent | Should -Match '\$_\.LastWriteTime -lt \$cutoff'
    }

    It "Directories are checked recursively" {
        # A parent's LastWriteTime does not move when a grandchild changes, so a
        # top-level-only check would delete fresh files nested deeper
        $scriptContent | Should -Match '(?s)if \(\$_\.PSIsContainer\).*?Get-ChildItem -LiteralPath \$_\.FullName -Recurse'
    }

    It "ReportOnly measures only eligible entries when filtering by age" {
        # Otherwise the report would promise more than the run deletes
        $scriptContent | Should -Match '\$getEligible'
    }
}

Describe "v2.16: Windows Update service stop is verified" -Tag "Fix", "V216" {
    It "Waits for the Stopped status" {
        $scriptContent | Should -Match 'WaitForStatus\(\[System\.ServiceProcess\.ServiceControllerStatus\]::Stopped'
    }

    It "Warns when a service is still running" {
        $scriptContent | Should -Match 'still running after 30s'
    }
}

Describe "v2.16: Controlled Folder Access preflight" -Tag "Fix", "V216" {
    It "Reads the Defender preference" {
        $scriptContent | Should -Match 'Get-MpPreference'
        $scriptContent | Should -Match 'EnableControlledFolderAccess -eq 1'
    }

    It "Exposes the flag in the result JSON" {
        $scriptContent | Should -Match 'ControlledFolderAccess = \[string\]\$script:Stats\.ControlledFolderAccess'
    }

    It "Reports 'unknown' when the check itself fails" {
        # Reporting false would tell an automated stand the figures are trustworthy
        # when Controlled Folder Access was never actually checked
        $scriptContent | Should -Match "ControlledFolderAccess = 'unknown'"
    }

    It "Missing Defender cmdlets are not treated as an error" {
        $scriptContent | Should -Match 'Get-MpPreference -ErrorAction Stop'
    }
}

Describe "v2.16: Disk Cleanup categories match the registry" -Tag "Fix", "V216" {

    BeforeAll {
        # Scoped to the $categories array: the comment above it names the removed
        # handlers, so a whole-file match would report them as still present
        $categoriesBlock = [regex]::Match($scriptContent, '(?s)\$categories = @\((.*?)\n\s*\)').Groups[1].Value
    }

    It "The category list was found" {
        $categoriesBlock | Should -Not -BeNullOrEmpty
    }

    It "Non-existent handlers are gone" {
        $categoriesBlock | Should -Not -Match '"Memory Dump Files"'
        $categoriesBlock | Should -Not -Match '"Windows Error Reporting Archive Files"'
        $categoriesBlock | Should -Not -Match '"Windows Error Reporting Queue Files"'
    }

    It "The real WER handler name is used" {
        $categoriesBlock | Should -Match '"Windows Error Reporting Files"'
    }

    It "Shader cache is covered" {
        $categoriesBlock | Should -Match '"D3D Shader Cache"'
    }

    It "Driver packages are left to Clear-DriverStore" {
        # cleanmgr would pick packages by its own closed heuristic, bypassing the
        # conservative unused-AND-superseded rule and giving no measurable result
        $categoriesBlock | Should -Not -Match '"Device Driver Packages"'
    }

    It "The user Downloads folder is never a cleanup target" {
        $categoriesBlock | Should -Not -Match '"DownloadsFolder"'
    }
}

Describe "v2.16: StateFlags cleanup sweeps every handler" -Tag "Fix", "V216" {
    It "Iterates the registry instead of the local category list" {
        # Flags left by an interrupted run used to stay in the registry forever
        $scriptContent | Should -Match '(?s)Get-ChildItem -Path \$regPath[^
]*\|\s*ForEach-Object \{\s*Remove-ItemProperty'
    }
}

Describe "v2.16: progress bars are all closed" -Tag "Fix", "V216" {
    It "Clear-AllProgress exists" {
        $scriptContent | Should -Match 'function Clear-AllProgress'
    }

    It "Activities are tracked as they are used" {
        $scriptContent | Should -Match '\$script:ProgressActivities'
    }

    It "Foreign bars are cleared by Id" {
        $scriptContent | Should -Match 'Write-Progress -Id \$id -Activity'
    }

    It "Obsolete no-op calls are gone" {
        $scriptContent | Should -Not -Match 'Write-Progress -Activity "Complete" -Completed'
        $scriptContent | Should -Not -Match 'Write-Progress -Activity "Cleanup" -Completed'
    }
}

Describe "v2.16: winget exit codes are decoded" -Tag "Fix", "V216" {
    It "Known codes are mapped" {
        $scriptContent | Should -Match '0x8A15002C - some applications failed to upgrade'
        $scriptContent | Should -Match '0x8A15002B - no applicable update found'
    }

    It "Nothing-to-upgrade is not reported as a warning" {
        $scriptContent | Should -Match '\$code -eq -1978335189'
    }

    It "Unknown codes still show the hex value" {
        $scriptContent | Should -Match 'unrecognized winget exit code'
    }
}

Describe "v2.16: Disk Cleanup timeout" -Tag "Fix", "V216" {
    It "Waits longer than the previous 420 seconds" {
        $scriptContent | Should -Match '\$maxWait = 900'
    }

    It "Exceeding the wait is not counted as a warning" {
        $scriptContent | Should -Match 'leaving it to finish in the background'
    }

    It "cleanmgr is not killed on timeout" {
        # Killing it mid-delete achieved nothing and contradicted the log message
        $scriptContent | Should -Not -Match '\$cleanmgr \| Stop-Process'
    }
}

#endregion

#region v2.16 Features

Describe "v2.16: driver store cleanup" -Tag "Feature", "V216" {
    It "Enumerates driver packages as XML" {
        # Plain text output of pnputil switches language with the console code page
        $scriptContent | Should -Match "'/enum-drivers', '/devices', '/format', 'xml'"
    }

    It "Only removes packages with no bound device AND a newer sibling" {
        $scriptContent | Should -Match '\$pkg\.Oem -eq \$newest\.Oem -or \$pkg\.InUse'
    }

    It "Never uses /force" {
        $scriptContent | Should -Not -Match 'pnputil[^
]*/force'
    }

    It "Trusts the exit code, not the localized text" {
        $scriptContent | Should -Match '(?s)pnputil\.exe /delete-driver.*?\$LASTEXITCODE -eq 0'
    }

    It "Maps packages to folders by INF hash, not by version string" {
        # Several packages can share an identical DriverVer
        $scriptContent | Should -Match 'Get-FileHash \$infPath -Algorithm SHA256'
    }

    It "Reports its own statistics category" {
        $scriptContent | Should -Match 'FreedByCategory\["DriverStore"\]'
    }
}

Describe "v2.16: kernel dump cleanup" -Tag "Feature", "V216" {
    It "Targets LiveKernelReports" {
        $scriptContent | Should -Match "LiveKernelReports"
    }

    It "Only deletes dumps older than the age threshold" {
        $scriptContent | Should -Match '\$_\.LastWriteTime -lt \$cutoff'
        $scriptContent | Should -Match '\[int\]\$MinAgeDays = 30'
    }

    It "Only touches .dmp files" {
        $scriptContent | Should -Match "-Filter '\*\.dmp'"
    }
}

Describe "v2.16: disk space report" -Tag "Feature", "V216" {
    It "Function exists and is called" {
        $scriptContent | Should -Match 'function Show-DiskSpaceReport'
        $scriptContent | Should -Match '(?m)^\s*Show-DiskSpaceReport\s*$'
    }

    It "Reports the MSI cache as keep-only" {
        # Deleting it breaks uninstall and repair
        $scriptContent | Should -Match "MSI cache \(keep\)"
    }

    It "Reads shadow storage through CIM, not vssadmin" {
        # vssadmin prints numbers using the system decimal separator
        $scriptContent | Should -Match 'Get-CimInstance Win32_ShadowStorage'
        $scriptContent | Should -Not -Match 'vssadmin list shadowstorage'
    }
}

#endregion

#region v2.16 Silent failure hardening

Describe "v2.16: silent failures are reported" -Tag "Fix", "V216", "SilentFailure" {

    It "Kernel dump deletion failures are counted and logged" {
        # A blocked deletion used to be indistinguishable from "nothing to clean"
        $scriptContent | Should -Match 'could not be deleted'
        $scriptContent | Should -Not -Match '(?s)Remove-Item -LiteralPath \$file\.FullName[^}]*\}\s*catch \{ \}'
    }

    It "pnputil exit code is checked before parsing" {
        $scriptContent | Should -Match 'pnputil /enum-drivers returned \$\(\$pnp\.ExitCode\)'
    }

    It "Unparseable driver packages are counted, not silently dropped" {
        $scriptContent | Should -Match '\$skipped\+\+'
        $scriptContent | Should -Match 'no package could be parsed'
    }

    It "An unparseable driver date does not discard the package" {
        # A date format change would otherwise empty the candidate list forever
        $scriptContent | Should -Match '\[datetime\]::TryParse'
    }

    It "Driver store falls back to measuring the repository when sizes are unknown" {
        $scriptContent | Should -Match 'per-package size unavailable'
    }

    It "Delivery Optimization no longer claims success without measuring" {
        $scriptContent | Should -Not -Match '"Delivery Optimization cache cleaned"'
        $scriptContent | Should -Match 'freed size unknown'
    }

    It "Delete-DeliveryOptimizationCache failures are logged" {
        $scriptContent | Should -Match 'Delete-DeliveryOptimizationCache failed'
    }

    It "cleanmgr verifies that categories were actually armed" {
        $scriptContent | Should -Match 'No Disk Cleanup handlers could be armed'
        $scriptContent | Should -Match '\$armed\+\+'
    }

    It "cleanmgr exit code is checked" {
        $scriptContent | Should -Match 'Disk Cleanup exited with code'
    }

    It "Browser caches are not reported as cleaned when nothing was freed" {
        $scriptContent | Should -Not -Match 'Write-Log "Browser caches cleaned \(\$browserNames\)" -Level SUCCESS'
        $scriptContent | Should -Match 'Browser caches: nothing freed'
    }

    It "A cleanup that frees nothing from a non-empty folder is reported" {
        $scriptContent | Should -Match 'nothing freed, \$\(Format-FileSize \$sizeBefore\) still present'
    }

    It "The age filter fails closed when a subtree cannot be read" {
        # Failing open would silently defeat the protection the filter exists for
        $scriptContent | Should -Match 'if \(\$walkErrors\) \{ return \$false \}'
    }

    It "ReportOnly measures the same set the real run deletes" {
        $scriptContent | Should -Not -Match '\$size = Get-FolderSize -Path \$Path'
    }

    It "winget source timeout counts as a warning" {
        $scriptContent | Should -Match '(?s)Winget source update timed out[^\r\n]*\r?\n\s*\$script:Stats\.WarningsCount\+\+'
    }

    It "Result JSON write failure counts as a warning" {
        # An automated stand would otherwise read the previous run's file as fresh
        $scriptContent | Should -Match '(?s)Failed to write result JSON[^\r\n]*\r?\n\s*\$script:Stats\.WarningsCount\+\+'
    }

    It "Downloaded updates are not counted as installed" {
        $scriptContent | Should -Match "\`$_\.Result -eq 'Installed'"
        $scriptContent | Should -Match 'downloaded but not yet applied'
    }
}

#endregion

#region v2.17 Bootstrap and path safety (findings from the Codex review)

Describe "v2.17: get.ps1 argument parser cannot silently disable a preview" -Tag "Fix", "V217" {

    BeforeAll {
        $getScript = Get-Content (Join-Path $PSScriptRoot '..' 'get.ps1') -Raw
    }

    It "Rejects an invalid switch value instead of treating it as false" {
        # "-ReportOnly:yes" used to evaluate to $false and start a real cleanup
        $getScript | Should -Match "Invalid value '\`$raw' for switch"
        $getScript | Should -Match "\`$clean -notmatch '\^\(true\|false\)\`$'"
    }

    It "Does not consume a parameter name as a value" {
        # "-LogPath -ReportOnly" used to set LogPath='-ReportOnly' and leave the
        # preview flag off, turning a dry run into a real one
        $getScript | Should -Match "\`$WinCleanArgs\[\`$i \+ 1\] -notmatch '\^-\{1,2\}\[A-Za-z\]'"
    }

    It "Validates parameter names before downloading anything" {
        $getScript | Should -Match "Unknown parameter"
    }
}

Describe "v2.17: bootstrap verification is mandatory" -Tag "Fix", "V217" {

    BeforeAll {
        $getScript = Get-Content (Join-Path $PSScriptRoot '..' 'get.ps1') -Raw
        $installScript = Get-Content (Join-Path $PSScriptRoot '..' 'install.ps1') -Raw
    }

    It "Both scripts refuse a release without the hash asset" -ForEach @(
        @{ Name = 'get.ps1' }, @{ Name = 'install.ps1' }
    ) {
        $content = if ($Name -eq 'get.ps1') { $getScript } else { $installScript }
        $content | Should -Match 'does not publish both WinClean\.ps1 and WinClean\.ps1\.sha256'
        # The old code hid verification inside "if ($hashAsset)", so a missing asset
        # skipped it entirely and silently
        $content | Should -Not -Match '(?m)^\s*if \(\$hashAsset\) \{'
    }

    It "Neither script falls back to a mutable branch or tag" {
        $getScript | Should -Not -Match 'raw\.githubusercontent\.com/\$repo/\$\(\$release\.tag_name\)'
        $installScript | Should -Not -Match 'raw\.githubusercontent\.com/\$repo/\$\(\$release\.tag_name\)'
    }

    It "Hashes are compared literally, not as a wildcard pattern" -ForEach @(
        @{ Name = 'get.ps1' }, @{ Name = 'install.ps1' }
    ) {
        $content = if ($Name -eq 'get.ps1') { $getScript } else { $installScript }
        # "-notlike" made a single "*" in the hash file verify any download
        $content | Should -Not -Match '\$actual -notlike \$expected'
        $content | Should -Match '\[string\]::Equals\(\$actual, \$expected'
        $content | Should -Match "'\^\[0-9a-fA-F\]\{64\}\`$'"
    }

    It "install.ps1 still checks that the asset looks like WinClean" {
        # The hash proves the two assets agree, not that the payload is our script
        $installScript | Should -Match "Contains\('PSScriptInfo'\)"
    }

    It "install.ps1 does not trust user-writable environment variables" {
        # $env:ProgramFiles is writable by a non-admin process and would let it aim an
        # elevated shortcut at its own binary
        $installScript | Should -Match "\[Environment\]::GetFolderPath\(\[Environment\+SpecialFolder\]::ProgramFiles\)"
        $installScript | Should -Not -Match "Join-Path \`$env:ProgramFiles"
    }
}

Describe "v2.17: volume roots are protected" -Tag "Fix", "V217" {

    It "Test-PathProtected refuses a drive root" {
        # TEMP set to "C:\", or an empty variable resolving to a root, would otherwise
        # hand the whole drive to the cleanup routine
        Test-PathProtected -Path 'C:\' | Should -BeTrue
    }

    It "Test-PathProtected refuses an empty path" {
        Test-PathProtected -Path '' | Should -BeTrue
    }

    It "Test-PathProtected expands short (8.3) names" {
        Test-PathProtected -Path 'C:\PROGRA~1' | Should -BeTrue
    }

    It "Test-PathProtected resolves relative traversal" {
        Test-PathProtected -Path 'C:\Windows\..\Windows' | Should -BeTrue
    }

    It "Test-PathProtected still allows a normal cleanup target" {
        Test-PathProtected -Path (Join-Path $env:SystemRoot 'Temp') | Should -BeFalse
    }
}

#endregion
