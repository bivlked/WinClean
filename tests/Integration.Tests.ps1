#Requires -Modules Pester

<#
.SYNOPSIS
    Level 1 integration tests: real WinClean functions against a sandboxed filesystem
.DESCRIPTION
    Each Describe block scaffolds a fake directory tree, then launches a child pwsh
    process that redirects TEMP/LOCALAPPDATA/APPDATA/USERPROFILE/SystemRoot/... into
    the scaffold, dot-sources WinClean.ps1 and executes REAL cleanup functions
    (ReportOnly = off). Assertions inspect what actually got deleted or kept.

    Safety: the child process only ever sees paths inside the scaffold; PATH is
    stripped after dot-sourcing so external tools (npm, docker, wsl) are not found.
    Requires Administrator (WinClean.ps1 has #Requires -RunAsAdministrator);
    GitHub Actions Windows runners are elevated, so this runs in CI too.
.NOTES
    Version: 2.15
    Requires: Pester 5.0+, pwsh 7.1+, Administrator
#>

BeforeDiscovery {
    $script:IsElevated = ([Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    $script:WinCleanPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'WinClean.ps1')).Path
    $script:SandboxRoots = [System.Collections.Generic.List[string]]::new()

    function New-Sandbox {
        <# Creates a scaffold tree and returns its root path #>
        $root = Join-Path ([System.IO.Path]::GetTempPath()) "WinCleanIT_$(Get-Random)"

        $dirs = @(
            'Windows\Temp'
            'Users\test\AppData\Local\Temp\junkdir'
            'Users\test\AppData\Roaming'
            'ProgramData'
            'Program Files'
            'Program Files (x86)'
            'Users\test\AppData\Local\Google\Chrome\User Data\Default\Cache'
            'Users\test\AppData\Local\Google\Chrome\User Data\Default\Code Cache'
            'Users\test\AppData\Local\Google\Chrome\User Data\Profile 1\Cache'
            'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default\cache2'
            'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default\startupCache'
            'Users\test\AppData\Local\npm-cache'
            'Users\test\AppData\Roaming\npm-cache'
            'Users\test\AppData\Local\uv\cache'
            'Users\test\AppData\Local\pip\Cache'
        )
        foreach ($d in $dirs) {
            New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null
        }

        $files = @{
            'Windows\protected-marker.txt'                                                       = 'must survive'
            'Windows\Temp\wjunk.txt'                                                             = 'x' * 2048
            'Users\test\AppData\Local\Temp\junk1.txt'                                            = 'x' * 4096
            'Users\test\AppData\Local\Temp\junkdir\junk2.txt'                                    = 'x' * 4096
            'Users\test\AppData\Local\Google\Chrome\User Data\Default\Cache\c1.bin'              = 'x' * 8192
            'Users\test\AppData\Local\Google\Chrome\User Data\Default\Code Cache\cc.bin'         = 'x' * 8192
            'Users\test\AppData\Local\Google\Chrome\User Data\Default\Bookmarks'                 = '{"roots":{}}'
            'Users\test\AppData\Local\Google\Chrome\User Data\Profile 1\Cache\p1.bin'            = 'x' * 8192
            'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default\cache2\e1.bin'        = 'x' * 8192
            'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default\startupCache\s1.bin'  = 'x' * 4096
            'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default\places.sqlite'        = 'not a cache'
            'Users\test\AppData\Local\npm-cache\pkg.tgz'                                         = 'x' * 8192
            'Users\test\AppData\Roaming\npm-cache\legacy.tgz'                                    = 'x' * 8192
            'Users\test\AppData\Local\uv\cache\wheel.whl'                                        = 'x' * 8192
            'Users\test\AppData\Local\pip\Cache\pip.whl'                                         = 'x' * 4096
        }
        foreach ($f in $files.Keys) {
            [System.IO.File]::WriteAllText((Join-Path $root $f), $files[$f])
        }

        # v2.16: Clear-TempFiles skips entries younger than a day, so temp junk has to be
        # aged for the cleanup tests to be meaningful. Files first, then the directory -
        # writing a file bumps its parent's LastWriteTime.
        $old = (Get-Date).AddDays(-3)
        foreach ($rel in @(
            'Users\test\AppData\Local\Temp\junk1.txt'
            'Users\test\AppData\Local\Temp\junkdir\junk2.txt'
            'Users\test\AppData\Local\Temp\junkdir'
            'Windows\Temp\wjunk.txt'
        )) {
            $item = Get-Item -LiteralPath (Join-Path $root $rel) -Force
            $item.LastWriteTime = $old
        }

        # Freshly written file: must survive the age filter
        [System.IO.File]::WriteAllText((Join-Path $root 'Users\test\AppData\Local\Temp\fresh.txt'), 'x' * 1024)

        $script:SandboxRoots.Add($root)
        return $root
    }

    function Invoke-Sandbox {
        <# Runs $Body inside a child pwsh with the environment redirected into $Root #>
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$Body
        )

        $driver = @'
$ErrorActionPreference = 'Continue'
$root = '{{ROOT}}'
$env:TEMP = Join-Path $root 'Users\test\AppData\Local\Temp'
$env:TMP = $env:TEMP
$env:LOCALAPPDATA = Join-Path $root 'Users\test\AppData\Local'
$env:APPDATA = Join-Path $root 'Users\test\AppData\Roaming'
$env:USERPROFILE = Join-Path $root 'Users\test'
$env:ProgramData = Join-Path $root 'ProgramData'
$env:SystemRoot = Join-Path $root 'Windows'
$env:SystemDrive = $root.TrimEnd('\')
$env:ProgramFiles = Join-Path $root 'Program Files'
${env:ProgramFiles(x86)} = Join-Path $root 'Program Files (x86)'

. '{{SCRIPT}}'

# Strip PATH so Get-Command does not find npm/docker/wsl and friends
$env:Path = $env:SystemRoot

{{BODY}}

@{
    TotalFreedBytes = $script:Stats.TotalFreedBytes
    FreedByCategory = @{} + $script:Stats.FreedByCategory
    WarningsCount   = $script:Stats.WarningsCount
    ErrorsCount     = $script:Stats.ErrorsCount
    LogPath         = $script:LogPath
} | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $root 'stats.json') -Encoding UTF8
'@

        $driver = $driver.Replace('{{ROOT}}', $Root).Replace('{{SCRIPT}}', $script:WinCleanPath).Replace('{{BODY}}', $Body)
        $driverPath = Join-Path $Root 'driver.ps1'
        Set-Content -Path $driverPath -Value $driver -Encoding UTF8

        $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $driverPath 2>&1
        $statsPath = Join-Path $Root 'stats.json'

        [pscustomobject]@{
            Output   = $out
            ExitCode = $LASTEXITCODE
            Stats    = if (Test-Path $statsPath) { Get-Content $statsPath -Raw | ConvertFrom-Json } else { $null }
        }
    }
}

AfterAll {
    foreach ($root in $script:SandboxRoots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Sandbox: Clear-TempFiles" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body @'
Write-Log "MARKER-BEFORE-CLEANUP" -Level INFO
Clear-TempFiles
'@
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
        $result.Stats | Should -Not -BeNullOrEmpty
        $result.Stats.ErrorsCount | Should -Be 0
    }

    It "Removes junk from user temp (including subdirectories)" {
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\junk1.txt') | Should -BeFalse
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\junkdir') | Should -BeFalse
    }

    It "Removes junk from Windows temp" {
        Test-Path (Join-Path $root 'Windows\Temp\wjunk.txt') | Should -BeFalse
    }

    It "Keeps files younger than a day (v2.16 age filter)" {
        # Files of a running installer must not be deleted mid-operation
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\fresh.txt') | Should -BeTrue
    }

    It "Keeps the active log file (v2.14 regression)" {
        $result.Stats.LogPath | Should -Not -BeNullOrEmpty
        Test-Path $result.Stats.LogPath | Should -BeTrue
    }

    It "Log still contains entries written before cleanup (v2.14 regression)" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'MARKER-BEFORE-CLEANUP'
    }

    It "Counts freed space in the Temp category" {
        [long]$result.Stats.FreedByCategory.Temp | Should -BeGreaterThan 0
    }
}

Describe "Sandbox: protected paths are never cleaned" -Tag "Integration", "Security" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body @'
Remove-FolderContent -Path $env:SystemRoot -Category "Test" -Description "should be refused"
Remove-FolderContent -Path $env:USERPROFILE -Category "Test" -Description "should be refused"
'@
    }

    It "SystemRoot content survives" {
        Test-Path (Join-Path $root 'Windows\protected-marker.txt') | Should -BeTrue
    }

    It "Refusal is logged" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Protected path skipped'
    }

    It "Nothing was counted as freed" {
        [long]$result.Stats.TotalFreedBytes | Should -Be 0
    }
}

Describe "Sandbox: Clear-BrowserCaches" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body 'Clear-BrowserCaches'
        $chrome = Join-Path $root 'Users\test\AppData\Local\Google\Chrome\User Data'
        $firefox = Join-Path $root 'Users\test\AppData\Local\Mozilla\Firefox\Profiles\abc.default'
    }

    It "Driver exits cleanly" {
        $result.ExitCode | Should -Be 0
    }

    It "Empties Chrome Default profile caches" {
        (Get-ChildItem (Join-Path $chrome 'Default\Cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
        (Get-ChildItem (Join-Path $chrome 'Default\Code Cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Empties additional Chrome profile caches (v2.1 regression)" {
        (Get-ChildItem (Join-Path $chrome 'Profile 1\Cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Keeps non-cache profile data (Bookmarks)" {
        Test-Path (Join-Path $chrome 'Default\Bookmarks') | Should -BeTrue
    }

    It "Empties Firefox cache2/startupCache under LOCALAPPDATA (v2.14 regression)" {
        (Get-ChildItem (Join-Path $firefox 'cache2') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
        (Get-ChildItem (Join-Path $firefox 'startupCache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Keeps Firefox profile data (places.sqlite)" {
        Test-Path (Join-Path $firefox 'places.sqlite') | Should -BeTrue
    }

    It "Counts freed space in the Browser category" {
        [long]$result.Stats.FreedByCategory.Browser | Should -BeGreaterThan 0
    }
}

Describe "Sandbox: Clear-DeveloperCaches" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body 'Clear-DeveloperCaches'
        $local = Join-Path $root 'Users\test\AppData\Local'
    }

    It "Empties the modern npm cache (LOCALAPPDATA, v2.14 regression)" {
        (Get-ChildItem (Join-Path $local 'npm-cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Empties the legacy npm cache too (APPDATA)" {
        (Get-ChildItem (Join-Path $root 'Users\test\AppData\Roaming\npm-cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Empties the uv cache (v2.14 feature)" {
        (Get-ChildItem (Join-Path $local 'uv\cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Empties the pip cache" {
        (Get-ChildItem (Join-Path $local 'pip\Cache') -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Counts freed space in the Developer category" {
        [long]$result.Stats.FreedByCategory.Developer | Should -BeGreaterThan 0
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
        $result.Stats.ErrorsCount | Should -Be 0
    }
}

Describe "Sandbox: ResultJsonPath" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body @'
Clear-TempFiles
$ResultJsonPath = Join-Path $root 'run-result.json'
Write-ResultJson -Path $ResultJsonPath
'@
        $jsonPath = Join-Path $root 'run-result.json'
    }

    It "Writes the result JSON" {
        Test-Path $jsonPath | Should -BeTrue
    }

    It "JSON is valid and carries the version and stats" {
        $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $json.Version | Should -Match '^\d+\.\d+$'
        [long]$json.TotalFreedBytes | Should -BeGreaterThan 0
        $json.PSObject.Properties.Name | Should -Contain 'ErrorsCount'
        $json.PSObject.Properties.Name | Should -Contain 'FreedByCategory'
    }
}

Describe "Sandbox: temp age filter is recursive" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $tempRoot = Join-Path $root 'Users\test\AppData\Local\Temp'
        $old = (Get-Date).AddDays(-10)

        # Old-looking directory holding a freshly written file deeper inside.
        # A parent's LastWriteTime does not move when a grandchild changes, so a
        # non-recursive age check would delete the fresh file along with the parent.
        $nested = Join-Path $tempRoot 'oldlooking\inner'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $nested 'fresh-inside.txt'), 'x' * 512)
        (Get-Item (Join-Path $tempRoot 'oldlooking') -Force).LastWriteTime = $old

        # Directory that is old all the way down: must still be removed
        $stale = Join-Path $tempRoot 'fullyold'
        New-Item -ItemType Directory -Path $stale -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $stale 'old.txt'), 'x' * 512)
        (Get-Item (Join-Path $stale 'old.txt') -Force).LastWriteTime = $old
        (Get-Item $stale -Force).LastWriteTime = $old

        # Freshly created EMPTY directory. It has no children at all, so a check that
        # only looks at descendants finds "nothing newer than the cutoff" and concludes
        # the directory is stale. Its own LastWriteTime is what proves otherwise.
        # A running installer's scratch folder looks exactly like this.
        $freshEmpty = Join-Path $tempRoot 'freshempty'
        New-Item -ItemType Directory -Path $freshEmpty -Force | Out-Null

        # Freshly TOUCHED directory whose contents are all old: same trap from the other
        # side - descendants are stale, but the directory itself was just written to
        $freshParent = Join-Path $tempRoot 'freshparent'
        New-Item -ItemType Directory -Path $freshParent -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $freshParent 'old-content.txt'), 'x' * 512)
        (Get-Item (Join-Path $freshParent 'old-content.txt') -Force).LastWriteTime = $old
        (Get-Item $freshParent -Force).LastWriteTime = (Get-Date)

        $result = Invoke-Sandbox -Root $root -Body 'Clear-TempFiles'
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
    }

    It "Keeps a directory that holds a fresh file deeper inside" {
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\oldlooking\inner\fresh-inside.txt') | Should -BeTrue
    }

    It "Still removes a directory that is old all the way down" {
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\fullyold') | Should -BeFalse
    }

    It "Keeps a freshly created EMPTY directory" {
        # Regression guard: an empty directory has no descendants to prove it is fresh,
        # so dropping the directory's own LastWriteTime check deletes it
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\freshempty') | Should -BeTrue
    }

    It "Keeps a freshly touched directory even when its contents are old" {
        Test-Path (Join-Path $root 'Users\test\AppData\Local\Temp\freshparent') | Should -BeTrue
    }
}

Describe "Sandbox: Remove-FolderContent partial-deletion accuracy" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    v2.17 (p.1 of the audit): Remove-FolderContent no longer re-walks the whole $Path to
    measure what got freed - after the delete attempt, a candidate that is fully gone
    contributes its pre-measured size, one that still exists gets re-measured on its own
    (not the whole of $Path). A mutation test proved this specific branch has no other
    coverage: removing it outright left the full suite green. This is the target: a
    directory candidate that partially empties (one locked file inside survives, the
    rest of its contents do not) must report exactly what was freed - not the whole
    directory's size, not zero.
    #>

    BeforeAll {
        $root = New-Sandbox
        $container = Join-Path $root 'Users\test\AppData\Roaming\PartialDelete'
        $subdir = Join-Path $container 'subdir'
        New-Item -ItemType Directory -Path $subdir -Force | Out-Null

        $lockedFile = Join-Path $subdir 'locked.bin'
        $freeFile = Join-Path $subdir 'free.bin'
        [System.IO.File]::WriteAllBytes($lockedFile, [byte[]]::new(4096))
        [System.IO.File]::WriteAllBytes($freeFile, [byte[]]::new(8192))

        # Held from THIS process: Windows enforces sharing violations across processes,
        # so the child sandbox's Remove-Item -Recurse will delete free.bin but fail on
        # locked.bin - and therefore fail to remove 'subdir' itself, which is exactly
        # the "partially deleted directory" case this test targets.
        $lockStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $result = Invoke-Sandbox -Root $root -Body @"
Remove-FolderContent -Path '$container' -Category 'PartialTest' -Description 'partial delete test'
"@
        } finally {
            $lockStream.Dispose()
        }
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
    }

    It "Keeps the locked file and the directory that holds it" {
        Test-Path $lockedFile | Should -BeTrue
        Test-Path $subdir | Should -BeTrue
    }

    It "Removes the file that was not locked" {
        Test-Path $freeFile | Should -BeFalse
    }

    It "Reports exactly the freed file's size - not the whole subdirectory, not zero" {
        [long]$result.Stats.FreedByCategory.PartialTest | Should -Be 8192
    }
}

Describe "Sandbox: Remove-FolderContent unmeasured directory" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    v2.18 (+B): a directory whose size cannot be measured before deletion ($null from
    Get-FolderSizeChecked, no age filter) used to be flattened to Size 0, deleted, and
    booked as 0 freed with no notice - the comment claimed the $null was "carried as such"
    but it was not. Now it is still removed, but reported as unmeasured instead of silently
    understated. Get-FolderSizeChecked is shadowed to force the $null path deterministically.
    #>

    BeforeAll {
        $root = New-Sandbox
        $container = Join-Path $root 'Users\test\AppData\Roaming\Unmeasured'
        $subdir = Join-Path $container 'sub'
        New-Item -ItemType Directory -Path $subdir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $subdir 'x.bin'), [byte[]]::new(4096))

        $result = Invoke-Sandbox -Root $root -Body @"
function Get-FolderSizeChecked { param(`$Path) `$null }
Remove-FolderContent -Path '$container' -Category 'UnmeasuredTest' -Description 'unmeasured test'
"@
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
    }

    It "Still deletes the unmeasurable directory" {
        Test-Path $subdir | Should -BeFalse
    }

    It "Reports it as unmeasured rather than crediting a silent zero" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'could not be measured'
    }

    It "Does not credit bogus freed bytes for it" {
        [long]($result.Stats.FreedByCategory.UnmeasuredTest ?? 0) | Should -Be 0
    }
}

Describe "Sandbox: Remove-FolderContent ReportOnly names unmeasurable items" -Tag "Integration" -Skip:(-not $IsElevated) {
    # v2.18 (+B / Codex second pass): a ReportOnly set that is entirely unmeasurable used
    # to print nothing at all (totalSize 0). It now names the excluded items instead of
    # staying silent, and of course deletes nothing.
    BeforeAll {
        $root = New-Sandbox
        $container = Join-Path $root 'Users\test\AppData\Roaming\UnmeasuredReport'
        New-Item -ItemType Directory -Path (Join-Path $container 'sub') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $container 'sub\y.bin'), [byte[]]::new(2048))

        $result = Invoke-Sandbox -Root $root -Body @"
`$ReportOnly = `$true
function Get-FolderSizeChecked { param(`$Path) `$null }
Remove-FolderContent -Path '$container' -Category 'UnmReport' -Description 'unmeasured report test'
"@
    }

    It "Runs without errors and keeps everything" {
        $result.ExitCode | Should -Be 0
        Test-Path (Join-Path $container 'sub') | Should -BeTrue
    }

    It "Names the unmeasurable items instead of printing nothing" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'not measurable'
    }
}

# v2.17: the audit (MyAI-dtx8, item 22) found 39 functions with zero behavioral tests,
# including 8 that delete files. Everything below closes that gap for the functions
# that can be exercised safely. Four of the eight (Clear-EventLogs, Clear-
# WinCleanRecycleBin's real delete path, Clear-DriverStore's real pnputil call, New-
# SystemRestorePoint's real Checkpoint-Computer call) touch OS state that cannot be
# redirected into the sandbox - the real Event Log service, the real Recycle Bin, the
# real driver store, real System Restore. Those are shadowed with fixtures instead of
# left untested: the decision/reporting logic gets real coverage, the destructive
# external call itself does not run. Full end-to-end coverage of that remaining
# surface needs the Proxmox stand (VM 190/191), consistent with project policy that
# destructive runs never happen on the workstation - not left as a silent gap.

Describe "Sandbox: Remove-FilesByPattern" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $patternDir = Join-Path $root 'Users\test\AppData\Roaming\PatternTest'
        New-Item -ItemType Directory -Path $patternDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $patternDir 'a.roslynobjectin'), 'x' * 4096)
        [System.IO.File]::WriteAllText((Join-Path $patternDir 'keep.txt'), 'must survive')

        $result = Invoke-Sandbox -Root $root -Body @"
Remove-FilesByPattern -Pattern '$patternDir\*.roslynobjectin' -Category 'VS' -Description 'Roslyn Temp'
"@
    }

    It "Removes the matching file" {
        Test-Path (Join-Path $patternDir 'a.roslynobjectin') | Should -BeFalse
    }

    It "Keeps files that do not match the pattern" {
        Test-Path (Join-Path $patternDir 'keep.txt') | Should -BeTrue
    }

    It "Counts freed space in the category" {
        [long]$result.Stats.FreedByCategory.VS | Should -BeGreaterThan 0
    }
}

Describe "Sandbox: Remove-FilesByPattern safety guards (v2.17, p.18)" -Tag "Integration", "Security" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        # Sits directly in a protected root: the pattern would match it, but its
        # containing folder is one of $script:ProtectedPaths
        [System.IO.File]::WriteAllText((Join-Path $root 'Windows\marker.tmp'), 'must survive')

        $ageDir = Join-Path $root 'Users\test\AppData\Roaming\AgeTest'
        New-Item -ItemType Directory -Path $ageDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $ageDir 'old.tmp'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $ageDir 'fresh.tmp'), 'x')
        (Get-Item (Join-Path $ageDir 'old.tmp')).LastWriteTime = (Get-Date).AddDays(-5)

        $result = Invoke-Sandbox -Root $root -Body @"
Remove-FilesByPattern -Pattern '$root\Windows\*.tmp' -Category 'Test' -Description 'protected test'
Remove-FilesByPattern -Pattern '$ageDir\*.tmp' -Category 'Test' -Description 'age test' -MinAgeDays 1
"@
    }

    It "Refuses to delete a file whose folder is a protected root" {
        Test-Path (Join-Path $root 'Windows\marker.tmp') | Should -BeTrue
    }

    It "Removes only the file older than MinAgeDays" {
        Test-Path (Join-Path $ageDir 'old.tmp') | Should -BeFalse
        Test-Path (Join-Path $ageDir 'fresh.tmp') | Should -BeTrue
    }
}

Describe "Sandbox: Clear-WindowsOld" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $windowsOld = Join-Path $root 'Windows.old'
        New-Item -ItemType Directory -Path $windowsOld -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $windowsOld 'old.dat'), 'x' * 4096)
    }

    It "Does nothing when Windows.old is absent" {
        # Clear-WindowsOld returns before its first Write-Log call in this case, so the
        # log file itself is never created - asserting on its content would pass either
        # way (missing file also fails to match) and prove nothing
        $emptyRoot = New-Sandbox
        $result = Invoke-Sandbox -Root $emptyRoot -Body 'Clear-WindowsOld'
        $result.ExitCode | Should -Be 0
        [long]$result.Stats.TotalFreedBytes | Should -Be 0
    }

    It "ReportOnly reports the size without deleting" {
        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
Clear-WindowsOld
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would clean: Windows\.old'
        Test-Path $windowsOld | Should -BeTrue
    }

    It "Skips deletion in non-interactive mode without prompting (safe default)" {
        $result = Invoke-Sandbox -Root $root -Body 'Clear-WindowsOld'
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Non-interactive mode - skipping Windows\.old deletion'
        Test-Path $windowsOld | Should -BeTrue
    }
}

Describe "Sandbox: Clear-SystemCaches" -Tag "Integration" -Skip:(-not $IsElevated) {

    BeforeAll {
        $root = New-Sandbox
        $prefetch = Join-Path $root 'Windows\Prefetch'
        New-Item -ItemType Directory -Path $prefetch -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $prefetch 'app.pf'), 'x' * 4096)

        $iconCache = Join-Path $root 'Users\test\AppData\Local\IconCache.db'
        [System.IO.File]::WriteAllText($iconCache, 'x' * 2048)

        # Delivery Optimization is shadowed with a no-op: Delete-DeliveryOptimizationCache
        # is a real built-in cmdlet (auto-loaded, not something a sandbox can redirect)
        # that operates on real, non-redirectable OS state.
        $result = Invoke-Sandbox -Root $root -Body @'
function Delete-DeliveryOptimizationCache { [CmdletBinding()] param([switch]$Force) }
Clear-SystemCaches
'@
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
        $result.Stats.ErrorsCount | Should -Be 0
    }

    It "Empties the Prefetch folder (Remove-FolderContent branch)" {
        (Get-ChildItem $prefetch -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Removes the single-file IconCache.db (file branch)" {
        Test-Path $iconCache | Should -BeFalse
    }

    It "Counts freed space in the System category" {
        [long]$result.Stats.FreedByCategory.System | Should -BeGreaterThan 0
    }
}

Describe "Sandbox: Clear-DriverStore" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    Get-RedundantDriverPackage and pnputil.exe are shadowed with fixtures: the real
    driver store and pnputil operate on actual installed drivers on whatever machine
    runs the tests, which a test may not touch.
    #>

    BeforeAll {
        $root = New-Sandbox
    }

    It "ReportOnly reports candidates without calling pnputil" {
        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
function Get-RedundantDriverPackage {
    @([pscustomobject]@{ Oem = 'oem10.inf'; Inf = 'sample.inf'; Bytes = 1048576; KeptVersion = [version]'2.0.0.0' })
}
function pnputil.exe { throw "pnputil must not run in ReportOnly mode" }
Clear-DriverStore
'@
        $result.ExitCode | Should -Be 0
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would clean: 1 superseded driver package'
    }

    It "Aggregates freed bytes and removed count on success" {
        $result = Invoke-Sandbox -Root $root -Body @'
function Get-RedundantDriverPackage {
    @(
        [pscustomobject]@{ Oem = 'oem10.inf'; Inf = 'a.inf'; Bytes = 1048576 }
        [pscustomobject]@{ Oem = 'oem11.inf'; Inf = 'b.inf'; Bytes = 2097152 }
    )
}
function pnputil.exe { $global:LASTEXITCODE = 0 }
Clear-DriverStore
'@
        [long]$result.Stats.FreedByCategory.DriverStore | Should -Be 3145728
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Removed 2 superseded driver package'
    }

    It "Falls back to the repo delta when a removed package has no measured size" {
        # v2.18 (#4): the old code summed per-package Bytes and fell back to the repo delta
        # only when the TOTAL was zero, so a mix of measured + unmeasured (Bytes=0)
        # understated the freed total by crediting just the measured 1 MB. Now ANY
        # unmeasured removed package makes the repo delta authoritative. pnputil is mocked
        # so nothing really leaves the store -> the delta is ~0, and crucially NOT 1 MB.
        $result = Invoke-Sandbox -Root $root -Body @'
function Get-RedundantDriverPackage {
    @(
        [pscustomobject]@{ Oem = 'oem10.inf'; Inf = 'a.inf'; Bytes = 1048576 }
        [pscustomobject]@{ Oem = 'oem11.inf'; Inf = 'b.inf'; Bytes = 0 }
    )
}
function pnputil.exe { $global:LASTEXITCODE = 0 }
Clear-DriverStore
'@
        # The warning + message prove the fallback path ran (allMeasured = false).
        $result.Stats.WarningsCount | Should -BeGreaterThan 0
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'per-package size incomplete'
        # And the credited total is the repo delta, not the naive per-package 1 MB sum.
        [long]$result.Stats.FreedByCategory.DriverStore | Should -BeLessThan 1048576
    }

    It "Counts a refused package as failed, not removed, and warns" {
        $result = Invoke-Sandbox -Root $root -Body @'
function Get-RedundantDriverPackage {
    @(
        [pscustomobject]@{ Oem = 'oem10.inf'; Inf = 'a.inf'; Bytes = 1048576 }
        [pscustomobject]@{ Oem = 'oem_fail.inf'; Inf = 'b.inf'; Bytes = 2097152 }
    )
}
function pnputil.exe {
    if ($args -contains 'oem_fail.inf') { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
}
Clear-DriverStore
'@
        [long]$result.Stats.FreedByCategory.DriverStore | Should -Be 1048576
        $result.Stats.WarningsCount | Should -BeGreaterThan 0
        Get-Content $result.Stats.LogPath -Raw | Should -Match '1 of 2 package\(s\) refused removal'
    }

    It "Reports nothing to clean when there are no candidates" {
        $result = Invoke-Sandbox -Root $root -Body @'
function Get-RedundantDriverPackage { @() }
Clear-DriverStore
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'No superseded driver packages found'
    }
}

Describe "Sandbox: Clear-DockerWSL ReportOnly" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    docker/wsl are shadowed with fixtures: a real docker system prune or wsl/diskpart
    compaction mutates real container/VHDX state a test may not touch. Only the
    ReportOnly (measure-only) branch is exercised for real.
    #>

    BeforeAll {
        $root = New-Sandbox
        $wslDir = Join-Path $root 'Users\test\AppData\Local\Packages\CanonicalGroupLimitedUbuntu_abc\LocalState'
        New-Item -ItemType Directory -Path $wslDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $wslDir 'ext4.vhdx'), 'x' * 8192)

        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
function docker { $global:LASTEXITCODE = 0 }
function wsl { $global:LASTEXITCODE = 0 }
Clear-DockerWSL
'@
    }

    It "Runs without errors" {
        $result.ExitCode | Should -Be 0
    }

    It "Reports the Docker prune it would run" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would run: docker system prune'
    }

    It "Reports the WSL/Docker disk it would compact, without touching the file" {
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would optimize 1 WSL2/Docker disk'
        Test-Path (Join-Path $wslDir 'ext4.vhdx') | Should -BeTrue
    }
}

Describe "Sandbox: Clear-EventLogs ReportOnly" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    Only the ReportOnly branch is exercised. The real path calls EventLogSession.ClearLog
    against the actual Windows Event Log service on whatever machine runs the tests.
    #>

    BeforeAll {
        $root = New-Sandbox
        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
Clear-EventLogs
'@
    }

    It "Reports without touching real event logs" {
        $result.ExitCode | Should -Be 0
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would clean: Windows Event Logs'
    }
}

Describe "Sandbox: Clear-WinCleanRecycleBin safe branches" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    Get-RecycleBinItemCount/Get-RecycleBinSize are shadowed with fixtures. The real
    deletion path (Clear-RecycleBin / Shell.Application) operates on the actual
    Recycle Bin of whatever machine runs the tests.
    #>

    BeforeAll {
        $root = New-Sandbox
    }

    It "Does nothing when the bin is already empty" {
        $result = Invoke-Sandbox -Root $root -Body @'
function Get-RecycleBinItemCount { 0 }
function Get-RecycleBinSize { 0 }
Clear-WinCleanRecycleBin
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Recycle Bin is already empty'
        [long]$result.Stats.TotalFreedBytes | Should -Be 0
    }

    It "ReportOnly reports the size without emptying" {
        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
function Get-RecycleBinItemCount { 3 }
function Get-RecycleBinSize { 5242880 }
Clear-WinCleanRecycleBin
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would clean: Recycle Bin'
        [long]$result.Stats.TotalFreedBytes | Should -Be 0
    }
}

Describe "Sandbox: New-SystemRestorePoint safe branches" -Tag "Integration" -Skip:(-not $IsElevated) {
    <#
    Only the -SkipRestore and -ReportOnly early-return paths are exercised. Real
    restore-point creation spawns Windows PowerShell running Checkpoint-Computer and
    mutates real System Restore state - project policy is that destructive runs only
    happen on the Proxmox stand (VM 190/191), never on the workstation.
    #>

    BeforeAll {
        $root = New-Sandbox
    }

    It "Returns true and does nothing when SkipRestore is set" {
        $result = Invoke-Sandbox -Root $root -Body @'
$SkipRestore = $true
$created = New-SystemRestorePoint
Write-Log "RESULT=$created" -Level INFO
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'RESULT=True'
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Restore point creation skipped'
    }

    It "Returns true and does nothing in ReportOnly mode" {
        $result = Invoke-Sandbox -Root $root -Body @'
$ReportOnly = $true
$created = New-SystemRestorePoint
Write-Log "RESULT=$created" -Level INFO
'@
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'RESULT=True'
        Get-Content $result.Stats.LogPath -Raw | Should -Match 'Would create restore point'
    }
}

Describe "Integration suite coverage" -Tag "Integration" {
    It "The integration suite actually ran" {
        # v2.17: every other Describe here is -Skip'd without administrator rights, so
        # the whole behavioural layer used to vanish silently and the run stayed green.
        # This test is deliberately NOT skippable: a non-elevated run must be visible.
        $IsElevated | Should -BeTrue -Because 'integration tests need administrator rights; without them nothing real is verified'
    }
}
