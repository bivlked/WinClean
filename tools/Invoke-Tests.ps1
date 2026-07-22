#Requires -Version 7.1
<#
.SYNOPSIS
    Single source of truth for how this repository runs its Pester suite.

.DESCRIPTION
    Both the CI test job and tools/Invoke-ReleaseCheck.ps1 call this script, for the same
    reason tools/Invoke-Lint.ps1 exists: a gate that runs a different configuration from
    CI can report green while CI fails, and a gate that is weaker than CI is worse than
    no gate because it is believed.

    Two things were duplicated before and are now stated once:

    - The supported Pester range. CI installed Pester with an upper bound while the gate
      ran whatever `Get-Module -ListAvailable` returned, and PowerShell loads the highest
      version present. With Pester 6 published, a single `Install-Module Pester` on the
      workstation would have moved the gate to a major version CI never runs.
    - The rule that a skipped test fails the run. The integration suite is the only layer
      that executes real cleanup code and it skips itself without administrator rights,
      so "passed, the rest silently absent" must never count as success.

.PARAMETER Quiet
    Return the Pester result object and print nothing. Used by the release gate, which
    prints its own PASS/FAIL line.

.PARAMETER FailOnProblem
    Exit with code 1 when a test failed or did not run. Used by CI.

.PARAMETER RequiredPesterRange
    Print the supported version range as "<min> <max>" and exit without importing
    anything. CI uses this to install exactly the range this script will accept.

.PARAMETER ResultPath
    Optional NUnit XML result file (CI publishes it as an artifact).

.OUTPUTS
    With -Quiet, the Pester result object.
#>
[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$FailOnProblem,
    [switch]$RequiredPesterRange,
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# Pester 6 changes semantics; it must arrive deliberately, not by whoever ran
# Install-Module last. Raising this bound is a decision, not a side effect.
$minPester = '5.0'
$maxPester = '5.99.99'

# Answered before anything is imported, so CI can ask for the range and then install it
if ($RequiredPesterRange) { return "$minPester $maxPester" }

$module = Get-Module -ListAvailable Pester |
    Where-Object { $_.Version -ge [version]$minPester -and $_.Version -le [version]$maxPester } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $module) {
    $found = (Get-Module -ListAvailable Pester | ForEach-Object { $_.Version.ToString() }) -join ', '
    throw "Pester $minPester..$maxPester is required (installed: $(if ($found) { $found } else { 'none' })). " +
          "Install it with: Install-Module Pester -MinimumVersion $minPester -MaximumVersion $maxPester -Scope CurrentUser -Force"
}
Import-Module $module.Path -Force -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repoRoot 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = if ($Quiet) { 'None' } else { 'Detailed' }
if ($ResultPath) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $ResultPath
}

$result = Invoke-Pester -Configuration $config

# A test that did not run verified nothing. GitHub Windows runners are elevated, so a
# skip there means something is actually wrong rather than "no admin rights".
$notRun = $result.SkippedCount + $result.NotRunCount

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Pester $($module.Version): $($result.PassedCount)/$($result.TotalCount) passed, $($result.FailedCount) failed, $notRun did not run"
    if ($result.FailedCount -gt 0) {
        Write-Host "::error::$($result.FailedCount) test(s) failed"
    }
    if ($notRun -gt 0) {
        Write-Host "::error::$notRun test(s) did not run - coverage is missing"
    }
}

if ($Quiet) {
    # Data for the release gate. Emitting it in verbose mode too would dump the whole
    # result object onto the console after the summary above.
    $result
}

if ($FailOnProblem -and ($result.FailedCount -gt 0 -or $notRun -gt 0)) { exit 1 }
