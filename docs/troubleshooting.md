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

If `winget` is not installed, the app half of the Updates phase is skipped and the run continues. Windows updates (via PSWindowsUpdate) are unaffected.

This is reported as a **warning**, and the run can still finish with **exit code 0**. Before v2.21 it was an error, and since the exit code is derived from the error count alone, every run on a machine without App Installer ended with code 1 even though all nine phases completed - which any scheduler or CI job reads as a failed run. A missing optional third-party tool is a property of the machine, not a failure of the run, the same way a machine without Docker is a normal machine here. A `winget` that **is** present and then fails is still reported, at a severity that follows whether the run can safely carry on: the upgrade check failing outright or an unhandled error is an error, while a stale package source, a timeout or a partly failed upgrade batch is a warning.

A machine with **no internet connection** never reaches the winget check at all: both halves of the Updates phase stop earlier, on the same connectivity check. Since v2.21 that branch is also a warning rather than an error, for the same reason - a laptop running maintenance away from the network otherwise reported failure on every run, however completely the cleanup succeeded. The result JSON records `AppUpdatesStatus: "skipped-offline"`, which covers the Windows half too.

**Fix:** install **App Installer** from the Microsoft Store, or bootstrap winget, then re-run. Note that the app-update count in the summary is what winget **offered**, not a confirmed install count (see [FAQ](faq.md) and [result-json.md](result-json.md)).

---

## "Update complete" but the version never changes

Symptom: WinClean announces an update, reports success, asks you to run it again - and the next run shows the same old version. Forever.

Cause: **two installations on one machine**, which is an ordinary situation rather than an exotic one. `install.ps1` puts a copy in `%ProgramFiles%\WinClean` (this is what the desktop shortcut starts), while an older `Install-Script` copy may still sit in `Documents\PowerShell\Scripts`. Up to v2.20 WinClean asked only whether a Gallery copy existed **somewhere**, then acted as if the answer had been "the file you are running is that copy". `Update-Script` dutifully updated the copy in Documents, and the shortcut kept starting the untouched one.

Since v2.21 the check compares the **running file** with the Gallery install location and offers a self-update only when they are the same file. Every other copy is told the method that actually applies to it (see [Updating an existing installation](../README.md#-updating-an-existing-installation)). An update that reports success is also verified against the version on disk afterwards, so a provider that silently changes nothing is reported instead of being announced as complete.

**Fix on an affected machine:** update the copy the shortcut points at by re-running `install.ps1` elevated, and remove the abandoned Gallery copy if you no longer use it:

**Step 1 - find out which copies exist and which one you actually run.** Either provider may report an install performed by the other, so ask both; whichever module is absent simply reports an unknown command, which is expected.

```powershell
Get-InstalledScript -Name WinClean -ErrorAction SilentlyContinue |
    Select-Object Version, InstalledLocation
Get-PSResource -Name WinClean -ErrorAction SilentlyContinue |
    Where-Object { $_.Type -eq 'Script' } | Select-Object Version, InstalledLocation
Get-Item "$env:ProgramFiles\WinClean\WinClean.ps1" -ErrorAction SilentlyContinue
```

The copy you run is the one your shortcut points at (right-click the shortcut -> Properties -> Target). WinClean also prints that path itself, but only in the two cases where telling the installations apart is the point: several Gallery installs at once, and an update that reported success without changing the running file.

**Step 2 - remove only a copy whose location is *not* the one you run.** `AllUsers` and `CurrentUser` installs can coexist, and an unscoped uninstall is not guaranteed to pick the one you meant, so pin it to the version you saw at the location you want gone:

```powershell
Uninstall-Script -Name WinClean -RequiredVersion <version at that location>       # PowerShellGet
Uninstall-PSResource -Name WinClean -Version <version at that location>           # PSResourceGet
```

If two installs report the **same** version at different locations, `Uninstall-Script` cannot name one of them (it has no `-Scope`). `Uninstall-PSResource` does take `-Scope`, so it can, provided PSResourceGet performed that install. When in doubt do not guess: update the copy you run by **replacing that exact file** with the script asset from the [latest release](https://github.com/bivlked/WinClean/releases/latest), and remove the other installation's folder only once you have confirmed it is not the path you launch. Removing an `AllUsers` install needs an elevated session, and neither command touches the `%ProgramFiles%\WinClean` copy at all - that one is not a Gallery installation and is replaced by re-running `install.ps1`.

### What WinClean does in each of these states

The advice you see depends on which copy is running, so the two situations above behave differently:

- **The running copy is the `%ProgramFiles%\WinClean` one** (the usual case for the desktop shortcut). It was never Gallery-managed, so there is no self-update to decline: WinClean names the installer as the way to update it. Removing the stray Gallery copy does not change this - re-running `install.ps1` is the update path for this copy, by design.
- **The running copy is one of several Gallery installs.** Here WinClean declines to update itself rather than modifying a copy at random, prints the path it is running from, and points at the manual replacement above. It keeps declining while more than one Gallery install remains; resolving the duplicate is what restores the automatic update.

---

## The same application is offered for update on every single run

WinClean asks `winget` what can be upgraded and then asks it to upgrade. When the same package keeps appearing run after run, the loop is almost always outside WinClean. There are two distinct causes, and they need different answers.

### Cause 1: the package is installed for the current user, and WinClean runs elevated

WinClean requires administrator rights, and `winget` refuses to manage **user-scope** packages from an elevated process:

```
The package installed for user scope cannot be uninstalled when running with administrator privileges.
```

An upgrade replaces the installed package, so it hits the same wall. Such packages will be offered, fail, and be offered again on the next run, forever. WinClean reports the failure honestly, but only as a warning that some upgrades failed: `winget upgrade --all` runs as one batch and returns a single exit code, so the message cannot name the package. It cannot fix it either, because a run cannot drop its own privileges half way through.

**Fix:** upgrade those packages yourself from a **normal, non-elevated** PowerShell window:

```powershell
winget upgrade --id <PackageId>
```

### Cause 2: the package's own installer records the wrong version

`winget` decides whether an upgrade exists by reading `DisplayVersion` from the package's uninstall entry in the registry, **not** by looking at the installed executable. If an installer writes fresh files but records a stale version in its own entry, the loop is permanent: the registry says 1.14.1, winget offers 1.14.7, the installer places 1.14.7 and writes 1.14.1 again.

**Diagnosis** (read-only, run in any PowerShell window):

```powershell
# what winget reads
Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
              'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
    ForEach-Object { Get-ItemProperty $_.PSPath } |
    Where-Object DisplayName -like '*<AppName>*' |
    Select-Object DisplayName, DisplayVersion, InstallLocation

# what is actually installed
(Get-Item '<InstallLocation>\<App>.exe').VersionInfo.FileVersion
```

If the two disagree, the installer is at fault, not winget and not WinClean. Report it to the application's vendor, and meanwhile choose one of:

- correct the recorded version so winget stops offering it, and let a genuinely newer release be offered normally:
  ```powershell
  Set-ItemProperty '<the uninstall key above>' -Name DisplayVersion -Value '<the real version>'
  ```
- or silence the package entirely with `winget pin add --id <PackageId>`, accepting that real updates are silenced too.

Either way the summary line stays truthful: it counts updates **offered**, not installed. See [result-json.md](result-json.md) for the `AppUpdatesOffered` field.

---

## Windows updates are skipped (PowerShell Gallery unreachable)

WinClean installs the `PSWindowsUpdate` module from the PowerShell Gallery. If the Gallery is unreachable while general connectivity works (a proxy, a TLS-inspecting appliance, a blocked host), the module cannot install and the Windows half of the Updates phase is skipped. The rest of the run continues normally.

This is **not** the offline case. A machine with no connectivity at all returns earlier, at the shared connectivity check described [above](#app-updates-are-skipped-winget-not-found), and never attempts the module install - so if you are simply offline, that section applies, not this one.

Unlike the offline branch, this one is still an **error** and the run exits non-zero: connectivity was proven to work, and then a dependency WinClean needs could not be fetched - an attempted operation that failed rather than a precondition that was absent.

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

WinClean **attempts** a **System Restore Point** near the start of a run (unless `-SkipRestore` is set or you are in `-ReportOnly`). Creation can fail (System Protection disabled, low disk), in which case the run warns and continues, so check the log to confirm a point exists. If one was created and a change caused a problem, roll back to it:

- `Win+R` -> `rstrui.exe` -> choose the restore point named `WinClean <date time>`.

Then check the log file to see exactly what was changed.

---

## Кратко (RU)

- **Очистка почти ничего не освобождает:** включён Controlled Folder Access - добавьте `pwsh.exe` в список разрешённых приложений. В JSON поле `ControlledFolderAccess` = `enabled`.
- **Обновления приложений пропущены:** не найден `winget` - установите App Installer из Microsoft Store.
- **Одно и то же приложение предлагается к обновлению каждый прогон:** причина вне WinClean. Либо пакет установлен для пользователя, а WinClean работает с правами администратора, и `winget` в повышенном контексте такие пакеты трогать отказывается - обновите его сами в обычном окне PowerShell (`winget upgrade --id <PackageId>`). Либо установщик пакета кладёт свежие файлы, но пишет в свою же запись в реестре старую версию, а `winget` смотрит именно туда: сверьте `DisplayVersion` из ветки `Uninstall` с `FileVersion` установленного exe.
- **Обновления Windows пропущены:** недоступен PowerShell Gallery - модуль `PSWindowsUpdate` не ставится, прогон продолжается.
- **Нужны права администратора и PowerShell 7.1+:** откройте `Win+X` -> Терминал (Администратор), вкладка PowerShell 7.
- **One-liner не запускается:** это fail-closed - при отсутствии ассета или несовпадении SHA256 запуск отменяется намеренно; скачайте вручную со страницы Releases.
- **Откат:** используйте точку восстановления `WinClean <дата>` (`rstrui.exe`).

Полная документация на русском: [README_RU.md](../README_RU.md).
