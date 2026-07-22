# FAQ

Deeper answers than the README summary. See also [safety.md](safety.md), [what-is-cleaned.md](what-is-cleaned.md) and [troubleshooting.md](troubleshooting.md).

---

### Is it safe to run WinClean?

Yes, by design. WinClean attempts a System Restore Point before the maintenance phases (and warns, without stopping, if it cannot be created), refuses a fixed set of protected system roots as cleanup targets, and can be run in `-ReportOnly` mode to preview the actions without making maintenance changes. The one-command installers verify the download's SHA256 against the published release hash and abort on any mismatch. The full model is documented in [safety.md](safety.md).

### Will it delete my installed programs?

No. WinClean removes caches and temporary files, not applications or user data. Package stores are preserved: `node_modules`, Python virtual environments, `vendor`, `.nuget\packages`, and `.gradle\caches\modules` are left alone. It cleans the **caches** those tools keep, which are safe to rebuild.

### Will it touch my browser passwords or bookmarks?

No. Only cache directories are cleaned. For Edge and Chrome that is Cache, Code Cache, GPUCache and the Service Worker CacheStorage; for Brave, Yandex, Opera and Opera GX it is Cache, Code Cache and GPUCache; Firefox uses its own `cache2`. Bookmarks, saved passwords, history and profiles are not touched.

### How often should I run it?

Monthly is a reasonable default. Active developers or machines with limited disk space benefit from weekly runs. There is no background service; you run it when you want to.

### Why does it need Administrator rights?

Windows Update, system cache cleanup, DISM component-store operations, service management (stopping the Windows Update service before clearing its cache), and creating restore points all require elevation. WinClean declares `#Requires -RunAsAdministrator` and refuses to run without it, rather than half-working.

### Can I run it on Windows 10?

WinClean is designed and tested for Windows 11 (23H2 / 24H2 / 25H2). Most features work on Windows 10 with PowerShell 7.1+, but some paths and Disk Cleanup categories are Windows-11-specific and may simply be skipped.

### Does it send any data anywhere?

No telemetry and no personal or file data is ever sent, and it stores or transmits no credentials. It is not fully offline, though: to do its job WinClean contacts the standard maintenance services - Windows Update and the PSWindowsUpdate module, winget, the PowerShell Gallery (a startup version check), and a connectivity probe - and the one-command installers fetch the release asset from GitHub. None of that uploads anything about you or your files.

### What does `-ReportOnly` do?

It is a dry run. WinClean walks the same phases and reports what it **would** clean and roughly how much space it would free, but makes no maintenance changes (no installs, no deletions of the caches it would clean, no restore point). It still writes its own log and result file and does the read-only update/connectivity checks unless you also pass `-SkipUpdates`. It is the recommended first run. Note that `-ReportOnly` is a preview of actions, not a verification of the script's integrity; integrity is handled by the fail-closed SHA256 check in `get.ps1` / `install.ps1`.

### How do I skip parts of the run?

Use the skip flags. In the current version, `-SkipCleanup` skips the **entire** cleanup group (system cleanup, deep cleanup, developer caches, Docker/WSL, and Visual Studio), which matches its documented "skip all cleanup" meaning. The per-category flags are finer controls used when you want cleanup in general but not one category:

- `-SkipUpdates` - no Windows or winget updates
- `-SkipCleanup` - no cleanup at all (updates only)
- `-SkipDevCleanup` - keep developer caches
- `-SkipDockerCleanup` - keep Docker/WSL
- `-SkipVSCleanup` - keep Visual Studio
- `-SkipRestore` - do not create a restore point
- `-DisableTelemetry` - additionally disable Windows telemetry (opt-in)

### How do updates work, and why does the "Apps" count look high?

Windows updates run through the `PSWindowsUpdate` module (including drivers). Application updates run through `winget upgrade --all`. The number shown for apps is what winget **offered**, not a confirmed install count: `winget upgrade --all` silently skips pinned packages, packages without a manifest, and packages where a UAC prompt was cancelled, and it does not report per-package results. The result JSON names this field `AppUpdatesOffered` for exactly this reason. See [result-json.md](result-json.md).

### What if something breaks?

If a restore point was created at the start of the run (check the log; it is attempted but can fail), roll back to it (`rstrui.exe`, choose `WinClean <date>`). Then read `%TEMP%\WinClean_<date>.log` to see what changed. More in [troubleshooting.md](troubleshooting.md).
