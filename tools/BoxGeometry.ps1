# Shared helper: automated console box-geometry validation.
# Dot-sourced by tools/Invoke-SmokeTest.ps1 and tools/proxmox/Invoke-StandTest.ps1.

function Test-BoxGeometry {
    <#
    .SYNOPSIS
        Checks that all console box lines are geometrically consistent
    .DESCRIPTION
        Walks captured WinClean console output. Inside every ╔═╗ ... ╚═╝ box each
        ║ row, ╠═╣/╟─╢ divider and the ╚═╝ bottom must match the top border width,
        and no foreign output (DISM/winget progress spam) may appear inside a box.
    .NOTES
        Measures character counts, not font display width - that is why the script
        avoids ambiguous-width glyphs inside boxes (see v2.14 CHANGELOG).
    .OUTPUTS
        [string[]] issue descriptions; empty array = geometry OK
    #>
    param([string[]]$Lines)

    $issues = @()
    $boxWidth = $null
    $boxStart = 0

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].TrimEnd()

        if ($line -match '^\s*╔(═+)╗$') {
            if ($null -ne $boxWidth) {
                $issues += "line $($boxStart): box opened but never closed before line $($i + 1)"
            }
            $boxWidth = $Matches[1].Length
            $boxStart = $i + 1
        }
        elseif ($null -eq $boxWidth -and $line -match '[╔║╠╟╣╢╚╗╝]') {
            # Box glyphs outside any recognized box = malformed top border or
            # orphaned fragment - must not pass silently
            $issues += "line $($i + 1): orphaned box glyph outside a recognized box: '$($line.Trim())'"
        }
        elseif ($null -ne $boxWidth) {
            if ($line -match '^\s*║(.*)║$') {
                if ($Matches[1].Length -ne $boxWidth) {
                    $issues += "line $($i + 1): row width $($Matches[1].Length) != border width $boxWidth"
                }
            }
            elseif ($line -match '^\s*[╠╟]([═─]+)[╣╢]$') {
                if ($Matches[1].Length -ne $boxWidth) {
                    $issues += "line $($i + 1): divider width $($Matches[1].Length) != border width $boxWidth"
                }
            }
            elseif ($line -match '^\s*╚(═+)╝$') {
                if ($Matches[1].Length -ne $boxWidth) {
                    $issues += "line $($i + 1): bottom width $($Matches[1].Length) != border width $boxWidth"
                }
                $boxWidth = $null
            }
            else {
                $issues += "line $($i + 1): non-box output inside an open box: '$($line.Trim())'"
            }
        }
    }

    if ($null -ne $boxWidth) {
        $issues += "line $($boxStart): box opened but never closed (end of output)"
    }

    return $issues
}
