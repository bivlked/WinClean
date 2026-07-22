#Requires -Version 7.1
<#
.SYNOPSIS
    Single source of truth for what PSScriptAnalyzer checks in this repository.

.DESCRIPTION
    Both the CI lint job and tools/Invoke-ReleaseCheck.ps1 call this script, so the
    release gate cannot report green on rules CI fails on.

    That drift was real. The gate linted three files at Error severity while CI linted
    the product, both bootstrap scripts, tools/ and tests/ at Error and Warning. A
    Warning-level finding in tests/ kept main red for two days across a release, and
    the gate reported "all green" the whole time. Keeping one list in one file is what
    prevents a repeat: a gate that is weaker than CI is worse than no gate, because it
    is believed.

    The analyzer version is pinned here for the same reason. CI installed the latest
    analyzer while the workstation had an older one, so the two could enforce different
    rule sets even with identical file and rule lists. CI asks this script which version
    to install, so there is one number in one place.

.PARAMETER Quiet
    Return the findings as objects and print nothing. Used by the release gate, which
    prints its own PASS/FAIL line.

.PARAMETER FailOnFinding
    Exit with code 1 when there is at least one finding. Used by CI.

.PARAMETER RequiredAnalyzerVersion
    Print the pinned PSScriptAnalyzer version and exit, without importing anything.
    CI uses this to install exactly the version this script will import.

.OUTPUTS
    With -Quiet, the PSScriptAnalyzer findings. Otherwise a human-readable table.
#>
[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$FailOnFinding,
    [switch]$RequiredAnalyzerVersion
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# Bumping this is a deliberate act: a newer analyzer can add rules, and "the gate is
# green" has to keep meaning "CI will be green".
$analyzerVersion = '1.25.0'

# Answered before the import, so CI can ask for the number and then install it
if ($RequiredAnalyzerVersion) { return $analyzerVersion }

try {
    Import-Module PSScriptAnalyzer -RequiredVersion $analyzerVersion -ErrorAction Stop
} catch {
    throw "PSScriptAnalyzer $analyzerVersion is required (CI pins the same version). " +
          "Install it with: Install-Module PSScriptAnalyzer -RequiredVersion $analyzerVersion -Scope CurrentUser -Force"
}

# Rules that are acceptable for an interactive console utility:
# - PSAvoidUsingWriteHost: intentional, this is colored console output
# - PSAvoidUsingEmptyCatchBlock: intentional, optional operations fail silently by design
# - PSUseUsingScopeModifierInNewRunspaces: variables are passed via ArgumentList
# - PSUseShouldProcessForStateChangingFunctions: not applicable to a CLI utility
# - PSReviewUnusedParameter: parameters are consumed through the $script: scope
# - PSUseSingularNouns: naming convention choice (Clear-BrowserCaches and friends)
# - PSUseDeclaredVarsMoreThanAssignments: debug and expansion variables
# - PSUseBOMForUnicodeEncodedFile: a BOM is not required for UTF-8
# - PSAvoidOverwritingBuiltInCmdlets: Write-Log is an internal function
$excludeRules = @(
    'PSAvoidUsingWriteHost'
    'PSAvoidUsingEmptyCatchBlock'
    'PSUseUsingScopeModifierInNewRunspaces'
    'PSUseShouldProcessForStateChangingFunctions'
    'PSReviewUnusedParameter'
    'PSUseSingularNouns'
    'PSUseDeclaredVarsMoreThanAssignments'
    'PSUseBOMForUnicodeEncodedFile'
    'PSAvoidOverwritingBuiltInCmdlets'
)

# get.ps1 and install.ps1 are what users actually execute from the internet, and the
# worst incident in this project came from get.ps1, so they are linted alongside the
# product. A missing one is a hard error rather than a silently smaller scope: skipping
# it would let the lint report clean over a file it never opened.
$requiredFiles = foreach ($f in 'WinClean.ps1', 'get.ps1', 'install.ps1') {
    $full = Join-Path $repoRoot $f
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Required lint target is missing: $f"
    }
    $full
}

# tools/ and tests/ are covered too: a broken gate or a broken test is a release risk
# of its own, and this is exactly where the warning that kept main red was hiding.
$paths = @(
    $requiredFiles
    Get-ChildItem (Join-Path $repoRoot 'tools'), (Join-Path $repoRoot 'tests') -Filter *.ps1 -Recurse |
        ForEach-Object FullName
)

$findings = @(
    foreach ($p in $paths) {
        Invoke-ScriptAnalyzer -Path $p -Severity Error, Warning -ExcludeRule $excludeRules
    }
)

if ($Quiet) {
    # Data for the release gate. Printing here as well would show every finding twice.
    $findings
} else {
    if ($findings) {
        $findings | Format-Table -AutoSize ScriptName, Line, RuleName, Message | Out-Host
        Write-Host ""
        Write-Host "::error::PSScriptAnalyzer found $($findings.Count) issue(s)"
    } else {
        Write-Host "::notice::PSScriptAnalyzer $analyzerVersion : no issues found in $($paths.Count) file(s)"
    }
}

if ($FailOnFinding -and $findings) { exit 1 }
