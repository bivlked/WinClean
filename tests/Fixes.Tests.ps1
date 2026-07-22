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
    Fix (original, v2.13): added -File to Get-ChildItem
    Fix (v2.17, p.2 of the audit): Get-ChildItem itself replaced with
    [System.IO.Directory]::EnumerateFiles - a raw .NET walk, no per-file PSObject. The
    directories-are-excluded guarantee is now structural (EnumerateFiles can only ever
    return files), not a filter flag, so this checks the real behavior directly instead
    of grepping for a flag that no longer exists in this function.
    #>

    It "Counts only file bytes, ignoring directory entries" {
        $testFolder = Join-Path $env:TEMP "PesterTest_FileFlag_$(Get-Random)"
        New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
        New-Item -ItemType Directory -Path "$testFolder\SubDir" -Force | Out-Null
        [System.IO.File]::WriteAllText("$testFolder\file.txt", ('x' * 1000))

        try {
            # If directory entries were counted (e.g. via a Length that resolves to
            # something non-zero for a container), this would overcount past 1000
            Get-FolderSize -Path $testFolder | Should -Be 1000
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
    <#
    v2.20: these used to be the regex '2\.1[3-9]', which stopped matching the moment the
    version crossed 2.19 - the tests failed on the version bump itself rather than on any
    defect. Compare versions as versions, and check the invariant that actually matters:
    the two places agree with each other.
    #>
    BeforeAll {
        $script:declaredVersion = if ($scriptContent -match '(?m)^\$script:Version\s*=\s*"([\d.]+)"') { $Matches[1] } else { $null }
        $script:scriptInfoVersion = if ($scriptContent -match '(?m)^\.VERSION\s+([\d.]+)\s*$') { $Matches[1] } else { $null }
    }

    It "Declares a parseable version" {
        $script:declaredVersion | Should -Not -BeNullOrEmpty
        { [version]$script:declaredVersion } | Should -Not -Throw
    }

    It "Is 2.13 or higher" {
        [version]$script:declaredVersion | Should -BeGreaterOrEqual ([version]'2.13')
    }

    It "PSScriptInfo carries the same version as `$script:Version" {
        # PSGallery publishes from PSScriptInfo while the banner and the update check read
        # $script:Version - a mismatch ships a package that lies about its own version
        $script:scriptInfoVersion | Should -Be $script:declaredVersion
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
        $scriptContent | Should -Match '(?s)if \(\$item\.PSIsContainer\).*?Get-ChildItem -LiteralPath \$item\.FullName -Recurse'
    }

    It "ReportOnly measures the same candidates the real run would delete" {
        # v2.17: eligibility and size are decided in one shared enumeration pass, used
        # by both branches - $candidates - instead of a separate scriptblock re-run for
        # each. Otherwise the report could promise more than the run actually deletes.
        $body = Get-FunctionBody -Name 'Remove-FolderContent'
        $body | Should -Match '\$candidates \+= \[pscustomobject\]'
        $body | Should -Match 'if \(\$ReportOnly\)'
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

    It "Exceeding the wait is reported as a warning (changed in v2.20)" {
        # v2.16 logged this at INFO because killing cleanmgr was worse than waiting, and
        # that part still holds. But the consequence was never stated: everything measured
        # after this point is partial, and the run prints its total and writes its JSON
        # while an elevated process is still deleting. Silence made a partial result look
        # like a final one.
        $body = Get-FunctionBody -Name 'Invoke-StorageSense'
        $body | Should -Match 'still running - it continues in the background'
        $body | Should -Match '\$script:Stats\.DiskCleanupPending = \$true'
    }

    It "cleanmgr is not killed on timeout" {
        # Killing it mid-delete achieved nothing and contradicted the log message
        $scriptContent | Should -Not -Match '\$cleanmgr \| Stop-Process'
    }

    It "Registry configuration is not pulled from under a still-running cleanmgr (v2.20)" {
        # The finally block swept StateFlags immediately after deciding to let cleanmgr
        # keep working, which removed the configuration it was running on
        $body = Get-FunctionBody -Name 'Invoke-StorageSense'
        $body | Should -Match 'if \(\$cleanmgr -and -not \$cleanmgr\.HasExited\)'
    }
}

#endregion

#region v2.16 Features

Describe "v2.16: driver store cleanup" -Tag "Feature", "V216" {
    It "Enumerates driver packages as XML" {
        # Plain text output of pnputil switches language with the console code page
        $scriptContent | Should -Match "'/enum-drivers', '/devices', '/format', 'xml'"
    }

    It "Only removes packages with no bound device AND a strictly newer sibling (v2.18)" {
        # Behavioral coverage lives in the Get-SupersededDriverCandidate tests; this pins
        # the guard text so a regression to an Oem/date comparison (which deleted a same-
        # version package with an older date) is also caught here.
        $scriptContent | Should -Match '\$pkg\.InUse -or \$pkg\.Version -ge \$newest\.Version'
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
        # v2.18: repo delta is authoritative whenever ANY removed package lacks a trusted
        # size, not only when the total is zero (the old wording was "unavailable").
        $scriptContent | Should -Match 'per-package size incomplete'
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
        # v2.17: the baseline for this message is $totalSize (sum of what was actually
        # eligible), not a Get-FolderSize of the whole path - see Remove-FolderContent
        $scriptContent | Should -Match 'nothing freed, \$\(Format-FileSize \$totalSize\) still present'
    }

    It "The age filter fails closed when a subtree cannot be read" {
        # Failing open would silently defeat the protection the filter exists for.
        # v2.17: no longer a Where-Object predicate returning $false - a plain foreach
        # skipping the candidate with `continue` - but the fail-closed guard is the same
        $body = Get-FunctionBody -Name 'Remove-FolderContent'
        $body | Should -Match 'if \(\$walkErrors\) \{ continue \}'
    }

    It "ReportOnly measures the same set the real run deletes" {
        $scriptContent | Should -Not -Match '\$size = Get-FolderSize -Path \$Path'
    }

    It "winget source timeout counts as a warning" {
        $scriptContent | Should -Match '(?s)Winget source update timed out[^\r\n]*\r?\n\s*\$script:Stats\.WarningsCount\+\+'
    }

    It "Result JSON write failure counts as an error, not a warning (v2.20)" {
        # An automated stand would otherwise read the previous run's file as fresh.
        # Changed deliberately in v2.20: the exit code is decided by ErrorsCount alone,
        # so as a warning this failure still exited 0 - the run reported success while
        # the artefact the user explicitly requested was missing.
        $scriptContent | Should -Match '(?s)Failed to write result JSON[^\r\n]*\r?\n\s*\$script:Stats\.ErrorsCount\+\+'
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

Describe "v2.18: bootstrap host allowlist is exact, not a broad suffix" -Tag "Fix", "V218" -ForEach @(
    @{ Name = 'get.ps1' }, @{ Name = 'install.ps1' }
) {
    <#
    #7 of the external review. The old suffix match accepted any *.github.com /
    *.githubusercontent.com subdomain; a release browser_download_url is always github.com.
    Exercise the real function (extracted so the bootstrap body does not run) to prove the
    allowlist is now exact.
    #>
    BeforeAll {
        $src = Get-Content (Join-Path $PSScriptRoot '..' $Name) -Raw
        if ($src -notmatch '(?ms)^(function Assert-GitHubUri \{.*?\n\})') {
            throw "Assert-GitHubUri not found in $Name"
        }
        # Dot-sourcing a scriptblock defines the function in this scope exactly as
        # Invoke-Expression would, without tripping PSAvoidUsingInvokeExpression
        # (which CI lints as a Warning and therefore fails on).
        . ([scriptblock]::Create($Matches[1]))
    }

    It "Accepts a real release asset URL on github.com" {
        Assert-GitHubUri 'https://github.com/bivlked/WinClean/releases/download/v2.18/WinClean.ps1' |
            Should -Be 'https://github.com/bivlked/WinClean/releases/download/v2.18/WinClean.ps1'
    }

    It "Rejects <Url>" -ForEach @(
        @{ Url = 'https://evil.com/x' }                       # unrelated host
        @{ Url = 'https://github.com.evil.com/x' }            # look-alike suffix
        @{ Url = 'https://objects.githubusercontent.com/x' }  # CDN subdomain, now refused
        @{ Url = 'http://github.com/x' }                      # wrong scheme
    ) {
        { Assert-GitHubUri $Url } | Should -Throw
    }
}

Describe "v2.18: silent-failure and honesty fixes" -Tag "Fix", "V218" {
    BeforeAll {
        $scriptContent = Get-Content (Join-Path $PSScriptRoot '..' 'WinClean.ps1') -Raw
    }

    It "Clear-DockerWSL bumps WarningsCount when a single VHDX fails to compact (#2)" {
        # Body-scoped: the per-VHDX catch must increment the counter, not just log, or the
        # stand/CI reads WarningsCount=0 on a real failure.
        $body = Get-FunctionBody -Name 'Clear-DockerWSL'
        $body | Should -Match '(?s)Could not compact.{0,160}WarningsCount\+\+'
    }

    It "Clear-BrowserCaches ReportOnly distinguishes empty from a real cleanup (#5)" {
        $body = Get-FunctionBody -Name 'Clear-BrowserCaches'
        $body | Should -Match 'but they are empty'
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

#region v2.19: -SkipCleanup contract + phase dispatch wiring

Describe "v2.19: -SkipCleanup suppresses the whole cleanup group" -Tag "Fix", "V219", "SkipCleanup" {

    BeforeAll {
        $body = Get-FunctionBody -Name 'Start-WinClean'
    }

    It "System, deep and disk-report phases are gated on -SkipCleanup" {
        $body | Should -Match "Invoke-Phase -Name 'SystemCleanup' -Skip:\`$SkipCleanup"
        $body | Should -Match "Invoke-Phase -Name 'DeepSystemCleanup' -Skip:\`$SkipCleanup"
        $body | Should -Match "Invoke-Phase -Name 'DiskSpaceReport' -Skip:\`$SkipCleanup"
    }

    It "Developer/Docker/VS phases are ALSO gated on -SkipCleanup, not only their own flag" {
        # This is the bug the external review found: before v2.19 these three ran even
        # with -SkipCleanup, contradicting the documented 'skip all cleanup' contract.
        $body | Should -Match "Invoke-Phase -Name 'DeveloperCleanup' -Skip:\(\`$SkipCleanup -or \`$SkipDevCleanup\)"
        $body | Should -Match "Invoke-Phase -Name 'DockerWSLCleanup' -Skip:\(\`$SkipCleanup -or \`$SkipDockerCleanup\)"
        $body | Should -Match "Invoke-Phase -Name 'VisualStudioCleanup' -Skip:\(\`$SkipCleanup -or \`$SkipVSCleanup\)"
    }

    It "Preparation and Updates carry their own skip flags" {
        $body | Should -Match "Invoke-Phase -Name 'Preparation' -Skip:\`$SkipRestore"
        $body | Should -Match "Invoke-Phase -Name 'Updates' -Skip:\`$SkipUpdates"
    }

    It "TotalSteps nests dev/docker/vs increments under -not SkipCleanup" {
        # The progress denominator must follow the same suppression, or a -SkipCleanup
        # run counts progress against phases that will never run.
        $body | Should -Match '(?s)if \(-not \$SkipCleanup\) \{\s*\$script:Stats\.TotalSteps \+= 2.*?SkipDevCleanup.*?SkipDockerCleanup.*?SkipVSCleanup.*?\}'
    }
}

#endregion

#region v2.19: app updates reported as offered, not installed (296v.1)

Describe "v2.19: app updates are reported as offered, not installed" -Tag "Fix", "V219", "AppUpdates" {

    It "Update-Applications records the offered count from the parsed table" {
        $body = Get-FunctionBody -Name 'Update-Applications'
        $body | Should -Match '\$script:Stats\.AppUpdatesOffered = \$updateCount'
        # The old name must be gone from the live code - it claimed 'installed' falsely
        $body | Should -Not -Match '\$script:Stats\.AppUpdatesCount'
    }

    It "Result JSON exposes AppUpdatesOffered, not AppUpdatesCount" {
        $body = Get-FunctionBody -Name 'Write-ResultJson'
        $body | Should -Match 'AppUpdatesOffered\s+=\s+\$script:Stats\.AppUpdatesOffered'
        $body | Should -Not -Match 'AppUpdatesCount\s+=\s+\$script:Stats\.AppUpdatesCount'
    }

    It "Final statistics label the app number as offered and drop the 'installed' claim" {
        # The rendering lives in Show-FinalStatisticsBody; Show-FinalStatistics only wraps it
        $body = Get-FunctionBody -Name 'Show-FinalStatisticsBody'
        $body | Should -Match '\$script:Stats\.AppUpdatesOffered'
        $body | Should -Match 'Apps: \$appsOffered offered'
        # Apps were never confirmed installed; the updates line must not be labelled so
        $body | Should -Not -Match '-Label "Updates installed:"'
    }
}

#endregion

#region v2.19: get.ps1 parameter allowlist matches WinClean (F4)

Describe "v2.19: get.ps1 forwards exactly WinClean's parameter set" -Tag "Fix", "V219", "Bootstrap" {
    # The reviewer confirmed the lists match today; this is the guard that keeps them in
    # sync. A new WinClean parameter that get.ps1 does not know would be silently dropped
    # from the one-line install, so drift must fail the build, not surprise a user.

    BeforeAll {
        function Get-NamedArrayLiteral {
            param($Ast, [string]$VarName)
            $assign = $Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Left.VariablePath.UserPath -eq $VarName
            }, $true) | Select-Object -First 1
            if (-not $assign) { throw "Assignment '`$$VarName' not found" }
            $strings = $assign.Right.FindAll({
                param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)
            return @($strings | ForEach-Object { $_.Value } | Sort-Object)
        }

        # WinClean's real parameters, split by static type
        $wcAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $wcParams = $wcAst.ParamBlock.Parameters
        $script:wcSwitch = @($wcParams | Where-Object { $_.StaticType -eq [switch] } |
                             ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object)
        $script:wcValue  = @($wcParams | Where-Object { $_.StaticType -eq [string] } |
                             ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object)

        # get.ps1's declared allowlist, read via AST (dot-sourcing it would try to run it)
        $getPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'get.ps1')).Path
        $getAst = [System.Management.Automation.Language.Parser]::ParseFile($getPath, [ref]$null, [ref]$null)
        $script:getSwitch = Get-NamedArrayLiteral -Ast $getAst -VarName 'switchParams'
        $script:getValue  = Get-NamedArrayLiteral -Ast $getAst -VarName 'valueParams'
    }

    It "switch parameters match exactly" {
        ($script:getSwitch -join ',') | Should -Be ($script:wcSwitch -join ',')
    }

    It "value parameters match exactly" {
        ($script:getValue -join ',') | Should -Be ($script:wcValue -join ',')
    }

    It "every WinClean parameter is reachable through get.ps1" {
        $allWc  = @($script:wcSwitch + $script:wcValue | Sort-Object)
        $allGet = @($script:getSwitch + $script:getValue | Sort-Object)
        ($allGet -join ',') | Should -Be ($allWc -join ',')
    }
}

#endregion

#region V220: silent failures that reported success

Describe "v2.20: an operation that did nothing does not report success" -Tag "Fix", "V220" {

    Context "Event log enumeration failure" {
        <#
        Behavioural, not a grep: Get-WinEvent is mocked to fail the way a stopped Event Log
        service fails. The old code then had an empty list, zero failed clears, and took the
        success branch - "Event logs cleared (0 logs)" while nothing was touched. Nothing is
        actually cleared here either, because the loop never has a channel to run on.
        #>
        It "Warns instead of claiming success when no channel can be listed" {
            Mock Get-WinEvent {
                Write-Error 'The Event Log service is unavailable' -ErrorAction SilentlyContinue
                @()
            }

            # Prove the mock is in effect BEFORE the product is allowed to touch anything.
            # If it ever stopped intercepting (a Pester upgrade, a scoping change, the
            # product switching to another API), the real enumeration would return the real
            # channels and this test would clear the developer's own event logs for real -
            # and only fail afterwards (raised in review).
            @(Get-WinEvent -ListLog *).Count | Should -Be 0 -Because 'the mock must intercept before Clear-EventLogs runs'

            $warningsBefore = $script:Stats.WarningsCount
            Clear-EventLogs
            $script:Stats.WarningsCount | Should -BeGreaterThan $warningsBefore
        }
    }

    Context "npm exit code" {
        # npm fails without throwing (EPERM on a locked cache), so the native exit code is
        # the only signal. Scoped to the function body: a match anywhere in the file would
        # stay green if this handling were deleted.
        It "Captures the npm exit code and uses it" {
            $body = Get-FunctionBody -Name 'Clear-DeveloperCaches'
            $body | Should -Match '\$npmExit\s*=\s*\$LASTEXITCODE'
            $body | Should -Match '\$npmExit\s*-ne\s*0'
        }

        It "No longer reports a bare success when nothing was freed" {
            $body = Get-FunctionBody -Name 'Clear-DeveloperCaches'
            $body | Should -Not -Match 'npm cache cleaned \(via npm\)'
        }
    }

    Context "winget source update exit code" {
        It "Reads the source-update exit code, not just job completion" {
            $body = Get-FunctionBody -Name 'Update-Applications'
            $body | Should -Match 'Winget source update failed'
        }
    }

    Context "Per-run state" {
        It "Start-WinClean builds a fresh stats object instead of patching three fields" {
            $body = Get-FunctionBody -Name 'Start-WinClean'
            $body | Should -Match '\$script:Stats\s*=\s*New-RunStats'
            $body | Should -Match '\$script:InternetConnectionCache\s*=\s*\$null'
        }
    }

    Context "Logging failure is visible" {
        It "Latches the first log write failure instead of swallowing every one" {
            $body = Get-FunctionBody -Name 'Write-Log'
            $body | Should -Match '\$script:LogWriteFailed'
            # Write-Log must not report its own failure through Write-Log
            $body | Should -Match 'Write-Host'
        }

        It "Surfaces it in the result JSON so a consumer knows the log is incomplete" {
            $body = Get-FunctionBody -Name 'Write-ResultJson'
            $body | Should -Match 'LoggingDegraded'
        }
    }

    Context "Privacy traces are confirmed, not assumed" {
        It "Compares the value count before and after instead of appending unconditionally" {
            $body = Get-FunctionBody -Name 'Clear-PrivacyTraces'
            $body | Should -Match 'Get-RegistryValueCount'
            # The old shape: success text appended right after a SilentlyContinue delete
            $body | Should -Match '\$after\s*-eq\s*0'
        }
    }
}

#endregion

#region V220R: findings from the pre-release review of v2.20

Describe "v2.20 review: measurements and failures answer honestly" -Tag "Fix", "V220R" {
    <#
    These cover the defects an independent review found in the v2.20 fixes themselves.
    Behavioural coverage for the Storage Sense decisions lives in Helpers.Tests.ps1
    (Select-StorageSenseTask / Get-StorageSenseVerdict / Wait-StorageSenseTask); what is
    left here is code that cannot be reached without a real scheduler, browser or winget.
    #>

    Context "Browser caches: both sides of the subtraction describe the same files" {
        It "Does not measure 'before' with the raw walker and 'after' with the checked one" {
            $body = Get-FunctionBody -Name 'Clear-BrowserCaches'
            # Get-FolderSize skips inaccessible files silently; Get-FolderSizeChecked
            # refuses to answer at all. Mixing them subtracted two different file sets.
            $body | Should -Not -Match 'sizeBefore\s*=.*Get-FolderSize\s'
        }

        It "Pairs the measurements per path instead of discarding the whole delta" {
            $body = Get-FunctionBody -Name 'Clear-BrowserCaches'
            $body | Should -Match '\$beforeMeasurements'
            $body | Should -Match '\$afterUnmeasured\+\+'
        }
    }

    Context "npm cache: an unreadable cache is not an emptied one" {
        It "Measures both sides with the checked variant" {
            $body = Get-FunctionBody -Name 'Clear-DeveloperCaches'
            $body | Should -Match '\$sizeBefore = Get-FolderSizeChecked'
            $body | Should -Match '\$sizeAfter = Get-FolderSizeChecked'
        }

        It "Says so instead of calling it empty when the size is unknown" {
            $body = Get-FunctionBody -Name 'Clear-DeveloperCaches'
            $body | Should -Match '\$npmMeasured'
        }
    }

    Context "Event logs: a partial enumeration failure is not a success" {
        It "Decides on the unfiltered channel list" {
            $body = Get-FunctionBody -Name 'Clear-EventLogs'
            $body | Should -Match '\$allLogs\.Count -eq 0'
            # The old discriminator read the FILTERED list, so 40 readable channels out of
            # 510 with 470 errors produced a plain success line
            $body | Should -Not -Match 'if \(-not \$logs -and \$enumErrors\)'
        }

        It "Reports channels that could not be listed separately from clearing failures" {
            $body = Get-FunctionBody -Name 'Clear-EventLogs'
            $body | Should -Match '\$enumErrorCount'
        }
    }

    Context "winget: an unusable executable is reported, not passed over" {
        It "Treats a missing exit code as a failure rather than short-circuiting on null" {
            $body = Get-FunctionBody -Name 'Update-Applications'
            $body | Should -Match '\[int\]::TryParse'
            $body | Should -Match '\$jobState'
            # The old guard: a null exit code silently satisfied it
            $body | Should -Not -Match '0 -ne \[int\]\$sourceExit'
        }
    }

    Context "Restore point: the killed child is gone before the registry is judged" {
        It "Waits for the process to actually exit after Kill" {
            $body = Get-FunctionBody -Name 'New-SystemRestorePoint'
            # Ordering, not proximity: a distance-bounded regex would break the next time
            # the comment between the two lines grows.
            $killAt = $body.IndexOf('Kill($true)')
            $waitAt = $body.IndexOf('WaitForExit(5000)')
            $killAt | Should -BeGreaterOrEqual 0
            $waitAt | Should -BeGreaterThan $killAt
        }
    }

    Context "Storage Sense: the task is pinned and the decisions are delegated" {
        It "Looks the task up by name alone exactly once - the initial discovery" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $byNameOnly = [regex]::Matches($body, 'Get-ScheduledTask -TaskName \$ssTaskName').Count
            $byNameOnly | Should -Be 1
            # Every later lookup goes through the pinned parameter set
            [regex]::Matches($body, 'Get-ScheduledTask @ssLookup').Count | Should -BeGreaterThan 1
        }

        It "Never passes a null TaskPath, which throws a binding error -ErrorAction cannot suppress" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $body | Should -Match "if \(\`$ssTaskPath\) \{ \`$ssLookup\['TaskPath'\] = \`$ssTaskPath \}"
        }

        It "Uses the helpers that carry the tested rules" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $body | Should -Match 'Select-StorageSenseTask'
            $body | Should -Match 'Get-StorageSenseVerdict'
            $body | Should -Match 'Wait-StorageSenseTask'
        }

        It "Distinguishes a task that disappeared from one that ran out of time" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $body | Should -Match "'vanished'"
        }
    }

    Context "A test file that fails to load cannot slip past green" {
        It "Invoke-Tests fails the run on a container that never produced tests" {
            # Measured on Pester 5.7.1: a parse error gives Result=Failed and
            # FailedContainersCount=1 while Failed/Skipped/NotRun are all 0
            $text = Get-Content (Join-Path $PSScriptRoot '..' 'tools' 'Invoke-Tests.ps1') -Raw
            $text | Should -Match 'FailedContainersCount'
            $text | Should -Match '\$failedContainers -gt 0'
        }

        It "The release gate applies the same rule as CI" {
            $text = Get-Content (Join-Path $PSScriptRoot '..' 'tools' 'Invoke-ReleaseCheck.ps1') -Raw
            $text | Should -Match 'FailedContainersCount'
        }
    }
}

#endregion

#region V220R2: second review round, before release

Describe "v2.20 pre-release review: fixes to the fixes" -Tag "Fix", "V220R2" {
    <#
    Five reviewers (four specialised agents plus a cross-engine pass) went over this
    release. The behavioural coverage for what they found lives in Helpers.Tests.ps1;
    what remains here is code that needs a scheduler, a missing cleanmgr.exe or a
    registry hive to reach.
    #>

    Context "Storage Sense: a step that did not happen cannot look like one that did" {
        It "Refuses to wait on a process that never started" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            # Measured: Start-Process on a missing exe leaves $null, and $null.HasExited is
            # $null, so '-not $cleanmgr.HasExited' is TRUE - the loop reported progress for
            # the full fifteen minutes and then set DiskCleanupPending for a process that
            # did not exist.
            $body | Should -Match 'if \(-not \$cleanmgr\) \{'
            $startAt = $body.IndexOf('Start-Process -FilePath "cleanmgr.exe"')
            $guardAt = $body.IndexOf('if (-not $cleanmgr) {')
            $startAt | Should -BeGreaterOrEqual 0
            $guardAt | Should -BeGreaterThan $startAt
        }

        It "Claims the task stopped only after checking that it stopped" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $body | Should -Match '\$taskAfterStop'
            # The unconditional claim must be gone: the success line has to sit in an else
            $body | Should -Match 'Stop-ScheduledTask[\s\S]{0,400}?\$taskAfterStop'
        }

        It "Counts a two-minute timeout as a warning again" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $body | Should -Match 'did not finish within \$timeout seconds[^\n]*-Level WARNING'
        }

        It "Does not contradict itself about whether the task was found" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            # An ambiguous lookup used to log "2 tasks with that name" and then, two lines
            # later, "task not found"
            $body | Should -Match '\$ssExplained'
            $body | Should -Match 'if \(-not \$ssExplained\)'
        }

        It "Sweeps the registry leftovers before honouring -SkipDiskCleanup" {
            $body = Get-FunctionBody -Name 'Invoke-StorageSense'
            $sweepAt = $body.IndexOf('Remove-ItemProperty -Path $_.PSPath')
            $skipAt = $body.IndexOf('if ($SkipDiskCleanup) {')
            $sweepAt | Should -BeGreaterOrEqual 0
            $skipAt | Should -BeGreaterThan $sweepAt
        }

        It "Does not measure free space around a step the user switched off" {
            $body = Get-FunctionBody -Name 'Start-WinClean'
            # Bracketing a no-op with two drive reads credited DiskCleanup with whatever
            # the drive gained meanwhile
            $body | Should -Match 'if \(\$SkipDiskCleanup\) \{\s*\r?\n\s*Invoke-StorageSense'
        }
    }

    Context "Link resolution fails closed on every unknown" {
        It "Returns null when the resolution bound is exhausted" {
            $body = Get-FunctionBody -Name 'Resolve-PathThroughLinks'
            # Falling out of the bounded loop means "could not resolve", and the caller
            # only fails closed on $null
            $body | Should -Match 'if \(-not \$changed\) \{ return \$current \}'
            $body.TrimEnd() | Should -Match 'return \$null\s*\}$'
        }

        It "Returns null when an ancestor cannot be examined" {
            $body = Get-FunctionBody -Name 'Resolve-PathThroughLinks'
            $body | Should -Match 'catch \{ return \$null \}'
        }
    }

    Context "The release note exists in exactly one place" {
        It "Appears exactly once inside PSScriptInfo, and its text is not duplicated outside" {
            # A version bump pasted the whole v2.20 release-note sentence into
            # Invoke-Phase's comment-based help, and that stray copy satisfied the release
            # gate's .RELEASENOTES check on its own.
            # Note the count is taken INSIDE the block: "vX.Y:" also opens legitimate prose
            # in other help blocks, so a whole-file count would forbid ordinary comments.
            $version = if ($scriptContent -match '(?m)^\$script:Version\s*=\s*"([\d.]+)"') { $Matches[1] } else { $null }
            $version | Should -Not -BeNullOrEmpty

            $psScriptInfo = if ($scriptContent -match '(?s)<#PSScriptInfo(.*?)#>') { $Matches[1] } else { '' }
            $psScriptInfo | Should -Not -BeNullOrEmpty
            ([regex]::Matches($psScriptInfo, "(?m)^\s*v$([regex]::Escape($version)):")).Count | Should -Be 1

            # And the sentence itself belongs to that one place only
            $noteLine = ([regex]::Match($psScriptInfo, "(?m)^\s*v$([regex]::Escape($version)):.*$")).Value.Trim()
            $noteLine.Length | Should -BeGreaterThan 40
            ([regex]::Matches($scriptContent, [regex]::Escape($noteLine))).Count | Should -Be 1
        }

        It "The gate looks for it only inside the .RELEASENOTES section" {
            # Scoping to the whole PSScriptInfo block was still too wide: a "vX.Y:" line
            # under any other field satisfied it while .RELEASENOTES was empty
            $gate = Get-Content (Join-Path $PSScriptRoot '..' 'tools' 'Invoke-ReleaseCheck.ps1') -Raw
            $gate | Should -Match '\$releaseNotes'
            $gate | Should -Match "What = '\.RELEASENOTES first line'; Ok = \`$releaseNotes"
            $gate | Should -Not -Match "What = '\.RELEASENOTES first line'; Ok = \`$scriptText"
        }

        It "Resolve-PathThroughLinks stops the ancestor walk at the volume root" {
            # The walk climbed past the root of a UNC share, Get-Item on \\server failed,
            # and the fail-closed rule then refused every UNC cleanup root
            $body = Get-FunctionBody -Name 'Resolve-PathThroughLinks'
            $body | Should -Match 'GetPathRoot'
            $body | Should -Match '\$parent\.Length -lt \$rootPath\.Length'
        }
    }
}

#endregion
