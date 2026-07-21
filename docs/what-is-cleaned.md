# What Exactly Is Cleaned

This page is the exhaustive inventory of what WinClean touches, phase by phase, and what it deliberately leaves alone. The guiding rule throughout: caches and regenerable temporary data are cleaned; your files, packages, and project dependencies are preserved.

For the machine-readable outcome of a run (freed bytes per category, warnings, phase status), see [result-json.md](result-json.md).

---

## Temporary files

Cleaned: user and system temp locations (`%TEMP%`, `%LOCALAPPDATA%\Temp`, and equivalents), deduplicated so a path reachable under two names is not counted or cleaned twice.

The temp sweep is age-aware. Files younger than roughly one day are kept, because they usually belong to a running installer or application. The age test is recursive: a freshly written file nested deep inside an old-looking parent folder keeps that whole subtree, so an active operation is never disrupted. An unreadable subtree is kept rather than deleted (the age filter fails closed).

## Browser caches

Seven browsers are handled.

Chromium family (one shared cache set: `Cache`, `Code Cache`, `GPUCache`, `Service Worker\CacheStorage`):

- Microsoft Edge
- Google Chrome
- Yandex Browser
- Opera
- Opera GX
- Brave

Firefox is handled separately (`Mozilla\Firefox\Profiles`, the `cache2` store), because its layout differs from Chromium browsers.

Multi-profile discovery: Chrome, Edge, and Firefox are cleaned across **all** profiles, not just the default one. Yandex, Opera, Opera GX, and Brave are cleaned for their default profile only.

| Cleaned | Preserved |
|:--------|:----------|
| Disk/code/GPU caches, service-worker cache storage | Bookmarks, saved passwords, history, cookies, extensions |

## Windows caches

Roughly eight categories of regenerable Windows caches, including:

- Windows Update cache (`SoftwareDistribution\Download`). The Windows Update service is stopped first; if it will not stop, the cache cleanup is skipped entirely rather than deleting files the service still holds.
- Delivery Optimization cache (cleared via the supported cmdlet).
- Thumbnail and icon caches.
- Other system caches that Windows rebuilds on demand.

## Developer caches

Cleaned (build and download caches only):

- npm, yarn, pnpm
- pip
- Composer
- NuGet (metadata caches)
- Gradle (build caches)
- Cargo
- Go build cache
- uv

| Cleaned | Preserved |
|:--------|:----------|
| Package manager download/build caches | `node_modules`, Python virtual environments, `vendor`, `\.nuget\packages`, `\.gradle\caches\modules` |

Skipped with `-SkipDevCleanup` (or the whole cleanup group with `-SkipCleanup`).

## Docker & WSL

Cleaned:

- Unused Docker images
- Stopped containers
- Docker build cache
- WSL2 virtual disk (VHDX) compaction

VHDX compaction uses `diskpart`. In v2.19 a failed `compact vdisk` is reported as a warning instead of a neutral "no space saved", and a failed `wsl --shutdown` skips compaction rather than touching a possibly-live disk.

Skipped with `-SkipDockerCleanup` (or `-SkipCleanup`).

## IDE caches

Cleaned:

- Visual Studio caches (including the MEF component cache)
- Visual Studio Code caches
- JetBrains IDE caches

Skipped with `-SkipVSCleanup` (or `-SkipCleanup`).

## Privacy (optional)

Cleaned:

- DNS resolver cache flush
- Windows event logs (only enabled, non-empty logs)
- Run history (Win+R)
- Explorer history and recent documents

Telemetry is only disabled when you pass `-DisableTelemetry`; it is never touched by default.

## Driver store

Cleaned: superseded third-party driver packages. A package is removed only when **both** conditions hold:

- No device is currently bound to it, and
- A strictly newer version of the same INF is installed.

As of v2.19 the rule requires a strictly newer version; a package of the same version with only an older date is no longer removed. Drivers for temporarily unplugged hardware survive, and `pnputil /force` is never used.

## Disk Cleanup

Cleaned via the built-in `cleanmgr` using StateFlags for 23 registry handler categories (system caches, error dumps, update leftovers, thumbnail cache, and similar). Only categories that actually exist on the machine are armed; a run that could arm nothing is skipped and is not reported as a success. `DownloadsFolder` is deliberately excluded, because it holds user files.

## Windows.old

Removed only after explicit confirmation. This is the previous Windows installation left behind by a feature update; it can be large, but it is also what an in-place rollback uses, so WinClean never removes it silently.

---

The exact, machine-readable result of any run (bytes freed per category, warnings, and each phase's status) is written to the result JSON. See [result-json.md](result-json.md).
