<div align="center">

# 🧹 WinClean

**Ultimate Windows 11 Maintenance Script**

[![PowerShell 7.1+](https://img.shields.io/badge/PowerShell-7.1%2B-blue?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/bivlked/WinClean/pulls)

*Automated system maintenance: updates, cleanup, and optimization in one script*

[Features](#-features) • [Quick Start](#-quick-start) • [Parameters](#-parameters) • [Examples](#-examples) • [Safety](#-safety)

</div>

---

## ✨ Features

### 🔄 System Updates
- **Windows Update** — all updates including drivers via PSWindowsUpdate
- **Microsoft Store apps** — automatic registration of Microsoft Update service
- **Winget packages** — updates all installed applications

### 🗑️ Smart Cleanup
- **Temporary files** — User Temp, Windows Temp, Local Temp
- **Browser caches** — Edge, Chrome, Firefox, Yandex, Opera, Brave (including profiles)
- **Windows caches** — Prefetch, Font Cache, Icon Cache, Thumbnail Cache
- **Windows Update cache** — SoftwareDistribution folder
- **Previous Windows** — Windows.old with confirmation prompt

### 👨‍💻 Developer Caches
- **npm / yarn / pnpm** — Node.js package managers
- **pip / Poetry / uv** — Python package managers
- **NuGet** — .NET package cache (metadata only, packages preserved)
- **Gradle** — build caches (dependencies preserved)
- **Composer** — PHP package manager

### 🐳 Docker & WSL
- **Docker** — unused images, stopped containers, build cache (`docker system prune`)
- **WSL2** — VHDX disk compaction via diskpart

### 🛠️ Visual Studio
- **Component cache** — outdated components cleanup
- **MEF cache** — Managed Extensibility Framework cache
- **Experimental Instances** — debug instances data

### 🔒 Privacy & Security
- **DNS cache** — flush DNS resolver cache
- **Run history** — RunMRU registry cleanup
- **Explorer history** — typed paths, search history
- **Recent documents** — Recent folder cleanup
- **Telemetry** *(optional)* — disable Windows telemetry via Group Policy

### ⚡ Performance
- **Parallel execution** — `ForEach-Object -Parallel` with throttling
- **Thread-safe stats** — `[hashtable]::Synchronized` for accurate metrics
- **Progress tracking** — real-time progress bar with current step

---

## 🚀 Quick Start

### One-Line Install & Run

```powershell
# Download and run (requires admin rights)
irm https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1 -OutFile "$env:TEMP\WinClean.ps1"; Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$env:TEMP\WinClean.ps1`""
```

### Manual Download

```powershell
# 1. Download the script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1" -OutFile "WinClean.ps1"

# 2. Run as Administrator
.\WinClean.ps1
```

### Clone Repository

```powershell
git clone https://github.com/bivlked/WinClean.git
cd WinClean
.\WinClean.ps1
```

---

## 📋 Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-SkipUpdates` | Skip Windows and winget updates | `$false` |
| `-SkipCleanup` | Skip all cleanup operations | `$false` |
| `-SkipRestore` | Skip system restore point creation | `$false` |
| `-SkipDevCleanup` | Skip developer caches (npm, pip, nuget) | `$false` |
| `-SkipDockerCleanup` | Skip Docker/WSL cleanup | `$false` |
| `-SkipVSCleanup` | Skip Visual Studio cleanup | `$false` |
| `-DisableTelemetry` | Disable Windows telemetry (Group Policy) | `$false` |
| `-ReportOnly` | Dry run — show what would be done | `$false` |
| `-LogPath` | Custom log file path | `$env:TEMP\WinClean_<date>.log` |

---

## 💡 Examples

### Full Maintenance (Default)
```powershell
.\WinClean.ps1
```
Runs all updates and cleanup operations.

### Cleanup Only (No Updates)
```powershell
.\WinClean.ps1 -SkipUpdates
```
Skips Windows/winget updates, runs cleanup only.

### Preview Mode (Dry Run)
```powershell
.\WinClean.ps1 -ReportOnly
```
Shows what would be cleaned without making changes.

### Quick Clean (Skip Heavy Operations)
```powershell
.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup -SkipVSCleanup
```
Fast cleanup: temp files, browser caches, developer caches.

### Full Privacy Mode
```powershell
.\WinClean.ps1 -DisableTelemetry
```
Complete maintenance plus Windows telemetry disabled.

### Custom Log Location
```powershell
.\WinClean.ps1 -LogPath "C:\Logs\maintenance.log"
```

---

## 🔧 Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Windows** | 11 | Tested on 23H2/24H2 |
| **PowerShell** | 7.1+ | [Install PowerShell 7](https://aka.ms/powershell) |
| **Rights** | Administrator | Required for system operations |

### Optional Dependencies

| Component | Required For |
|-----------|--------------|
| [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) | Windows updates (auto-installed) |
| [winget](https://aka.ms/getwinget) | Application updates |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Docker cleanup |
| [WSL 2](https://aka.ms/wsl2) | WSL disk compaction |

---

## 🛡️ Safety

### What WinClean Does

✅ Creates **restore point** before any changes
✅ **Preserves** installed packages (NuGet, Maven, npm)
✅ **Asks confirmation** before deleting Windows.old
✅ Uses **try/finally** to ensure services restart
✅ Validates paths against **protected list**
✅ Supports **ReportOnly** mode for preview

### Protected Paths

The following paths are never deleted:
- `$env:SystemRoot` (Windows folder)
- `$env:ProgramFiles` and `${env:ProgramFiles(x86)}`
- `$env:USERPROFILE` (User profile folder)
- `$env:SystemDrive\Users`

### What Gets Cleaned (Safe)

| Category | Items |
|----------|-------|
| Caches | Temporary files, browser caches, font cache |
| Build | Gradle build-cache, webpack cache |
| Metadata | NuGet v3-cache, pip http-cache |
| Logs | Old Windows Update logs, VS telemetry |

### What is Preserved (Never Deleted)

| Category | Items |
|----------|-------|
| Packages | `~\.nuget\packages`, `~\.m2\repository` |
| Dependencies | `node_modules`, `~\.gradle\caches\modules-*` |
| User Data | Documents, Downloads, Desktop |

---

## 📊 Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    WinClean Execution                       │
├─────────────────────────────────────────────────────────────┤
│  1. ✓ Check Administrator Rights                           │
│  2. ✓ Check Pending Reboot                                  │
│  3. ✓ Create System Restore Point                          │
├─────────────────────────────────────────────────────────────┤
│  4. 🔄 Windows Updates (drivers included)                   │
│  5. 🔄 Winget Application Updates                          │
├─────────────────────────────────────────────────────────────┤
│  6. 🗑️ System Cleanup (temp, caches, browsers)              │
│  7. 🗑️ Developer Caches (npm, pip, nuget, gradle)           │
│  8. 🐳 Docker/WSL Cleanup                                   │
│  9. 🛠️ Visual Studio Cleanup                                │
├─────────────────────────────────────────────────────────────┤
│ 10. 🔒 Privacy Cleanup (DNS, history)                       │
│ 11. ⚙️ Telemetry Settings (if -DisableTelemetry)            │
├─────────────────────────────────────────────────────────────┤
│ 12. 📊 Summary Report                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Logging

Every run creates a detailed log file:

```
%TEMP%\WinClean_20250115_143052.log
```

Log includes:
- Timestamp for each operation
- Success/Warning/Error status
- Freed space per category
- Total execution time

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

**⭐ If you find this useful, please give it a star!**

Made with ❤️ for Windows users

</div>
