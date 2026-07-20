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
