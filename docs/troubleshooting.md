# Troubleshooting

Common problems when running WinClean and how to resolve them. For the safety model see [safety.md](safety.md); for the machine-readable run summary see [result-json.md](result-json.md).

---

## Cleanup frees almost nothing (Controlled Folder Access is enabled)

Windows Defender's Controlled Folder Access blocks writes and deletions inside protected folders **without raising an error**. Every delete call reports success, so the log looks fine while nothing is actually freed.

WinClean detects this up front and warns. The result JSON field `ControlledFolderAccess` will read `enabled`, which means the freed-space figures are understated.

**Fix:** add `pwsh.exe` to the Controlled Folder Access allowed apps list:

- Windows Security -> Virus & threat protection -> Ransomware protection -> Manage Controlled folder access -> Allow an app through Controlled folder access.
- Add the PowerShell 7 executable (`pwsh.exe`), then re-run WinClean.

If the check itself cannot run (third-party antivirus, stripped image, broken WMI), the field reads `unknown` and the figures are unverified rather than confirmed good.

---

## App updates are skipped (winget not found)

If `winget` is not installed, the application-update phase is skipped and the run continues. Windows updates (via PSWindowsUpdate) are unaffected.

**Fix:** install **App Installer** from the Microsoft Store, or bootstrap winget, then re-run. Note that the app-update count in the summary is what winget **offered**, not a confirmed install count (see [FAQ](faq.md) and [result-json.md](result-json.md)).

---

## Windows updates are skipped (PowerShell Gallery unreachable)

WinClean installs the `PSWindowsUpdate` module from the PowerShell Gallery. If the Gallery is unreachable (offline, proxy, TLS), the module cannot install and the Windows-update phase is skipped. The rest of the run continues normally.

This path is guarded by timeouts, so a stuck Gallery cannot hang the whole run. You will see a clear message with manual-install instructions.

**Fix:** restore connectivity, or install the module by hand once:

```powershell
Install-Module PSWindowsUpdate -Force -Scope CurrentUser
```

---

## "This script requires administrator" or "requires PowerShell 7.1+"

WinClean declares `#Requires -RunAsAdministrator` and `#Requires -Version 7.1`. It will refuse to run in a non-elevated shell or on Windows PowerShell 5.1.

**Fix:**

- Install PowerShell 7: `winget install --id Microsoft.PowerShell`
- Open an elevated PowerShell 7 terminal: press `Win+X`, then choose **Terminal (Admin)**, and make sure the tab is **PowerShell 7** (`pwsh`), not Windows PowerShell.

---

## The one-liner refuses to run

`get.ps1` and `install.ps1` are **fail-closed**. They download WinClean from the latest GitHub Release and verify its SHA256 against the published `WinClean.ps1.sha256` asset. The run is aborted if:

- the release does not publish **both** `WinClean.ps1` and `WinClean.ps1.sha256`, or
- the downloaded file's hash does not match the published hash exactly.

There is no fallback to a mutable branch. This is intentional: running unverified code with administrator rights is worse than not running at all.

**What to do:** this usually means a release was published incompletely or a download was corrupted. Wait for the release to be fixed, or download `WinClean.ps1` manually from the [Releases page](https://github.com/bivlked/WinClean/releases) and run it yourself.

---

## Where is the log?

Every run writes a timestamped log:

```
%TEMP%\WinClean_<date>.log
```

Open the most recent one and search for `[WARNING]` and `[ERROR]` lines. Each entry is timestamped, and freed space is reported per category. You can also pass `-LogPath` to write it somewhere specific.

---

## Reading the machine-readable result

For automation or CI, pass `-ResultJsonPath` to get a JSON summary of the run (freed bytes, warnings, errors, per-phase status, and more). The full schema, including the tri-state phase status, is documented in [result-json.md](result-json.md).

---

## Something went wrong, how do I roll back?

WinClean creates a **System Restore Point** at the start of every run (unless `-SkipRestore` is set or you are in `-ReportOnly`). If a change caused a problem, roll back to that restore point:

- `Win+R` -> `rstrui.exe` -> choose the restore point named `WinClean <date time>`.

Then check the log file to see exactly what was changed.

---

## Кратко (RU)

- **Очистка почти ничего не освобождает:** включён Controlled Folder Access - добавьте `pwsh.exe` в список разрешённых приложений. В JSON поле `ControlledFolderAccess` = `enabled`.
- **Обновления приложений пропущены:** не найден `winget` - установите App Installer из Microsoft Store.
- **Обновления Windows пропущены:** недоступен PowerShell Gallery - модуль `PSWindowsUpdate` не ставится, прогон продолжается.
- **Нужны права администратора и PowerShell 7.1+:** откройте `Win+X` -> Терминал (Администратор), вкладка PowerShell 7.
- **One-liner не запускается:** это fail-closed - при отсутствии ассета или несовпадении SHA256 запуск отменяется намеренно; скачайте вручную со страницы Releases.
- **Откат:** используйте точку восстановления `WinClean <дата>` (`rstrui.exe`).

Полная документация на русском: [README_RU.md](../README_RU.md).
