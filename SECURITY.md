# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.x     | :white_check_mark: |
| 1.x     | :x:                |

## Security Features

WinClean is designed with security in mind:

- **System Restore Point**: Created before any changes
- **Protected Paths**: Critical system folders are never touched
- **No Network Data**: Script doesn't send any data externally
- **No Credentials**: Script never stores or transmits credentials
- **Dry Run Mode**: `-ReportOnly` flag to preview all changes
- **SHA256 verification** (since 2.15): `get.ps1` and `install.ps1` download the script from the latest GitHub Release and verify it against the published `WinClean.ps1.sha256` asset. Verification is fail-closed - a hash mismatch or a missing asset aborts the run, and the scripts never silently fall back to a mutable branch
- **Protected install location** (since 2.15): `install.ps1` installs to `%ProgramFiles%\WinClean`, which requires administrator rights to modify, so the elevated desktop shortcut cannot be hijacked by a non-admin process
- **Explicit parameter binding** (since 2.15): the script declares `PositionalBinding = $false`, so a stray argument fails loudly instead of silently binding to the wrong parameter

### Protected Paths (Never Modified)

```
C:\Windows\
C:\Program Files\
C:\Program Files (x86)\
C:\Users\
C:\Users\<Username>\
```

## Reporting a Vulnerability

If you discover a security vulnerability in WinClean, please report it responsibly:

### How to Report

1. **DO NOT** create a public GitHub issue for security vulnerabilities
2. **Email** the maintainer directly (create a private security advisory)
3. Or use GitHub's [private vulnerability reporting](https://github.com/bivlked/WinClean/security/advisories/new)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 24-48 hours
  - High: 1 week
  - Medium: 2 weeks
  - Low: Next release

### After Reporting

1. We will acknowledge receipt of your report
2. We will investigate and determine impact
3. We will develop and test a fix
4. We will release a patched version
5. We will publicly acknowledge your contribution (unless you prefer anonymity)

## Security Best Practices for Users

When using WinClean:

1. **Always download from official sources** (GitHub Releases or PowerShell Gallery).
2. **For integrity, use `get.ps1` / `install.ps1`.** They fail-closed: the script is downloaded from the latest GitHub Release and its SHA256 is compared exactly against the published `WinClean.ps1.sha256` asset. A mismatch or a missing hash asset aborts the run, and the scripts never fall back to a mutable branch. If you download `WinClean.ps1` manually, verify its hash yourself against the release asset.
3. **For a safe preview, use `-ReportOnly`.** It shows the actions WinClean would take and changes nothing. Note this is a *preview of behavior*, not an *integrity check* - the two are separate concerns.
4. **Run with minimum necessary privileges** (though administrator is required).
5. **Keep PowerShell updated** to the latest version.
6. **Review the changelog** before updating to new versions.

## Supply Chain

- **Bootstrap:** `get.ps1` and `install.ps1` pull from GitHub Release assets (immutable), not from `main`, and verify SHA256 fail-closed (see above). See [docs/safety.md](docs/safety.md) for the full trust model.
- **CI GitHub Actions** are pinned to full commit SHAs (not moving tags like `@v4`), and [Dependabot](.github/dependabot.yml) opens update PRs so the pins stay current. This limits the blast radius of a compromised action tag for a utility that runs elevated.
- **Releases** are verified end-to-end on real Windows 11 VMs (ru-RU and en-US) before publishing; the release gate is documented in [docs/release-process.md](docs/release-process.md).

## Scope

The following are **in scope** for security reports:

- Code execution vulnerabilities
- Privilege escalation
- Data destruction outside intended scope
- Information disclosure
- Bypass of safety mechanisms

The following are **out of scope**:

- Issues requiring physical access to the machine
- Social engineering
- Issues in dependencies not controlled by this project
- Issues already publicly known

---

*Thank you for helping keep WinClean secure!*
