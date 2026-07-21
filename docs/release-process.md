# Release process

This is the manual runbook for shipping a WinClean release. It is deliberately manual: an automated `release.yml` workflow is a future improvement and is intentionally deferred for now, so every release goes through the checklist below and the machine gate `Invoke-ReleaseCheck.ps1`.

## Why all channels must agree

WinClean is distributed through several channels, and they must all show the same version at the same time:

- **`main`** holds the source of truth for the code.
- **README badges** advertise the current version. The version badge is dynamic (it reads the latest GitHub Release via shields.io), so it follows the release automatically; the version that still needs a manual bump is the flow-diagram heading in each README.
- **GitHub Release** is what the one-line bootstrap scripts consume: both `get.ps1` and `install.ps1` download `WinClean.ps1` from the **latest GitHub Release** and verify it against the published `WinClean.ps1.sha256` asset. They are fail-closed: a missing asset or a hash mismatch aborts the run, and there is no fallback to a mutable branch.
- **PSGallery** is what the script's built-in update check uses: `Test-ScriptUpdate` compares the running version against the PowerShell Gallery. An installed copy only learns about a new version if it was published there.
- **CHANGELOG.md** is the human record of what changed.

If these drift, users get confused or, worse, run an old version while the README promises a new one. A `git push` alone does **not** publish a release: the bootstrap scripts keep serving the previous GitHub Release until you cut a new one.

## Where the version lives

The version appears in several places inside `WinClean.ps1` (the `$script:Version` variable, the PSScriptInfo `.VERSION`, `.RELEASENOTES`, the `.SYNOPSIS`, and the `NOTES` block) and in the docs (the flow diagram heading in both READMEs, and the CHANGELOG entry). The README version badge is dynamic and needs no bump; the test-count lines in CONTRIBUTING and CLAUDE are a separate counter the gate also checks. Line numbers move between releases, so find each spot by content (grep), not by a fixed line number.

You do not verify these by hand. The machine gate does it for you.

## The machine gate

```powershell
pwsh tools/Invoke-ReleaseCheck.ps1
```

This is fail-closed and checks, at minimum:

- the version is consistent across every place it appears;
- there are no em-dashes or en-dashes anywhere in the tracked text (only hyphen-minus is allowed);
- the documented test counters match the real Pester count;
- PowerShell syntax parses;
- PSScriptAnalyzer reports no Error-level findings;
- Pester runs with **no skipped tests** (a skipped integration suite is a silent gap);
- the smoke test passes (a real `-ReportOnly` run, console box geometry, result JSON);
- the working tree is clean and pushed.

Optional flags:

- `-IncludeStand` also runs one real cleanup on the stand (`Invoke-StandTest.ps1 -Mode Full -Source local` against the default config). The broader RU + EN and `ReportNoCleanup` matrix below is run manually.
- `-VerifyPublished` is run **after** the GitHub Release exists: it confirms both assets are present and that the published `WinClean.ps1.sha256` matches the released `WinClean.ps1`.

## Cutting the GitHub Release

Compute the hash, write the sidecar file, and create the release with both assets:

```powershell
$hash = (Get-FileHash .\WinClean.ps1 -Algorithm SHA256).Hash
"$hash  WinClean.ps1" | Out-File "$env:TEMP\WinClean.ps1.sha256" -Encoding ascii -NoNewline

gh release create vX.Y `
  ".\WinClean.ps1#WinClean.ps1" `
  "$env:TEMP\WinClean.ps1.sha256#WinClean.ps1.sha256" `
  --title "WinClean vX.Y" `
  --notes "..."
```

**Both assets are mandatory.** A release that publishes `WinClean.ps1` without `WinClean.ps1.sha256` is refused by `get.ps1` (it will not run unverified code elevated). If you have to correct the script inside an already-published release, re-upload with `--clobber` and recompute the hash so the two stay in sync:

```powershell
$hash = (Get-FileHash .\WinClean.ps1 -Algorithm SHA256).Hash
"$hash  WinClean.ps1" | Out-File "$env:TEMP\WinClean.ps1.sha256" -Encoding ascii -NoNewline
gh release upload vX.Y ".\WinClean.ps1#WinClean.ps1" "$env:TEMP\WinClean.ps1.sha256#WinClean.ps1.sha256" --clobber
```

## Publishing to PSGallery

```powershell
Publish-PSResource -Path .\WinClean.ps1 -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY
```

The API key lives in the `PSGALLERY_API_KEY` environment variable. Publishing here is what lets already-installed copies discover the update through `Test-ScriptUpdate`; skipping it leaves PSGallery users behind even though the GitHub one-liners are current.

## Stand verification

Every release is validated on real Windows 11 VMs before and after publishing, run manually with `tools/proxmox/Invoke-StandTest.ps1`:

- **RU (VM 190)** and **EN (VM 191)** (via `-ConfigPath`), so locale-dependent parsing is exercised in both cultures.
- **Full** runs (real cleanup) plus **`-Mode ReportNoCleanup`** (a preview with `-SkipCleanup`, which verifies end-to-end that the whole cleanup group is suppressed and reported as skipped).
- The nightly matrix additionally runs a quick pass with **`-Source release`**, which downloads `WinClean.ps1` from the latest release **tag** (`raw.githubusercontent.com/.../<tag>/WinClean.ps1`). This catches a broken release with a healthy `main`; note it exercises the tag's script content, not the release **asset** download or the `get.ps1` one-liner (those are covered by `-VerifyPublished` and a manual one-liner run). The nightly also has a dead-man heartbeat check: an independent, later cron reports if the matrix never ran, so a silent night is not mistaken for a healthy one.

## Checklist

1. Land all code and doc changes on the release branch; update `CHANGELOG.md` with the new version section.
2. Bump the version in every place inside `WinClean.ps1` and the docs (verify by grep, not line number).
3. Run `pwsh tools/Invoke-ReleaseCheck.ps1` until green.
4. Run `pwsh tools/Invoke-ReleaseCheck.ps1 -IncludeStand` (one Full/local pass), and manually run the RU + EN stand (`Invoke-StandTest.ps1` with each `-ConfigPath`) in Full and `-Mode ReportNoCleanup`.
5. Merge to `main` and push.
6. Compute the SHA256, write `WinClean.ps1.sha256`, and `gh release create vX.Y` with both assets.
7. `Publish-PSResource` to PSGallery.
8. Run `pwsh tools/Invoke-ReleaseCheck.ps1 -VerifyPublished` (confirms the assets and SHA256), then a manual one-liner run (`irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex`, or `Invoke-StandTest.ps1 -Source release` on the stand) to confirm the new version is served.
9. Confirm README badges, the GitHub Release, PSGallery and the CHANGELOG all show the same version.
