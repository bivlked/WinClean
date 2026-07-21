<div align="center">

<img src="https://raw.githubusercontent.com/bivlked/WinClean/main/assets/logo.svg" alt="WinClean Logo" width="120" height="120">

# WinClean

### Ultimate Windows 11 Maintenance Script

[![Latest release](https://img.shields.io/github/v/release/bivlked/WinClean?label=release&logo=github&color=blue)](https://github.com/bivlked/WinClean/releases/latest)
[![PSGallery](https://img.shields.io/powershellgallery/v/WinClean?label=PSGallery&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/WinClean)
[![CI](https://github.com/bivlked/WinClean/actions/workflows/ci.yml/badge.svg)](https://github.com/bivlked/WinClean/actions/workflows/ci.yml)
[![PowerShell 7.1+](https://img.shields.io/badge/PowerShell-7.1%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**One command to update, clean, and optimize Windows 11 - safely.**

[English](README.md) | [Русский](README_RU.md)

---

[Quick Start](#-quick-start) •
[Features](#-features) •
[Parameters](#-parameters) •
[Safety](#%EF%B8%8F-safety) •
[Docs](#-learn-more) •
[FAQ](#-faq)

</div>

---

**WinClean** is a free, open-source **Windows 11 cleanup and maintenance script** written in **PowerShell**. In one command it installs Windows and app updates, **frees disk space** by clearing temporary files and browser caches, **cleans developer caches** (npm, pip, NuGet, Docker, WSL, IDEs), and runs a deep system cleanup - all with a restore point, protected system paths, and a preview mode so nothing important is touched.

> 💡 **Typical result:** 5-20 GB freed, depending on how the system is used.

---

## 🚀 Quick Start

> **Requirements:** PowerShell 7.1+ (`winget install Microsoft.PowerShell`) and an **elevated** terminal (Win+X -> Terminal (Admin)).

**See what it would do first (a preview that changes nothing):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1))) -ReportOnly
```

**Run it once (updates + cleanup):**

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex
```

**Install (or update) + create a desktop shortcut that always runs elevated:**

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/install.ps1 | iex
```

<table>
<tr>
<td>

### 🔒 Why the one-liner is safe to trust

- The bootstrap scripts download WinClean from the **latest GitHub Release** and **verify its SHA256** against the published `WinClean.ps1.sha256` asset. Verification is **fail-closed**: a mismatch or a missing asset aborts, with no fallback to a mutable branch.
- `install.ps1` installs into `%ProgramFiles%\WinClean` (admin-only), so the elevated shortcut cannot be hijacked.
- `-ReportOnly` shows exactly what would happen and changes nothing.
- MIT licensed, no telemetry, no data leaves your machine. See **[SECURITY.md](SECURITY.md)** and **[docs/safety.md](docs/safety.md)**.

</td>
</tr>
</table>

<details>
<summary>📥 Alternative installation methods</summary>

### 📦 PowerShell Gallery

```powershell
Install-Script -Name WinClean -Scope CurrentUser
```

Then run as Administrator:
```powershell
WinClean.ps1
```

### Manual download

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1" -OutFile "WinClean.ps1"
.\WinClean.ps1
```

### Clone the repository

```powershell
git clone https://github.com/bivlked/WinClean.git
cd WinClean
.\WinClean.ps1
```

</details>

---

## 🎯 Why WinClean?

<table>
<tr>
<td width="50%">

### 😫 Before WinClean

- Manually run Windows Update
- Open each browser to clear cache
- Remember npm/pip/nuget cache locations
- Forget about Docker cleanup for months
- Run Disk Cleanup separately
- Hope you didn't delete something important

</td>
<td width="50%">

### 😎 With WinClean

- **One command** does everything
- **All browsers** cleaned automatically
- **All dev tools** handled in parallel
- **Docker & WSL** optimized
- **Deep cleanup** with DISM
- **Safe by design** - protected paths

</td>
</tr>
</table>

---

## ✨ Features

<table>
<tr>
<td width="33%" valign="top">

### 🔄 Updates
- Windows Update (+ drivers, via PSWindowsUpdate)
- winget packages (incl. Store-sourced packages winget exposes)

</td>
<td width="33%" valign="top">

### 🗑️ Cleanup
- Temp files (age-aware)
- Browser caches (7 browsers)
- Windows caches
- Driver store (superseded versions)
- Stale kernel dumps
- Recycle Bin emptying
- Windows.old removal
- Disk space report

</td>
<td width="33%" valign="top">

### 👨‍💻 Developer
- npm / yarn / pnpm
- pip / Composer
- NuGet / Gradle / Cargo
- Go build cache

</td>
</tr>
<tr>
<td width="33%" valign="top">

### 🐳 Docker & WSL
- Unused images
- Stopped containers
- Build cache
- WSL2 VHDX compaction

</td>
<td width="33%" valign="top">

### 🛠️ IDEs
- Visual Studio caches
- VS Code caches
- JetBrains IDEs
- MEF cache cleanup

</td>
<td width="33%" valign="top">

### 🔒 Privacy
- DNS cache flush
- Event logs cleanup
- Run history (Win+R)
- Explorer history
- Recent documents
- Telemetry *(optional)*

</td>
</tr>
</table>

> **Browsers:** Edge, Chrome, Brave, Yandex, Opera, Opera GX, and Firefox. Every profile is cleaned for Chrome, Edge, and Firefox; the default profile for the rest. Bookmarks, passwords, and history are never touched. Full inventory: **[docs/what-is-cleaned.md](docs/what-is-cleaned.md)**.

---

## 📋 Parameters

| Parameter | Description | Default |
|:----------|:------------|:-------:|
| `-SkipUpdates` | Skip Windows and winget updates | `false` |
| `-SkipCleanup` | Skip **all** cleanup (system, deep, developer, Docker/WSL, Visual Studio) | `false` |
| `-SkipRestore` | Skip system restore point creation | `false` |
| `-SkipDevCleanup` | Skip developer caches (npm, pip, etc.) | `false` |
| `-SkipDockerCleanup` | Skip Docker/WSL cleanup | `false` |
| `-SkipVSCleanup` | Skip Visual Studio cleanup | `false` |
| `-DisableTelemetry` | Disable Windows telemetry via Group Policy | `false` |
| `-ReportOnly` | **Dry run** - show what would be done | `false` |
| `-LogPath` | Custom log file path | Auto |
| `-ResultJsonPath` | Write a machine-readable run summary (JSON) for automation/CI | Off |

> `-SkipCleanup` turns off the whole cleanup group. Use the per-category flags (`-SkipDevCleanup`, `-SkipDockerCleanup`, `-SkipVSCleanup`) for finer control when you still want the system cleanup. The `-ResultJsonPath` schema is documented in **[docs/result-json.md](docs/result-json.md)**.

---

## 🎯 Recommended Profiles

| Profile | Command | Best For |
|:--------|:--------|:---------|
| **Preview** | `.\WinClean.ps1 -ReportOnly` | First run - see what will be cleaned without changes |
| **Safe** | `.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup` | Minimal risk - only temp files and caches |
| **Developer** | `.\WinClean.ps1` | Full cleanup - includes npm, pip, nuget, Docker, IDE caches |
| **Quick** | `.\WinClean.ps1 -SkipUpdates -SkipDevCleanup -SkipVSCleanup` | Fast - system cleanup only, no dev tools |
| **Updates Only** | `.\WinClean.ps1 -SkipCleanup` | Just Windows and app updates, no cleanup at all |

> 💡 **Tip:** Always run with `-ReportOnly` first to preview what will be cleaned.

---

## 🔧 Requirements

| Requirement | Version | Notes |
|:------------|:--------|:------|
| **Windows** | 11 | Tested on 23H2/24H2/25H2 (most features also work on Windows 10) |
| **PowerShell** | 7.1+ | [Download here](https://aka.ms/powershell) |
| **Rights** | Administrator | Required for system operations |

<details>
<summary>📦 Optional dependencies</summary>

| Component | Required For | Auto-installed |
|:----------|:-------------|:--------------:|
| PSWindowsUpdate | Windows updates | ✅ Yes |
| winget | App updates | ❌ Manual |
| Docker Desktop | Docker cleanup | ❌ Manual |
| WSL 2 | WSL optimization | ❌ Manual |

</details>

---

## 🛡️ Safety

WinClean is built to be safe to run on a working machine. The short version:

| Safety Feature | Description |
|:---------------|:------------|
| 🔄 **Restore Point** | Created before any changes (skip with `-SkipRestore`) |
| 🛡️ **Protected Paths** | `C:\Windows`, `C:\Program Files`, `C:\Users` and volume roots are never deleted |
| 📦 **Preserves Packages** | `node_modules`, `.nuget\packages`, virtualenvs, `vendor` are kept |
| 👁️ **Preview Mode** | `-ReportOnly` shows changes first |
| 🔒 **Fail-closed Install** | One-liners verify SHA256 against the release asset |
| 🧪 **VM-verified** | Every release is run end-to-end on real Windows 11 VMs (ru-RU and en-US) |

<details>
<summary>✅ Cleaned vs 🛡️ Preserved</summary>

| ✅ Cleaned | 🛡️ Preserved |
|:-----------|:-------------|
| `%TEMP%\*` | `Documents`, `Downloads` |
| Browser caches | Browser bookmarks, passwords |
| `npm-cache` | `node_modules` |
| `pip\Cache` | Virtual environments |
| `Composer\cache` | `vendor` |
| `NuGet\v3-cache` | `\.nuget\packages` |
| `\.gradle\build-cache` | `\.gradle\caches\modules` |

</details>

> Full trust and safety model, including Controlled Folder Access and the bootstrap verification: **[docs/safety.md](docs/safety.md)**.

---

## 📊 Execution Flow

```
┌────────────────────────────────────────────────────────────────┐
│                     WinClean v2.19                             │
├────────────────────────────────────────────────────────────────┤
│  PREPARATION                                                   │
│  ├─ ✓ Check Administrator Rights                               │
│  ├─ ✓ Check Pending Reboot                                     │
│  └─ ✓ Create System Restore Point                              │
├────────────────────────────────────────────────────────────────┤
│  UPDATES                                                       │
│  ├─ 🔄 Windows Updates (including drivers)                     │
│  └─ 🔄 Winget Application Updates                              │
├────────────────────────────────────────────────────────────────┤
│  CLEANUP                                                       │
│  ├─ 🗑️ Temporary Files & Browser Caches                        │
│  ├─ 🗑️ Developer Caches (npm, pip, nuget, gradle)              │
│  ├─ 🐳 Docker & WSL Optimization                               │
│  └─ 🛠️ Visual Studio & IDE Caches                              │
├────────────────────────────────────────────────────────────────┤
│  DEEP CLEANUP                                                  │
│  ├─ 🔧 DISM Component Cleanup                                  │
│  ├─ 💾 Disk Cleanup (23 registry handlers)                    │
│  ├─ 🚗 Driver Store (superseded packages)                     │
│  ├─ 🧹 Stale Kernel Dumps (older than 30 days)                │
│  └─ 📁 Windows.old Removal (with confirmation)                 │
├────────────────────────────────────────────────────────────────┤
│  PRIVACY (optional)                                            │
│  ├─ 🔒 Clear DNS Cache & History                               │
│  └─ ⚙️ Disable Telemetry (if -DisableTelemetry)                │
├────────────────────────────────────────────────────────────────┤
│  📊 DISK SPACE REPORT + SUMMARY                                │
└────────────────────────────────────────────────────────────────┘
```

> Each phase's outcome is recorded in the result JSON as **completed**, **skipped**, or **failed**, so an automated run can tell "everything ran" from "a phase threw". See **[docs/result-json.md](docs/result-json.md)**.

---

## 📝 Logging

Every run writes a detailed log to `%TEMP%\WinClean_<date>.log` with a timestamp, status (success / warning / error), freed space per category, and total time. Pass `-ResultJsonPath` for a machine-readable summary.

---

## 📚 Learn More

Deep-dive documentation lives in **[`docs/`](docs/)**:

| Page | What's inside |
|:-----|:--------------|
| [Safety model](docs/safety.md) | Restore points, protected paths, fail-closed bootstrap, Controlled Folder Access |
| [What is cleaned](docs/what-is-cleaned.md) | Exhaustive per-phase inventory: cleaned vs preserved |
| [Result JSON](docs/result-json.md) | `-ResultJsonPath` schema for automation and CI |
| [Troubleshooting](docs/troubleshooting.md) | Common problems and fixes |
| [FAQ](docs/faq.md) | Extended questions and answers |
| [Comparison](docs/comparison.md) | How WinClean compares to manual cleanup |
| [Release process](docs/release-process.md) | How releases are built and verified |

---

## ❓ FAQ

<details>
<summary><b>Is it safe to run WinClean?</b></summary>

Yes. WinClean creates a restore point before making changes and never touches protected system paths. Use `-ReportOnly` to preview changes first. More: [docs/safety.md](docs/safety.md).

</details>

<details>
<summary><b>Will it delete my installed programs or packages?</b></summary>

No. WinClean only cleans caches and temporary files. Installed programs, npm/NuGet packages, and user data remain untouched.

</details>

<details>
<summary><b>How often should I run it?</b></summary>

Monthly is a good default. Heavy developers or users with limited disk space may benefit from weekly runs.

</details>

<details>
<summary><b>Can I run it on Windows 10?</b></summary>

It is designed for Windows 11, but most features work on Windows 10 with PowerShell 7.1+.

</details>

More questions are answered in **[docs/faq.md](docs/faq.md)** and **[docs/troubleshooting.md](docs/troubleshooting.md)**.

---

## 🤝 Contributing & Community

Contributions are welcome. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the workflow, code style, and testing, and open a **[Discussion](https://github.com/bivlked/WinClean/discussions)** for questions, ideas, or to share a success story.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'feat: add some amazing feature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

### ⭐ Star this repo if you find it useful!

**[Report Bug](https://github.com/bivlked/WinClean/issues)** •
**[Request Feature](https://github.com/bivlked/WinClean/issues)** •
**[Discussions](https://github.com/bivlked/WinClean/discussions)** •
**[Changelog](CHANGELOG.md)**

Made with ❤️ for Windows users

</div>
