# How WinClean compares

An honest look at where WinClean fits, versus doing maintenance by hand and versus generic one-click "PC cleaners". The goal here is to help you decide whether it is the right tool, not to sell it.

---

## Versus cleaning up by hand

Manual maintenance works, but it is easy to forget a step and easy to make a mistake. WinClean runs the same steps in one command, in a consistent order, with a restore point and a log.

| | By hand | WinClean |
|:--|:--|:--|
| Windows Update | Open Settings, wait, repeat | One phase, plus drivers |
| Browser caches | Open each browser, each profile | Seven browsers, multiple profiles, automatically |
| Dev tool caches | Remember each cache path | npm, pip, NuGet, Gradle, Cargo, Go, and more |
| Docker / WSL | Rarely done | Prune plus VHDX compaction |
| Disk Cleanup / DISM | Separate tools | Included, with before/after measurement |
| Safety | Hope you did not delete the wrong thing | Restore point, protected paths, dry run |
| Record of what happened | None | Timestamped log plus optional JSON summary |

## Versus generic one-click cleaners

Generic cleaners tend to optimize for a big "space freed" number and touch things a maintenance tool should leave alone. WinClean is deliberately narrower and more conservative.

- **Safety by design.** A System Restore Point is created before changes. A fixed set of system paths is never deleted, and path protection normalizes short names and `..` traversal. `-ReportOnly` previews every action. The one-command installers are fail-closed and verify a SHA256 hash before running anything.
- **Honest reporting.** WinClean does not inflate results. Freed space is measured, not estimated from a category list. Operations that quietly do nothing say so instead of logging success. The optional result JSON reports each phase as Completed, Skipped, or Failed, and reports app updates as the number winget **offered** rather than a confirmed install count.
- **Developer-tool awareness.** It cleans the caches developers actually accumulate (npm, pip, NuGet, Gradle, Cargo, Go, Docker, WSL, Visual Studio, VS Code, JetBrains) while preserving the package stores and project artifacts those tools depend on (`node_modules`, virtual environments, `vendor`, `.nuget\packages`). Generic cleaners usually miss the caches and sometimes delete the artifacts.
- **Verifiable.** WinClean is a single open-source PowerShell script under the MIT license. Every release is run end-to-end on real Windows 11 VMs (ru-RU and en-US) and is covered by 300+ automated tests. You can read exactly what it does before running it.

## Where WinClean is not the right tool

- It is **not** a real-time or scheduled background cleaner. It runs when you run it.
- It is **not** a registry "optimizer" or a tune-up suite. It does not promise speed gains from registry edits; the one registry-adjacent action is optional telemetry disabling behind `-DisableTelemetry`.
- It is **Windows-11-first.** It works on much of Windows 10 with PowerShell 7.1+, but it is designed and verified for Windows 11.
- It does not uninstall applications or manage startup items.

If you want a conservative, transparent, developer-aware maintenance script that you can audit and roll back, WinClean fits. If you want an always-on cleaner or a registry tuner, it is not that.
