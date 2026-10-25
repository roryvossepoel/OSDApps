# Architecture

[Documentation](README.md) · [Getting started](getting-started.md) · [Runtime](runtime.md)

OSDApps separates content ownership, acquisition, device staging, installation and inspection. The CLI writes deployment state; the Viewer reads it. SetupComplete runs independently of the module.

![OSDApps end-to-end architecture](images/osdapps-architecture.svg)

## End-to-end flow

```text
Full Windows preparation (optional)
    save module and prepare reusable USB content

WinPE after OSDCloud applies Windows
    synchronize selected repository packages when online
    stage built-in intent and available fallback content
    write one ordered device queue and standalone runtime

First Windows boot / SetupComplete
    PreInstall prepares built-ins and enforces applicable installer trust checks
    Runner validates all selected repository hashes before installer execution
    each independent app is attempted once; ordinary app failures do not block the rest
    write persistent result; apply cleanup policy; retain logs

OOBE / Autopilot continues
```

The Viewer can inspect an existing Windows target and cache in full Windows or supported WinPE. It does not perform any of the acquisition, staging, installation or cleanup steps above.

## Two source models

### Repository apps and scripts

A repository is owner-managed static content: `catalog.json`, per-app manifests and package archives. During WinPE staging the module resolves a compatible variant, downloads or reuses its `Package.zip`, checks the manifest SHA-256 and copies it to local device staging.

Runner checks every available selected staged archive before starting the first installer, then extracts it for `Package/Install.ps1` execution. A hash mismatch is a queue-blocking trust failure. Runner does not contact the repository to refresh packages during SetupComplete.

Full-Windows `Sync-OSDAppRepository` can also prepare media ahead of deployment. Repository variants default to the synchronization host's architecture. From 0.43.0, use `-Architecture x64` or `-Architecture arm64` to prepare another target, and use the same parameter on desired-state cache-health checks. The cache still holds one variant per Id; see [repository target selection](repository.md#preparing-content-for-another-architecture). Repository content, licensing and hosting remain the repository owner's responsibility.

`Get-OSDAppCacheHealth` compares physical cache content, local metadata and an
optional desired catalog without changing files. Explicit
`Sync-OSDAppRepository -Prune` reconciles the complete catalog for the selected architecture
transactionally; normal selective synchronization remains merge-only.

### Built-in apps

Built-ins are vendor-native integrations maintained by OSDApps. The module does not ship their installer payloads.

WinPE stages deployment intent and copies matching existing cache content as fallback when available. Full-Windows Sync commands or standalone PreInstall perform acquisition/refresh. Microsoft 365 Apps uses the Office Deployment Tool; Teams, Adobe, Chrome, Firefox and Webex use their integrated vendor acquisition paths.

Supported installer files are checked for Windows Authenticode trust and the expected publisher organization. This covers Office `setup.exe`, Teams `teamsbootstrapper.exe` and Chrome/Firefox/Webex MSI files, not every nested payload. See the [publisher policy](built-in-apps.md#authenticode-and-publisher-policy-0340).

## Why Office refreshes in full Windows

OSDApps does not treat the Office Deployment Tool as a WinPE acquisition mechanism. It uses the full-Windows runtime for Office synchronization. The same phase boundary is used for all built-ins; public built-in Sync commands are not the WinPE staging interface.

An organization can instead supply Office as a repository package when it needs to own the package/version. Repository acquisition then happens in WinPE, but installation still runs in Windows.

## Optional OSDCloud USB cache

The CLI identifies a visible volume by `CacheVolumeLabel` (default `OSDCloud`), not a fixed drive letter. Its cache root is `\OSDApps`.

| Condition | Acquisition path |
| --- | --- |
| USB + online | Stage available cache as fallback, check vendor freshness and refresh where needed. |
| USB + offline | Use matching, complete local content staged from the cache, subject to applicable trust/hash checks. |
| No USB + online | Repository staging can use a temporary cache on the offline Windows disk; built-ins can be acquired directly to the local runtime after boot. |
| No USB + offline | Requires sufficient acceptable content already staged on the device. Without it, acquisition/installation cannot succeed. |

The cache changes where content is acquired and reused. Runner consumes local staging; it does not execute installers directly from the USB cache. Keep media attached while the deployment is using it.

![Source ownership and synchronization phases](images/source-ownership-sync.svg)

## Cache generation recovery

Built-in refreshes replace complete directories, not individual files in the
active cache. A sibling `.osdapps-new-<guid>` holds the candidate and
`.osdapps-old-<guid>` temporarily holds the previous generation. If a process
stops between the directory renames, the next full-Windows built-in sync or
PreInstall invocation can restore a validated old generation before attempting
downloads or offline restaging. Recovery never overwrites an existing active
directory or promotes unfinished `.new` content. If no old candidate validates,
or multiple candidates validate, it preserves them and reports the ambiguity.
Successful refresh removes obsolete transaction directories. Read-only cache
inspection does not perform recovery. This does not retry SetupComplete or
recover an interrupted Windows installation.

## One cache writer at a time

OSDApps 0.41.0 and later hold an exclusive file handle on
`<cache root>/.osdapps-cache.lock` while a public built-in sync, repository
sync/prune, or cache-clear operation is active. The lock covers the full
operation, including reading the existing catalog for reconciliation, recovery,
downloads, directory swaps and cleanup. PreInstall uses the same helper for its
USB cache, or its local staged root when no USB cache is available.

A competing lock attempt fails immediately instead of waiting or retrying.
In PreInstall this is a phase failure (`CacheLockUnavailable`): SetupComplete's
existing exit-code guard prevents Runner from starting. There is no scheduled
retry or promise that SetupComplete runs again. Repository staging also stops
on a lock failure instead of reading a changing cache as offline fallback.

Normal completion and errors dispose the handle; process termination or reboot
releases it through the operating system. The empty file deliberately remains,
including after `Clear-OSDAppCache -All`. Its existence does not mean the cache
is busy. Do not delete or replace it to force an unlock. `-WhatIf` neither opens
nor creates it, and unrelated cache roots can be written independently.

This coordinates cooperating writers using this implementation. Older module
versions, manual file operations and external tools do not participate. Viewer
and health inspection remain read-only and do not acquire a lock; they are not
consistent snapshots during a concurrent write. Cache locking does not serialize
separate device-staging operations or retry interrupted deployments.

## Cache transaction space checks

Before a candidate is created, public built-in synchronization and standalone
PreInstall check the acquisition volume. The budget is the larger of the
configured minimum and the expected new payload plus 20% and 64 MB of overhead.
Known HTTP lengths are preferred; without one, the current generation provides
an estimate. Office retains its 8 GB default minimum because ODT does not expose
a complete download length up front. Teams retains 2 GB, Adobe 3 GB and the
other built-ins 1 GB. Existing content already occupies disk space, so it is not
counted again: moving it to the sibling backup does not copy its payload.

Repository synchronization sums only archives that need acquisition. Local
sources use their file lengths; remote archives use a HEAD request bounded to
15 seconds. Missing/rejected lengths fall back to the larger of the existing
package size and 1 GB per changed package. The batch budget adds the same 20%
and 64 MB allowance and is rechecked for remaining work before each archive.
The cache stores ZIPs without extracting them. Pending prune removals are not
credited as free space before commit. `-WhatIf` skips these probes and checks.

Unchanged MSI/ZIP generations can be reused without replacement space. Teams
still prepares a fresh candidate containing a bootstrapper and a copied or
newly downloaded MSIX. A blocked PreInstall refresh uses the existing acceptable
staged payload when available; without a fallback, acquisition fails normally.

These checks apply to local acquisition volumes, including the Windows disk
when no USB cache is present. They are estimates, not disk reservations: a
server can omit or misreport size, Office content can grow, and other processes
can consume space afterward. Transaction validation/rollback remain necessary.
They do not size app installation or extraction workspace, nor change
`Test-OSDAppDeployment -MinimumFreeSpaceGB` on the offline Windows target.

## Runtime locations

| Location | Contents |
| --- | --- |
| `<cache volume>:\OSDApps` | Reusable repository/built-in cache and cache-operation logs |
| `<Windows target>\Windows\Temp\OSDApps` | Per-device manifest, PreInstall/Runner, staged packages and Work |
| `%ProgramData%\OSDApps\Logs\Runtime.log` | Default persistent PreInstall/Runner log in deployed Windows |
| `%ProgramData%\OSDApps\Results\Latest.json` | Default atomic final deployment result and per-app outcomes |

Typical local staging contains `DeviceManifest.json`, `Invoke-OSDAppPreInstall.ps1`, `Invoke-OSDAppRunner.ps1`, `Restore-OSDAppCacheGeneration.ps1`, `Assert-OSDAppTransactionSpace.ps1`, `Enter-OSDAppCacheLock.ps1`, `Packages`, `BuiltIn` and `Work`.

`CleanupMode OnSuccess` schedules removal of temporary device source only after every selected app succeeded; `Never` retains it. A failed or skipped app retains source for investigation. The persistent log, result and reusable USB cache are separate from that staging directory.

SetupComplete is a one-shot Windows Setup phase. OSDApps deliberately creates no scheduled task, RunOnce value, service or other retry persistence. PreInstall and Runner therefore isolate ordinary app-local failures and continue independent entries during that one execution. Manifest, hash and supported-publisher trust failures remain blocking safety boundaries.

## Source resolution rules

For built-ins, the deployment first identifies the optional cache and available local fallback, then attempts freshness/acquisition when network availability permits. Content must be locally available and pass the checks applicable to its format before installation.

A refresh failure is not automatically fatal if an acceptable staged fallback exists. Without a usable fallback, that built-in is recorded as failed and its installer is skipped while independent entries can continue. Conversely, a complete-looking fallback is not automatically acceptable: a supported MSI/EXE signature or publisher failure stops deployment. `GetIsNetworkAvailable()` reports interface availability, not verified access to every vendor endpoint.

Per-deployment `AcquisitionOutcome` and retained refresh errors distinguish successful download, metadata-confirmed reuse, offline use and fallback from installation success. The embedded PreInstall result counts fallback/offline entries; a successful installation can still carry an acquisition warning. See [Acquisition reporting](runtime.md#acquisition-and-installation-are-separate-results) and [Runtime logging](runtime.md#logging).

## Metadata model

| File | Role |
| --- | --- |
| `catalog.json` | Repository index, including optional retired aliases mapped to canonical IDs |
| `Apps/<Id>/<Version>/<Architecture>/manifest.json` | Per-repository-package metadata and archive hash |
| `CacheCatalog.json` | Local repository-cache snapshot |
| `CacheInfo.json` | Per-built-in cache metadata |
| `DeviceManifest.json` | Selected Windows target's ordered `Apps` queue and runtime settings |
| `metadata/builtins.json` | Public built-in definitions for discovery and external consumers; not the organization's package catalog |

Optional repository Vendor metadata is descriptive. It is not a signing certificate, a signature verification result or an authorization decision.

## Device manifest

Repository packages can be classified as `App` or `Script`. Both execute `Package/Install.ps1` as SYSTEM, with the same hash checks and one-shot failure handling; the type is presentation and reporting metadata. Scripts must be unattended and must not trigger a restart.

The manifest has a stable per-staging `DeploymentId` and one ordered `Apps` array containing `Source=BuiltIn` or `Source=Repository` entries. PreInstall filters the built-ins for preparation; Runner processes the full array from top to bottom and uses the identity to correlate phase results.

Adding a new Id appends it. Re-adding an existing Id replaces its entry and moves it to the end, rather than creating a duplicate. Viewer sorting changes only the screen order; it never writes the manifest.

`Set-OSDAppConfiguration` is session-scoped. Add commands capture runtime settings in the manifest so SetupComplete does not need the module or the original PowerShell session.

For exact package fields, see [Repository apps and scripts](repository.md), [Built-in apps](built-in-apps.md) and the [public metadata contract](public-metadata.md). For proven scenarios and remaining limitations, see [Validation matrix](testing.md).
