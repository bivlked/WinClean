#Requires -Version 7.1

<#
.SYNOPSIS
    Pre-release gate for WinClean: one fail-closed command instead of a manual checklist
.DESCRIPTION
    Runs every check that must pass before tagging a release and prints a single
    verdict. Exit code 0 means "safe to release", 1 means at least one check failed.

    Beyond the usual syntax/lint/test trio it verifies the things that actually went
    wrong in this project before: the version drifting apart between the five places
    it lives in, test counters in the docs disagreeing with reality, em dashes
    creeping into documentation, and a release tag published without assets (which
    silently keeps serving the previous version to every one-liner user).

    The stand run and the published-release check are opt-in because they are slow
    or only meaningful after publishing.
.PARAMETER SkipSmoke
    Skip the ReportOnly smoke run (it takes ~15 seconds and requires administrator)
.PARAMETER IncludeStand
    Also run a full test on the Proxmox stand VM (several minutes)
.PARAMETER VerifyPublished
    After publishing: download the release asset and compare its SHA256 with the
    local file, exactly the way get.ps1 and install.ps1 do
.EXAMPLE
    pwsh tools/Invoke-ReleaseCheck.ps1
.EXAMPLE
    pwsh tools/Invoke-ReleaseCheck.ps1 -IncludeStand
.EXAMPLE
    pwsh tools/Invoke-ReleaseCheck.ps1 -VerifyPublished
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipSmoke,
    [switch]$IncludeStand,
    [switch]$VerifyPublished
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'WinClean.ps1'

$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail = ''
    )
    $script:Results.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
    $mark = if ($Passed) { 'PASS' } else { 'FAIL' }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $mark, $Name) -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "WinClean release check" -ForegroundColor Cyan
Write-Host "  repo: $repoRoot" -ForegroundColor DarkGray
Write-Host ""

# --- 1. Version is the same in every place that carries it -------------------
# Five in-script locations plus badges and the flow diagram in both READMEs.
$scriptText = Get-Content $scriptPath -Raw
$version = if ($scriptText -match '(?m)^\$script:Version\s*=\s*"([\d.]+)"') { $Matches[1] } else { $null }

if (-not $version) {
    Add-Result -Name 'Version can be determined' -Passed $false -Detail 'no $script:Version assignment found'
} else {
    $versionSites = @(
        @{ What = 'PSScriptInfo .VERSION'; Ok = $scriptText -match "(?m)^\.VERSION\s+$([regex]::Escape($version))\s*$" }
        @{ What = '.RELEASENOTES first line'; Ok = $scriptText -match "(?m)^\s*v$([regex]::Escape($version)):" }
        @{ What = 'SYNOPSIS'; Ok = $scriptText -match "Maintenance Script v$([regex]::Escape($version))" }
        @{ What = 'NOTES Version'; Ok = $scriptText -match "(?m)^\s*Version:\s+$([regex]::Escape($version))\s*$" }
        @{ What = 'NOTES Changes in'; Ok = $scriptText -match "Changes in $([regex]::Escape($version)):" }
    )
    foreach ($readme in @('README.md', 'README_RU.md')) {
        $text = Get-Content (Join-Path $repoRoot $readme) -Raw
        $versionSites += @{ What = "$readme badge"; Ok = $text -match "-$([regex]::Escape($version))-blue" }
        $versionSites += @{ What = "$readme flow diagram"; Ok = $text -match "WinClean v$([regex]::Escape($version))" }
    }

    $missing = @($versionSites | Where-Object { -not $_.Ok } | ForEach-Object { $_.What })
    Add-Result -Name "Version $version is consistent in all 9 places" -Passed ($missing.Count -eq 0) `
        -Detail $(if ($missing) { "не совпадает: $($missing -join ', ')" } else { '' })
}

# --- 2. CHANGELOG has an entry for this version ------------------------------
if ($version) {
    $changelog = Get-Content (Join-Path $repoRoot 'CHANGELOG.md') -Raw
    $hasEntry = $changelog -match "(?m)^##\s*\[$([regex]::Escape($version))\]"
    Add-Result -Name "CHANGELOG has a [$version] entry" -Passed $hasEntry
}

# --- 3. No em/en dashes anywhere (absolute project rule) ---------------------
# grep -P lies in the C locale, so the check is done in PowerShell directly.
$dashFiles = @('README.md', 'README_RU.md', 'CHANGELOG.md', 'CONTRIBUTING.md',
               'SECURITY.md', 'CLAUDE.md', 'WinClean.ps1', 'get.ps1', 'install.ps1')
$withDashes = foreach ($f in $dashFiles) {
    $full = Join-Path $repoRoot $f
    if (-not (Test-Path $full)) { continue }
    $count = ([regex]::Matches((Get-Content $full -Raw), '[–—]')).Count
    if ($count -gt 0) { "$f ($count)" }
}
Add-Result -Name 'No em/en dashes in code and docs' -Passed (-not $withDashes) `
    -Detail $(if ($withDashes) { $withDashes -join ', ' } else { '' })

# --- 4. Syntax of all three shipped scripts ----------------------------------
$syntaxErrors = foreach ($f in @('WinClean.ps1', 'get.ps1', 'install.ps1')) {
    $full = Join-Path $repoRoot $f
    if (-not (Test-Path $full)) { continue }
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) { "$f ($($errors.Count))" }
}
Add-Result -Name 'PowerShell syntax is valid' -Passed (-not $syntaxErrors) `
    -Detail $(if ($syntaxErrors) { $syntaxErrors -join ', ' } else { '' })

# --- 5. PSScriptAnalyzer: no Error-level findings ----------------------------
# Warnings are expected and documented in CLAUDE.md (Write-Host, empty catch blocks).
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $analyzerErrors = @(Invoke-ScriptAnalyzer -Path $scriptPath -Severity Error)
    Add-Result -Name 'PSScriptAnalyzer: no errors' -Passed ($analyzerErrors.Count -eq 0) `
        -Detail $(if ($analyzerErrors) { ($analyzerErrors | Select-Object -First 3 | ForEach-Object { "$($_.RuleName):$($_.Line)" }) -join ', ' } else { '' })
} else {
    Add-Result -Name 'PSScriptAnalyzer available' -Passed $false -Detail 'module not installed'
}

# --- 6. Pester, and the count the docs claim ---------------------------------
# Counting It blocks by hand is wrong here: -ForEach multiplies them.
$pesterCount = $null
if (Get-Module -ListAvailable Pester) {
    $pester = Invoke-Pester -Path (Join-Path $repoRoot 'tests') -PassThru -Output None
    $pesterCount = $pester.TotalCount
    Add-Result -Name "Pester: $($pester.PassedCount)/$($pester.TotalCount) passed" -Passed ($pester.FailedCount -eq 0) `
        -Detail $(if ($pester.FailedCount) { ($pester.Failed | Select-Object -First 3 | ForEach-Object { $_.ExpandedPath }) -join '; ' } else { '' })

    $countClaims = @(
        @{ File = 'CLAUDE.md';       Pattern = "$pesterCount Pester" }
        @{ File = 'CONTRIBUTING.md'; Pattern = "$pesterCount tests" }
    )
    $wrongCounts = foreach ($claim in $countClaims) {
        $full = Join-Path $repoRoot $claim.File
        if ((Test-Path $full) -and (Get-Content $full -Raw) -notmatch [regex]::Escape($claim.Pattern)) { $claim.File }
    }
    Add-Result -Name "Docs agree that there are $pesterCount tests" -Passed (-not $wrongCounts) `
        -Detail $(if ($wrongCounts) { "устарел счётчик: $($wrongCounts -join ', ')" } else { '' })
} else {
    Add-Result -Name 'Pester available' -Passed $false -Detail 'module not installed'
}

# --- 7. Smoke run (ReportOnly) -----------------------------------------------
if ($SkipSmoke) {
    Write-Host "  [SKIP] Smoke run (-SkipSmoke)" -ForegroundColor DarkGray
} else {
    $smokeOut = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-SmokeTest.ps1') 2>&1
    $smokePassed = $LASTEXITCODE -eq 0
    Add-Result -Name 'Smoke run (ReportOnly, box geometry, result JSON)' -Passed $smokePassed `
        -Detail $(if (-not $smokePassed) { ($smokeOut | Select-Object -Last 3) -join ' | ' } else { ($smokeOut | Select-Object -Last 1) })
}

# --- 8. Working tree is clean and pushed -------------------------------------
Push-Location $repoRoot
try {
    $dirty = @(& git status --porcelain)
    Add-Result -Name 'Working tree is clean' -Passed ($dirty.Count -eq 0) `
        -Detail $(if ($dirty) { "$($dirty.Count) файл(ов) не закоммичено" } else { '' })

    $branchInfo = (& git status -sb | Select-Object -First 1)
    $notPushed = $branchInfo -match '\[(ahead|behind)'
    Add-Result -Name 'Branch is in sync with origin' -Passed (-not $notPushed) -Detail $(if ($notPushed) { $branchInfo } else { '' })
} finally {
    Pop-Location
}

# --- 9. Stand run (opt-in) ---------------------------------------------------
if ($IncludeStand) {
    Write-Host "  ...running the stand VM, this takes a few minutes" -ForegroundColor DarkGray
    $standOut = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'proxmox\Invoke-StandTest.ps1') -Mode Full -Source local 2>&1
    $standPassed = $LASTEXITCODE -eq 0
    Add-Result -Name 'Stand test (full run on a VM)' -Passed $standPassed `
        -Detail (($standOut | Where-Object { $_ -match 'STAND TEST|freed|warnings' } | Select-Object -Last 2) -join ' | ')
}

# --- 10. Published release actually carries the assets (opt-in) --------------
# A tag without assets keeps every one-liner user on the previous version.
if ($VerifyPublished -and $version) {
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/bivlked/WinClean/releases/latest"
        Add-Result -Name "Latest release is v$version" -Passed ($release.tag_name -eq "v$version") -Detail "tag: $($release.tag_name)"

        $assetScript = $release.assets | Where-Object name -eq 'WinClean.ps1'
        $assetHash = $release.assets | Where-Object name -eq 'WinClean.ps1.sha256'
        Add-Result -Name 'Release carries both assets' -Passed ($assetScript -and $assetHash)

        if ($assetScript -and $assetHash) {
            $tmpScript = Join-Path ([System.IO.Path]::GetTempPath()) "wc-relcheck-$(Get-Random).ps1"
            $tmpHash = "$tmpScript.sha256"
            try {
                Invoke-WebRequest $assetScript.browser_download_url -OutFile $tmpScript
                Invoke-WebRequest $assetHash.browser_download_url -OutFile $tmpHash
                # Read from files, not from .Content: Invoke-WebRequest returns a byte
                # array here, and -split over an array yields garbage instead of a hash
                $published = ((Get-Content $tmpHash -Raw) -split '\s+')[0]
                $downloaded = (Get-FileHash $tmpScript -Algorithm SHA256).Hash
                $local = (Get-FileHash $scriptPath -Algorithm SHA256).Hash
                Add-Result -Name 'Asset hash matches its .sha256 file' -Passed ($published -eq $downloaded)
                Add-Result -Name 'Published asset matches the local script' -Passed ($local -eq $downloaded)
            } finally {
                Remove-Item $tmpScript, $tmpHash -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Add-Result -Name 'Published release check' -Passed $false -Detail $_.Exception.Message
    }
}

# --- Verdict -----------------------------------------------------------------
$failed = @($script:Results | Where-Object { -not $_.Passed })

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "RELEASE CHECK PASSED" -ForegroundColor Green
    Write-Host "  $($script:Results.Count) checks, all green$(if ($version) { " (v$version)" })" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host "RELEASE CHECK FAILED" -ForegroundColor Red
    Write-Host "  $($failed.Count) of $($script:Results.Count) checks failed:" -ForegroundColor Red
    foreach ($f in $failed) { Write-Host "    - $($f.Name)$(if ($f.Detail) { " : $($f.Detail)" })" -ForegroundColor Red }
    Write-Host ""
    exit 1
}
