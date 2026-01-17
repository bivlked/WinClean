<div align="center">

<img src="https://raw.githubusercontent.com/bivlked/WinClean/main/assets/logo.svg" alt="WinClean Logo" width="120" height="120">

# WinClean

### Ultimate Windows 11 Maintenance Script

[![Version](https://img.shields.io/badge/version-2.11-blue.svg)](https://github.com/bivlked/WinClean/releases)
[![PSGallery](https://img.shields.io/powershellgallery/v/WinClean?label=PSGallery&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/WinClean)
[![CI](https://github.com/bivlked/WinClean/actions/workflows/ci.yml/badge.svg)](https://github.com/bivlked/WinClean/actions/workflows/ci.yml)
[![PowerShell 7.1+](https://img.shields.io/badge/PowerShell-7.1%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Automated system maintenance: updates, cleanup, and optimization in one script**

[English](README.md) | [Русский](README_RU.md)

---

[Why WinClean?](#-why-winclean) •
[Features](#-features) •
[Quick Start](#-quick-start) •
[Parameters](#-parameters) •
[Safety](#%EF%B8%8F-safety) •
[FAQ](#-faq)

</div>

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
- **Safe by design** — protected paths

</td>
</tr>
</table>

> 💡 **Average cleanup result:** 5-20 GB freed, depending on system usage

---

## ✨ Features

<table>
<tr>
<td width="33%" valign="top">

### 🔄 Updates
- Windows Update (+ drivers)
- Microsoft Store apps
- Winget packages
- PSWindowsUpdate module

</td>
<td width="33%" valign="top">

### 🗑️ Cleanup
- Temp files (3 locations)
- Browser caches (6 browsers)
- Windows caches (8 types)
- Recycle Bin emptying
- Windows.old removal

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

---

## 🚀 Quick Start

### 📦 Install from PowerShell Gallery (Recommended)

```powershell
Install-Script -Name WinClean -Scope CurrentUser
```

Then run as Administrator:
```powershell
WinClean.ps1
```

<details>
<summary>📥 Alternative installation methods</summary>

### ⚡ One-Line Download & Run

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1 -OutFile "$env:TEMP\WinClean.ps1"; Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$env:TEMP\WinClean.ps1`""
```

### Manual Download

```powershell
# Download
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1" -OutFile "WinClean.ps1"

# Run as Administrator
.\WinClean.ps1
```

### Clone Repository

```powershell
git clone https://github.com/bivlked/WinClean.git
cd WinClean
.\WinClean.ps1
```

</details>

---

## 📋 Parameters

| Parameter | Description | Default |
|:----------|:------------|:-------:|
| `-SkipUpdates` | Skip Windows and winget updates | `false` |
| `-SkipCleanup` | Skip all cleanup operations | `false` |
| `-SkipRestore` | Skip system restore point creation | `false` |
| `-SkipDevCleanup` | Skip developer caches (npm, pip, etc.) | `false` |
| `-SkipDockerCleanup` | Skip Docker/WSL cleanup | `false` |
| `-SkipVSCleanup` | Skip Visual Studio cleanup | `false` |
| `-DisableTelemetry` | Disable Windows telemetry via Group Policy | `false` |
| `-ReportOnly` | **Dry run** — show what would be done | `false` |
| `-LogPath` | Custom log file path | Auto |

---

## 💡 Usage Examples

<table>
<tr>
<td width="50%">

### Full Maintenance
```powershell
.\WinClean.ps1
```
All updates + all cleanup

</td>
<td width="50%">

### Cleanup Only
```powershell
.\WinClean.ps1 -SkipUpdates
```
No updates, just cleanup

</td>
</tr>
<tr>
<td width="50%">

### Preview Mode
```powershell
.\WinClean.ps1 -ReportOnly
```
See what would happen

</td>
<td width="50%">

### Quick Clean
```powershell
.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup
```
Fast cleanup only

</td>
</tr>
</table>

---

## 🎯 Recommended Profiles

Choose the right profile for your needs:

| Profile | Command | Best For |
|:--------|:--------|:---------|
| **Preview** | `.\WinClean.ps1 -ReportOnly` | First run — see what will be cleaned without changes |
| **Safe** | `.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup` | Minimal risk — only temp files and caches |
| **Developer** | `.\WinClean.ps1` | Full cleanup — includes npm, pip, nuget, Docker, IDE caches |
| **Quick** | `.\WinClean.ps1 -SkipUpdates -SkipDevCleanup -SkipVSCleanup` | Fast — system cleanup only, no dev tools |
| **Updates Only** | `.\WinClean.ps1 -SkipCleanup` | Just Windows and app updates |

> 💡 **Tip:** Always run with `-ReportOnly` first to preview what will be cleaned!

---

## 🔧 Requirements

| Requirement | Version | Notes |
|:------------|:--------|:------|
| **Windows** | 11 | Tested on 23H2/24H2/25H2 |
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

### ✅ What WinClean Does

| Safety Feature | Description |
|:---------------|:------------|
| 🔄 **Restore Point** | Created before any changes |
| 🛡️ **Protected Paths** | System folders never touched |
| 📦 **Preserves Packages** | NuGet, npm, Maven packages kept |
| ❓ **Confirmation** | Windows.old asks before deletion |
| 🔧 **Service Recovery** | Uses try/finally for services |
| 👁️ **Preview Mode** | `-ReportOnly` shows changes first |

### 🚫 Protected Paths (Never Deleted)

```
C:\Windows\
C:\Program Files\
C:\Program Files (x86)\
C:\Users\
C:\Users\YourName\
```

### ✅ Safe to Clean vs 🛡️ Preserved

| ✅ Cleaned | 🛡️ Preserved |
|:-----------|:-------------|
| `%TEMP%\*` | `Documents`, `Downloads` |
| Browser caches | Browser bookmarks, passwords |
| `npm-cache` | `node_modules` |
| `pip\Cache` | Virtual environments |
| `Composer\cache` | `vendor` |
| `NuGet\v3-cache` | `\.nuget\packages` |
| `\.gradle\build-cache` | `\.gradle\caches\modules` |

---

## 📊 Execution Flow

```
┌────────────────────────────────────────────────────────────────┐
│                     WinClean v2.11                              │
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
│  ├─ 💾 Disk Cleanup (20+ categories)                           │
│  └─ 📁 Windows.old Removal (with confirmation)                 │
├────────────────────────────────────────────────────────────────┤
│  PRIVACY (optional)                                            │
│  ├─ 🔒 Clear DNS Cache & History                               │
│  └─ ⚙️ Disable Telemetry (if -DisableTelemetry)                │
├────────────────────────────────────────────────────────────────┤
│  📊 SUMMARY REPORT                                             │
└────────────────────────────────────────────────────────────────┘
```

---

## 📝 Logging

Every run creates a detailed log:

```
%TEMP%\WinClean_20260117_143052.log
```

**Log contents:**
- ⏰ Timestamp for each operation
- ✅ Success / ⚠️ Warning / ❌ Error status
- 📊 Freed space per category
- ⏱️ Total execution time

---

## ❓ FAQ

<details>
<summary><b>Is it safe to run WinClean?</b></summary>

Yes! WinClean creates a restore point before making changes and never touches protected system paths. Use `-ReportOnly` to preview changes first.

</details>

<details>
<summary><b>Will it delete my installed programs?</b></summary>

No. WinClean only cleans caches and temporary files. Your installed programs, npm packages, NuGet packages, and user data remain untouched.

</details>

<details>
<summary><b>How often should I run it?</b></summary>

Monthly is recommended. Heavy developers or users with limited disk space may benefit from weekly runs.

</details>

<details>
<summary><b>Why does it need Administrator rights?</b></summary>

Required for: Windows Update, system cache cleanup, DISM operations, service management, and creating restore points.

</details>

<details>
<summary><b>Can I run it on Windows 10?</b></summary>

Primarily designed for Windows 11, but most features work on Windows 10 with PowerShell 7.1+.

</details>

<details>
<summary><b>What if something goes wrong?</b></summary>

Use the restore point created at the start to roll back. Check the log file for details about what was changed.

</details>

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

### ⭐ Star this repo if you find it useful!

**[Report Bug](https://github.com/bivlked/WinClean/issues)** •
**[Request Feature](https://github.com/bivlked/WinClean/issues)** •
**[Changelog](CHANGELOG.md)**

Made with ❤️ for Windows users

</div>
