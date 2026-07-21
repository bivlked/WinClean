# Trust & Safety Model

WinClean runs elevated and deletes files, so its safety guarantees are the most important thing to understand before you use it. This page explains every mechanism that protects your system and your data, and is honest about what each one does and does not do.

If you only read one thing: run `.\WinClean.ps1 -ReportOnly` first. It shows exactly what a real run would touch and changes nothing.

---

## System restore point

Before making any changes, WinClean creates a System Restore point (`New-SystemRestorePoint`). If cleanup or an update ever leaves the system in a state you dislike, you can roll back to the point taken at the start of the run.

- `-SkipRestore` disables restore-point creation for that run.
- In `-ReportOnly` mode no restore point is created, because the preview changes nothing.
- Restore points depend on System Protection being enabled for the drive. WinClean logs when a point could not be created (for example, the 24-hour system frequency limit) so you are never left believing a rollback point exists when it does not.

## Protected paths (never deleted)

A fixed allowlist of critical locations is refused by every delete path, regardless of what a cleanup routine is asked to remove (`$script:ProtectedPaths`):

```
C:\Windows\
C:\Windows\System32\
C:\Program Files\
C:\Program Files (x86)\
C:\Users\
C:\Users\<name>\
```

Volume roots (for example `C:\`) are protected explicitly as well. Path protection is not a naive string match: it normalizes short (8.3) names such as `PROGRA~1` and resolves `..` traversal before comparing, so a path that only looks different on the surface cannot slip past the check.

## Preview mode (`-ReportOnly`)

`-ReportOnly` performs a dry run: it walks the same logic a real run would, reports what would be cleaned and how much space it would free, and makes no changes. It installs nothing, deletes nothing, and creates no restore point.

`-ReportOnly` is a preview of behavior. It is **not** an integrity or authenticity check of the script itself. For that, see "Fail-closed bootstrap" below.

## Controlled Folder Access awareness

Windows Defender's Controlled Folder Access (CFA), when enabled, silently blocks deletions inside protected folders while every delete call still reports success. Left undetected, this makes cleanup look complete while freeing nothing.

WinClean checks the CFA state up front and warns when it is enabled, so the numbers in the summary are not quietly misleading. The result JSON records the state in `ControlledFolderAccess`:

- `disabled` - deletions are not being blocked by CFA.
- `enabled` - some deletions may have been blocked; freed-space figures are understated.
- `unknown` - the check itself failed (for example, Defender cmdlets unavailable), so the figures are unverified rather than confirmed good.

## Fail-closed bootstrap (`get.ps1` / `install.ps1`)

The one-line install scripts download `WinClean.ps1` from the **latest GitHub Release** and verify its SHA256 against the published `WinClean.ps1.sha256` release asset before running anything.

- Both assets are mandatory. A release that publishes the script without its hash asset is refused, rather than silently skipping verification.
- There is no fallback to a mutable branch such as `main`: tags and branches move, release assets do not.
- The comparison is exact (ordinal, case-insensitive), never a wildcard match, so a stray `*` in a hash file cannot "verify" arbitrary content.
- The download host is validated against an exact allowlist (`github.com`).

If the hash does not match, or an asset is missing, the bootstrap aborts before executing a single line. Running unverified code elevated is worse than not running it at all.

## Protected install location

`install.ps1` installs to `%ProgramFiles%\WinClean`, a directory that requires administrator rights to modify. The desktop shortcut it creates always launches elevated, and because its target lives in an admin-only location, a non-admin process cannot hijack the shortcut to run something else with elevation.

## Explicit parameter binding

The script declares `[CmdletBinding(PositionalBinding = $false)]`. A stray positional argument therefore fails loudly instead of silently binding to a parameter such as `-LogPath`. This exists to prevent the exact class of accident where an argument meant as a flag is swallowed as a value and an intended dry run becomes a real cleanup.

## VM-verified releases

Every release is run end-to-end on real Windows 11 virtual machines in both `ru-RU` and `en-US` locales before it is published. This catches locale-dependent parsing bugs, console-frame misalignment, and real-cleanup regressions that unit tests alone cannot.

---

## Кратко (RU)

- Перед изменениями создаётся точка восстановления (кроме `-ReportOnly` и `-SkipRestore`).
- Защищённые системные пути никогда не удаляются; проверка учитывает короткие имена и `..`.
- `-ReportOnly` показывает планируемые действия и ничего не меняет (это предпросмотр, а не проверка подлинности скрипта).
- `get.ps1`/`install.ps1` скачивают скрипт из последнего GitHub Release и fail-closed сверяют SHA256; при несовпадении или отсутствии ассета запуск прерывается.
- Установка в `%ProgramFiles%\WinClean` (только админ), явное связывание параметров, каждый релиз проверяется на реальных VM (ru-RU и en-US).

Назад к обзору: [README_RU.md](../README_RU.md).
