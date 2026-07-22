# Trust & Safety Model

WinClean runs elevated and deletes files, so its safety guarantees are the most important thing to understand before you use it. This page explains every mechanism that protects your system and your data, and is honest about what each one does and does not do.

If you only read one thing: run `.\WinClean.ps1 -ReportOnly` first. It shows what a real run would touch and makes no maintenance changes.

---

## System restore point

WinClean **attempts** to create a System Restore point (`New-SystemRestorePoint`) before the maintenance phases. If it succeeds, you can roll back to the point taken near the start of the run. Creating it is a safety net, not a hard gate: if it fails, the run logs a warning and continues.

- `-SkipRestore` disables restore-point creation for that run.
- In `-ReportOnly` mode no restore point is created.
- A couple of internal steps (recovering from an interrupted previous run, and the script-update check) run before the restore point, so it is "before the maintenance phases", not literally before every line of the run.
- Restore points depend on System Protection being enabled for the drive. WinClean temporarily lifts the 24-hour creation frequency limit so a same-day second run can still get a point, and it logs when a point could not be created, so you are never left believing a rollback point exists when it does not.

## Protected paths (never bulk-deleted)

A fixed allowlist of critical locations (`$script:ProtectedPaths`) is refused as a bulk-cleanup target: the folder-cleanup routine that walks and empties a directory tree will not accept any of these roots. This guards against a mistargeted cleanup wiping a system root. It is not a global interceptor on every single delete call in the script - a few paths (browser caches, the Recycle Bin, privacy history, Windows.old) are removed by their own dedicated, tightly-scoped code rather than routed through this list.

```
C:\Windows\
C:\Windows\System32\
C:\Program Files\
C:\Program Files (x86)\
C:\Users\
C:\Users\<name>\
```

Volume roots (for example `C:\`) are protected explicitly as well. Path protection is not a naive string match: it normalizes short (8.3) names such as `PROGRA~1` and resolves `..` traversal before comparing, so a path that only looks different on the surface cannot slip past the check.

Since v2.20 the check also follows links. Path normalization works on text and does not resolve reparse points, so a junction whose visible path looked harmless while pointing at a protected root used to pass the guard, and enumerating that junction lists the target's contents. A cleanup root is now resolved to its final target before the rules are applied, and a link that cannot be resolved is refused rather than guessed at. Only the root needs this: a link found deeper inside a tree is already harmless, because the recursive walk does not descend into reparse points and deleting a junction removes the link and leaves its target intact.

## Preview mode (`-ReportOnly`)

`-ReportOnly` performs a dry run: it walks the same logic a real run would and reports what would be cleaned and how much space it would free. It makes no maintenance changes - it installs nothing, deletes none of the caches or files it would clean, and creates no restore point. It does still write its own log file (and the result JSON if you passed `-ResultJsonPath`, removing any pre-existing one first on a best-effort basis), set the process TLS version, and perform the read-only update and connectivity checks unless you also pass `-SkipUpdates`.

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
- There is no fallback to a mutable branch such as `main` for the downloaded script. Release assets are version-associated, though a maintainer can still replace them (for example with `gh release upload --clobber`), so this check detects corruption and inconsistent packaging - not a compromised repository or release account.
- The comparison is exact (ordinal, case-insensitive), never a wildcard match, so a stray `*` in a hash file cannot "verify" arbitrary content.
- The download host is validated against an exact allowlist (`github.com`).

If the hash does not match, or an asset is missing, the bootstrap aborts before executing a single line of the downloaded `WinClean.ps1`. (The small `get.ps1`/`install.ps1` bootstrap that you invoke with `irm ... | iex` is itself fetched from `main` and is short enough to read before you run it.) Running unverified code elevated is worse than not running it at all.

## Protected install location

`install.ps1` installs to `%ProgramFiles%\WinClean`, a directory that requires administrator rights to modify. The desktop shortcut it creates always launches elevated, and because its target script lives in an admin-only location, a non-admin process cannot swap the *installed script* for something else that would then run elevated. (The `.lnk` file itself sits on the user-writable desktop, so treat the Program Files install path as the integrity boundary, not the shortcut.)

## Explicit parameter binding

The script declares `[CmdletBinding(PositionalBinding = $false)]`. A stray positional argument therefore fails loudly instead of silently binding to a parameter such as `-LogPath`. This exists to prevent the exact class of accident where an argument meant as a flag is swallowed as a value and an intended dry run becomes a real cleanup.

## VM-verified releases

Every release is run end-to-end on real Windows 11 virtual machines in both `ru-RU` and `en-US` locales before it is published. This catches locale-dependent parsing bugs, console-frame misalignment, and real-cleanup regressions that unit tests alone cannot.

---

## Кратко (RU)

- Точка восстановления **создаётся по возможности** перед фазами обслуживания; при неудаче пишется предупреждение и прогон продолжается (кроме `-ReportOnly` и `-SkipRestore`).
- Корни защищённых системных путей не принимаются как цель массовой очистки; проверка учитывает короткие имена и `..`.
- `-ReportOnly` показывает планируемые действия и не делает изменений в очистке/обновлениях (пишет свой лог/result-файл и делает read-only проверки; это предпросмотр, а не проверка подлинности скрипта).
- `get.ps1`/`install.ps1` скачивают скрипт из последнего GitHub Release и fail-closed сверяют SHA256; при несовпадении или отсутствии ассета запуск прерывается (ассеты релиза мейнтейнер может заменить, это проверка от порчи, а не от компрометации аккаунта).
- Установка в `%ProgramFiles%\WinClean` (только админ), явное связывание параметров, каждый релиз проверяется на реальных VM (ru-RU и en-US).

Назад к обзору: [README_RU.md](../README_RU.md).
