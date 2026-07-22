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
        # v2.19: the version badge is dynamic (shields.io github/v/release), so it carries no
        # hardcoded version to drift. Guard that it stayed dynamic rather than being
        # re-hardcoded; the flow diagram still names the version explicitly, so that is the
        # place the release must bump.
        $versionSites += @{ What = "$readme dynamic release badge"; Ok = $text -match "img\.shields\.io/github/v/release/bivlked/WinClean" }
        $versionSites += @{ What = "$readme flow diagram"; Ok = $text -match "WinClean v$([regex]::Escape($version))" }
    }

    $missing = @($versionSites | Where-Object { -not $_.Ok } | ForEach-Object { $_.What })
    Add-Result -Name "Version $version is consistent in all $($versionSites.Count) places" -Passed ($missing.Count -eq 0) `
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
$dashFiles = @(
    'README.md', 'README_RU.md', 'CHANGELOG.md', 'CONTRIBUTING.md',
    'SECURITY.md', 'CLAUDE.md', 'WinClean.ps1', 'get.ps1', 'install.ps1'
) + @(Get-ChildItem -Path (Join-Path $repoRoot 'tests'), (Join-Path $repoRoot 'tools') `
        -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
      ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) })

$withDashes = foreach ($f in $dashFiles) {
    $full = Join-Path $repoRoot $f
    if (-not (Test-Path $full)) { continue }
    # Unicode escapes, not the characters themselves: a literal em dash here would make
    # this file fail its own check as soon as tools/ joined the list
    $count = ([regex]::Matches((Get-Content $full -Raw), '[\u2013\u2014]')).Count
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

# --- 5. PSScriptAnalyzer, exactly the scope CI enforces ----------------------
# Runs tools/Invoke-Lint.ps1, the same script the CI lint job runs, so this gate
# cannot be greener than CI. It used to be: this check linted three files at Error
# severity while CI linted tools/ and tests/ too, at Error and Warning. A Warning in
# tests/ kept main red for two days across a release and the gate never saw it.
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $analyzerFindings = @(& (Join-Path $PSScriptRoot 'Invoke-Lint.ps1') -Quiet)
    Add-Result -Name 'PSScriptAnalyzer: no findings (same scope as CI)' -Passed ($analyzerFindings.Count -eq 0) `
        -Detail $(if ($analyzerFindings) { ($analyzerFindings | Select-Object -First 3 | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName)" }) -join ', ' } else { '' })
} else {
    Add-Result -Name 'PSScriptAnalyzer available' -Passed $false -Detail 'module not installed'
}

# --- 6. Pester, and the count the docs claim ---------------------------------
# Counting It blocks by hand is wrong here: -ForEach multiplies them.
#
# v2.20: runs through tools/Invoke-Tests.ps1, the same script CI runs, so the gate cannot
# execute a different Pester version or a laxer rule than CI. It used to call Invoke-Pester
# directly with no version bound while CI pinned an upper bound, and PowerShell loads the
# highest installed version - so installing Pester 6 would silently split the two.
$pesterCount = $null
$pester = $null
try {
    $pester = & (Join-Path $PSScriptRoot 'Invoke-Tests.ps1') -Quiet
} catch {
    Add-Result -Name 'Pester available in the supported range' -Passed $false -Detail "$_"
}
if ($pester) {
    $pesterCount = $pester.TotalCount
    # Skipped tests count as a failure of the gate. The integration suite - the only
    # layer that executes real cleanup code - skips itself without administrator rights,
    # and a release must never go out on "176 of 204 passed, the rest silently absent".
    $notRun = $pester.SkippedCount + $pester.NotRunCount
    Add-Result -Name "Pester: $($pester.PassedCount)/$($pester.TotalCount) passed, none skipped" `
        -Passed ($pester.FailedCount -eq 0 -and $notRun -eq 0) `
        -Detail $(
            if ($pester.FailedCount) { ($pester.Failed | Select-Object -First 3 | ForEach-Object { $_.ExpandedPath }) -join '; ' }
            elseif ($notRun) { "$notRun тест(ов) не выполнено - нужны права администратора" }
            else { '' })

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

    # v2.20: this used to read `git status -sb`, which compares against the LOCAL
    # remote-tracking ref. Without a fetch it confirms a state that may no longer exist:
    # the gate would report "in sync with origin" while origin had already moved. Ask the
    # remote, and fail closed when it cannot be asked - an unverifiable claim is not a
    # passing check.
    $fetchOut = & git fetch --prune 2>&1
    $fetchOk = $LASTEXITCODE -eq 0

    $upstream = & git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
    # No upstream at all is not "in sync", it is "nothing to sync with"
    $hasUpstream = ($LASTEXITCODE -eq 0) -and $upstream

    $ahead = $behind = 0
    if ($hasUpstream) {
        $counts = (& git rev-list --left-right --count 'HEAD...@{upstream}') -split '\s+'
        if ($counts.Count -ge 2) { $ahead = [int]$counts[0]; $behind = [int]$counts[1] }
    }

    $syncDetail =
        if (-not $fetchOk)      { "git fetch не удался - состояние origin неизвестно: $(($fetchOut | Select-Object -Last 1))" }
        elseif (-not $upstream) { 'у ветки нет upstream' }
        elseif ($ahead -or $behind) { "ahead $ahead, behind $behind (upstream: $upstream)" }
        else { '' }

    Add-Result -Name 'Branch is in sync with origin (verified against the remote)' `
        -Passed ($fetchOk -and $hasUpstream -and $ahead -eq 0 -and $behind -eq 0) -Detail $syncDetail
} finally {
    Pop-Location
}

# --- 9. Stand run (opt-in) ---------------------------------------------------
if ($IncludeStand) {
    Write-Host "  ...running the stand VM, this takes a few minutes" -ForegroundColor DarkGray
    # Join-Path per segment: a backslash inside the argument is a literal character on
    # Linux/macOS, not a separator, so "proxmox\Invoke-StandTest.ps1" would be one odd
    # filename there. This gate is not deployed to the Proxmox host today (only the four
    # scripts in Deploy-StandRunner are), so this is hygiene rather than a live defect.
    $standScript = Join-Path (Join-Path $PSScriptRoot 'proxmox') 'Invoke-StandTest.ps1'
    $standOut = & pwsh -NoProfile -File $standScript -Mode Full -Source local 2>&1
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
