#Requires -Version 5.1

<#
.SYNOPSIS
    WinClean one-command bootstrap: download the latest release and run it
.DESCRIPTION
    Run WinClean on any machine with a single command (PowerShell 7.1+, elevated):

        irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex

    With parameters for WinClean:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1))) -ReportOnly

    The script checks prerequisites (PowerShell 7.1+, Administrator), downloads
    WinClean.ps1 from the latest GitHub Release and runs it.

    Fails closed. A release that does not publish BOTH WinClean.ps1 and
    WinClean.ps1.sha256 is refused, and there is no fallback to a branch or a tag:
    tags are movable, release assets are not. Running unverified code elevated is
    worse than not running at all.
.NOTES
    Project: https://github.com/bivlked/WinClean
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$WinCleanArgs
)

$ErrorActionPreference = 'Stop'
$repo = 'bivlked/WinClean'

function Stop-Bootstrap {
    <# Reports a failure in a way automation can detect, without killing an `iex` host session #>
    param([string]$Message, [string]$Hint, [int]$Code = 1)
    Write-Host $Message -ForegroundColor Red
    if ($Hint) { Write-Host $Hint -ForegroundColor Yellow }
    Write-Error $Message -ErrorAction Continue
    $global:LASTEXITCODE = $Code
}

function Assert-GitHubUri {
    <# The URLs come from an API response; make sure they still point at GitHub #>
    param([string]$Uri)
    # Exact-host allowlist (v2.18). A release browser_download_url is always github.com.
    # The old suffix match also accepted ANY *.github.com / *.githubusercontent.com
    # subdomain, which this function never legitimately needs. Redirects to the asset CDN
    # are followed by Invoke-WebRequest internally and are NOT re-validated here, so the
    # CDN hosts are deliberately left out - adding them would only widen accepted API
    # values without securing the redirect step.
    $allowedHosts = @('github.com')
    $parsed = [uri]$Uri
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -notin $allowedHosts) {
        throw "Refusing to download from an unexpected host: $($parsed.Host)"
    }
    return $Uri
}

# 1. PowerShell 7.1+
if ($PSVersionTable.PSVersion -lt [version]'7.1') {
    Stop-Bootstrap "WinClean requires PowerShell 7.1+ (current: $($PSVersionTable.PSVersion))." `
                   "Install it with:  winget install --id Microsoft.PowerShell"
    return
}

# 2. Administrator
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Bootstrap "WinClean must run as Administrator." `
                   "Open an elevated PowerShell 7 (Win+X -> Terminal (Admin)) and re-run the command."
    return
}

# 3. Parse arguments BEFORE touching the network, and validate them against
#    WinClean's actual parameter set - a typo should not cost a download.
$switchParams = @('SkipUpdates', 'SkipCleanup', 'SkipRestore', 'SkipDevCleanup',
                  'SkipDockerCleanup', 'SkipVSCleanup', 'DisableTelemetry', 'ReportOnly')
$valueParams  = @('LogPath', 'ResultJsonPath')

$splat = @{}
for ($i = 0; $i -lt $WinCleanArgs.Count; $i++) {
    $token = $WinCleanArgs[$i]

    if ($token -notmatch '^-{1,2}[A-Za-z]') {
        Stop-Bootstrap "Unrecognized argument: '$token' (expected -Parameter [value])."
        return
    }

    # Accept both "-Name value" and "-Name:value"
    $name = $token -replace '^-{1,2}', ''
    $inline = $null
    if ($name -match '^([^:]+):(.*)$') { $name = $Matches[1]; $inline = $Matches[2] }

    $switchName = $switchParams | Where-Object { $_ -eq $name } | Select-Object -First 1
    $valueName  = $valueParams  | Where-Object { $_ -eq $name } | Select-Object -First 1

    if ($switchName) {
        # A switch may be given as "-Flag", "-Flag:$false" or "-Flag false".
        # Anything else is rejected rather than guessed: silently treating
        # "-ReportOnly:yes" as $false would turn an intended preview into a real
        # cleanup, which is exactly the incident this parser exists to prevent.
        $raw = if ($null -ne $inline) { $inline }
               elseif (($i + 1) -lt $WinCleanArgs.Count -and
                       $WinCleanArgs[$i + 1] -match '^\$?(true|false)$') { $WinCleanArgs[++$i] }
               else { 'true' }

        $clean = $raw -replace '^\$', ''
        if ($clean -notmatch '^(true|false)$') {
            Stop-Bootstrap "Invalid value '$raw' for switch -$switchName." `
                           "Use -$switchName, -${switchName}:`$true or -${switchName}:`$false."
            return
        }
        $splat[$switchName] = [switch]($clean -eq 'true')
    }
    elseif ($valueName) {
        $value = if ($null -ne $inline) {
            $inline
        } elseif (($i + 1) -lt $WinCleanArgs.Count -and $WinCleanArgs[$i + 1] -notmatch '^-{1,2}[A-Za-z]') {
            # Do not swallow the next token if it looks like a parameter name:
            # "-LogPath -ReportOnly" would otherwise consume the flag as a path value
            # and start a real cleanup instead of a preview
            $WinCleanArgs[++$i]
        } else {
            $null
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            Stop-Bootstrap "Parameter -$valueName requires a value."
            return
        }
        $splat[$valueName] = $value
    }
    else {
        Stop-Bootstrap "Unknown parameter '-$name'." `
                       "Known parameters: $(($switchParams + $valueParams) -join ', ')"
        return
    }
}

# 4. Resolve the latest release
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 15
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    $hint = if ($status -in 403, 429) {
        "GitHub API rate limit reached for your address. Wait an hour or download manually: https://github.com/$repo/releases"
    } else {
        "Check your connection and try again, or download manually: https://github.com/$repo/releases"
    }
    Stop-Bootstrap "Could not query the latest WinClean release: $_" $hint
    return
}

$scriptAsset = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1' } | Select-Object -First 1
$hashAsset   = $release.assets | Where-Object { $_.name -eq 'WinClean.ps1.sha256' } | Select-Object -First 1

# Both assets are mandatory. Previously a missing hash asset silently skipped
# verification entirely, which turned "fail closed" into "fail open" - exactly the
# property an attacker would target, since removing a file is easier than forging one.
if (-not $scriptAsset -or -not $hashAsset) {
    Stop-Bootstrap "Release $($release.tag_name) does not publish both WinClean.ps1 and WinClean.ps1.sha256." `
                   "Refusing to run unverified code. Download and check manually: https://github.com/$repo/releases"
    return
}

# 5. Download into a unique per-run directory (avoids a predictable-path race)
$destDir = Join-Path ([System.IO.Path]::GetTempPath()) ("WinClean-" + [guid]::NewGuid().ToString('N'))
$destPath = Join-Path $destDir 'WinClean.ps1'
New-Item -ItemType Directory -Path $destDir -Force | Out-Null

try {
    Write-Host "Downloading WinClean $($release.tag_name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri (Assert-GitHubUri $scriptAsset.browser_download_url) `
                      -OutFile $destPath -TimeoutSec 60 -MaximumRedirection 3

    # 6. Verify SHA256 against the published hash
    $hashFile = Join-Path $destDir 'WinClean.ps1.sha256'
    Invoke-WebRequest -Uri (Assert-GitHubUri $hashAsset.browser_download_url) `
                      -OutFile $hashFile -TimeoutSec 30 -MaximumRedirection 3

    $expected = ((Get-Content -LiteralPath $hashFile -Raw) -split '\s+')[0].Trim()
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') {
        Stop-Bootstrap "The published hash is not a valid SHA256 value. Aborting."
        return
    }

    $actual = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash
    # Literal comparison: -like would treat the published hash as a wildcard pattern,
    # so a single "*" in that file would make any download "verify" successfully
    if (-not [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Bootstrap "SHA256 mismatch - the downloaded file does not match the published hash. Aborting."
        return
    }
    Write-Host "SHA256 verified." -ForegroundColor DarkGray

    # Catches a captive portal or proxy error page that happens to hash correctly
    # only in the sense of being a complete file - cheap sanity check on top
    $head = Get-Content -LiteralPath $destPath -TotalCount 5 -ErrorAction Stop
    if (-not ($head -join "`n").Contains('PSScriptInfo')) {
        Stop-Bootstrap "Downloaded file does not look like WinClean.ps1 - aborting."
        return
    }

    # 7. Run.
    # NOTE: splatting a plain STRING ARRAY does not bind parameter names - the tokens
    # would be passed positionally ("-ReportOnly" would become a VALUE of the first
    # positional parameter). That is why $splat above is a hashtable.
    Write-Host "Starting WinClean..." -ForegroundColor Cyan
    Write-Host ""
    & $destPath @splat
} finally {
    Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
}
