#Requires -Modules Pester

<#
.SYNOPSIS
    Guards for the project documentation (v2.19).
.DESCRIPTION
    Two regressions this suite prevents: an em/en dash slipping into any doc (the project
    uses only hyphen-minus), and a relative Markdown link pointing at a file that does not
    exist (easy to introduce when docs move). No admin rights and no dot-sourcing needed -
    these are pure file scans, so they run everywhere the rest of the suite does.
#>

# Computed at discovery time so -ForEach can enumerate one test per file.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DocFiles = @('README.md', 'README_RU.md', 'SECURITY.md', 'CONTRIBUTING.md', 'CHANGELOG.md') +
    (Get-ChildItem (Join-Path $RepoRoot 'docs') -Filter *.md -File -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path 'docs' $_.Name })
$DocCases = $DocFiles | ForEach-Object { @{ File = $_; RepoRoot = $RepoRoot } }

Describe "Docs: punctuation" -Tag "Docs" {
    It "<File> uses only hyphen-minus, never an em/en dash" -ForEach $DocCases {
        $text = Get-Content (Join-Path $RepoRoot $File) -Raw
        # U+2013 en-dash and U+2014 em-dash - the AI-marker punctuation the project bans.
        # Built from code points so this guard file itself never contains the characters.
        $dashChars = [char[]]@([char]0x2013, [char]0x2014)
        ($text.IndexOfAny($dashChars) -ge 0) | Should -BeFalse -Because "$File must not contain em/en dashes"
    }
}

Describe "Docs: internal links resolve" -Tag "Docs" {
    It "<File> has no dangling relative links" -ForEach $DocCases {
        $path = Join-Path $RepoRoot $File
        $dir  = Split-Path $path -Parent
        $text = Get-Content $path -Raw
        $broken = foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
            $target = $m.Groups[1].Value.Trim()
            if ($target -match '^(https?:|mailto:|#)') { continue }  # external or in-page anchor
            $rel = ($target -split '#', 2)[0]                        # strip any #anchor
            if (-not $rel) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $dir $rel))) { $target }
        }
        (@($broken) -join ', ') | Should -BeNullOrEmpty -Because "$File links to missing files"
    }
}
