# FAQ and troubleshooting

[Documentation](README.md) · [Getting started](getting-started.md) · [Viewer](viewer.md) · [Runtime](runtime.md)

## Which commands belong on the preparation machine and which belong in WinPE?

Use a **full Windows preparation machine** to install/save the module, build repository packages and run built-in `Sync-OSDApp*` commands. Use **WinPE on the target PC** for deployment staging after OSDCloud has applied Windows and before its first Windows boot.

The Add cmdlets write to a selected Windows target. Do not run deployment examples against your active preparation-machine Windows drive. The [examples](../Examples/README.md) state their environment. The short online example assumes you are already in WinPE; it does not check that for you.

The Viewer is different: it can inspect current Windows, an explicit Windows root, or a supported WinPE target without modifying the deployment.

## Does OSDApps need to be installed in Windows?

Not in the deployed Windows installation for SetupComplete to work. The CLI stages `DeviceManifest.json`, the standalone PreInstall and Runner scripts, and the required available content. SetupComplete does not import the OSDApps module.

The module is needed wherever you run its public CLI commands or open the Viewer.

## What if an app installed by OSDApps is also a blocking app during Autopilot ESP?

Normal Intune detection rules still apply. For a required Win32 app tracked as blocking by the Enrollment Status Page (ESP), Intune evaluates whether the app is already installed. If detection succeeds, Intune does not download or run that app's installer again, even when OSDApps installed it before OOBE. ESP still needs to process app policy and detection; this does not bypass enrollment or other ESP requirements.

OSDApps built-ins can install a newer vendor release than the version packaged in Intune. Design detection to accept **the required version or a newer compatible version**, where your application policy allows this, rather than requiring an exact older version.

For example, if Intune requires version `1.2.0` and OSDApps installed `1.3.0`, a suitable minimum-version rule recognizes the installed app. An exact `1.2.0` rule can report it as missing and cause Intune to attempt installation unnecessarily.

Check the following when preparing the Intune app:

- Match the product, architecture and installation context. A machine-wide installation is not the same as a per-user installation.
- Use a supported version comparison or a detection script that parses version values correctly. Do not use plain string ordering or accept every newer major version without checking compatibility.
- Ensure detection matches the installer actually used. An MSI product-code rule might not recognize an EXE-based installation, and product codes can change between releases.
- Do not rely on a marker written only by your Intune installation wrapper: an OSDApps installation will not create that marker.

OSDApps does not change Intune assignments or detection rules. Missing dependencies or additional organization-specific configuration can still require processing through Intune. Validate detection against an OSDApps-installed device before making the app blocking in ESP.

See Microsoft's [Win32 app processing flow](https://learn.microsoft.com/troubleshoot/mem/intune/app-management/develop-deliver-working-win32-app-via-intune) and [Win32 app detection rules](https://learn.microsoft.com/intune/intune-service/apps/apps-win32-add#step-4-detection-rules).

## Why does Microsoft 365 Apps not refresh in WinPE?

OSDApps does not use the Office Deployment Tool as a WinPE acquisition mechanism. Built-in acquisition/refresh runs in full Windows, where the deployment runtime used by the module is available. WinPE stages Office deployment intent and can copy an existing Office cache.

See [Architecture](architecture.md) and [Microsoft 365 Apps options](built-in-apps.md#microsoft-365-apps).

## Teams sync works in WinPE. Why is it also deferred?

The public `Sync-OSDAppMicrosoftTeams` command **rejects WinPE**. Downloading Teams files may be technically possible there, but that is not the supported OSDApps built-in synchronization path.

All built-ins follow the same division: stage in WinPE; refresh through full-Windows Sync commands or standalone PreInstall. The MSI/EXE signature policy is enforced in full Windows, not bypassed by treating WinPE as another Sync environment.

## What if I need Office or Teams fully managed in WinPE?

Use the repository model for organization-managed content and versioning. Repository acquisition and staging can occur in WinPE, but installation still occurs in full Windows through SetupComplete. This does not make a vendor installer a WinPE-compatible executable.

## How do I check which module and configuration are active?

```powershell
Get-Module OSDApps | Select-Object Name, Version, Path
Get-OSDAppConfiguration
```

A previously imported development module can remain active even after installing a Gallery release. Review the actual loaded path, not only the installed version list.

Configuration is session-scoped. Starting a new PowerShell process or reloading a module is not a substitute for configuring the deployment session. Runtime values are written into the device manifest when apps are staged.

## Why is my staging queue empty or already populated?

An empty queue is expected before Add commands run, or after successful cleanup removes the temporary manifest. The Viewer also needs to be looking at the intended Windows target.

An existing manifest means that target already has OSDApps staging; it does not by itself mean anything is installed. Inspect the target and entries before changing them. Re-adding an Id replaces its entry and moves it to the end of the queue. Use `Remove-OSDAppStaging` for intentional unstaging in WinPE; do not delete a whole SetupComplete file that may contain other commands.

`Show-OSDAppUI -TestMode` inspects an existing isolated GUI test folder on full Windows. It does not create demonstration apps, and it must not be used for normal WinPE deployment.

## What happens to an old BuiltIn\Teams USB cache?

The canonical Id remains `MicrosoftTeams`; its folder is `BuiltIn\MicrosoftTeams`, and the commands are `Add-OSDAppMicrosoftTeams` / `Sync-OSDAppMicrosoftTeams`. The public metadata now declares `Teams` as a **retired cache alias**, not as a command or deployable application Id.

Run `Sync-OSDAppMicrosoftTeams` on full Windows. OSDApps prepares the canonical payload first and removes `BuiltIn\Teams` only after `BuiltIn\MicrosoftTeams` is complete. Standalone PreInstall applies the same guarded cleanup when it successfully uses or creates a canonical USB cache; cleanup failure is a warning and does not fail installation. If canonical preparation or trust validation fails, the old folder is preserved. You can inspect the condition beforehand with `Get-OSDAppCacheHealth -Offline` or explicitly preview manual removal with `Clear-OSDAppCache -Name Teams -WhatIf`.

This does not reintroduce the old `Add-OSDAppTeams` or `Sync-OSDAppTeams` commands, and the SetupComplete runtime still accepts only the canonical identity. The original rename is recorded in the [0.31.0 changelog](../CHANGELOG.md#0310).

## Do built-in apps require an OSDCloud USB flash drive?

Not for most built-ins. Without a cache volume, supported Add cmdlets can stage intent and PreInstall can acquire their content directly to the local Windows runtime when online. **Microsoft Company Portal and CMTrace Open are exceptions:** both require a populated OSDCloud cache during WinPE staging and do not acquire content during SetupComplete. Company Portal's preparation command downloads the official kit automatically on full Windows; its `-KitPath` option is only a fallback for a locally supplied kit. Windows Inbox Cleanup uses a bundled script rather than a downloaded installer. Repository Add commands can use a temporary cache on the offline Windows disk when no USB cache is present.

A volume with the configured label, `OSDCloud` by default, is automatically used as the cache when present. Keep module files and installer cache content conceptually separate: `\Modules` is a convenient module location; `\OSDApps` is the cache directory.

## What does a blank OSDCloud USB flash drive need?

For **OSDApps cache use**, a suitable volume with the configured label is enough; `\OSDApps` and its content folders can be created by the acquisition path. This is not a claim that an otherwise blank USB flash drive can boot WinPE or deploy Windows. Boot media preparation belongs to OSDCloud, outside these examples.

An empty application cache works for online acquisition. It cannot supply apps for a fully offline deployment.

<a id="can-the-osdcloud-usb-be-completely-blank"></a>

## Can I pre-cache an OSDCloud USB flash drive?

Yes. See [Prepare a USB cache](../Examples/Prepare-UsbCache.md). Full-Windows built-in commands include:

```powershell
Sync-OSDAppMicrosoft365Apps
Sync-OSDAppMicrosoftTeams
Sync-OSDAppAdobeAcrobatUnified
Sync-OSDAppGoogleChromeEnterprise
Sync-OSDAppMozillaFirefoxEnterprise
Sync-OSDAppCiscoWebex
```

Choose the actual architectures, channels and languages needed by your deployment rather than running every default blindly. In particular, match Office/Firefox configuration and Teams architecture between preparation and staging.

For repository packages, configure your real `CatalogUri` and call `Sync-OSDAppRepository`. Pre-caching is optional for normal online deployment; `Add-OSDApp` can synchronize requested repository packages in WinPE, and built-ins refresh during full-Windows PreInstall.

## How do I inspect and safely clean stale repository cache content?

For built-in namespace cleanup instead, see [Keep the built-in cache managed](#how-do-i-keep-the-built-in-cache-managed).

Start with the read-only health plan:

```powershell
$Health = Get-OSDAppCacheHealth
$Health.Entries |
    Where-Object Action -ne 'None' |
    Select-Object Id, CanonicalId, State, Integrity, Action, Reason, SizeMB
```

This uses the session's configured repository catalog. Use `-Offline` for a
local-only integrity view, or `-CatalogPath` / `-CatalogUri` for an explicit
desired catalog. A desired-state failure makes `Healthy=False`; it never grants
permission to remove cached content.

Then preview complete reconciliation:

```powershell
Sync-OSDAppRepository -Prune -WhatIf
```

If the listed cache volume, replacements and removals are correct, run the same
command with `-Confirm`. `-Prune` is deliberately incompatible with selective
`-Name` synchronization. Valid exceptional packages can be retained with
`-PinnedId`; aliases, missing packages and corrupt packages cannot be pinned.
See [Cache health and reconciliation](repository.md#cache-health-and-reconciliation).

## How do I keep the built-in cache managed?

`OSDApps\BuiltIn` is reserved for OSDApps built-in app caches. Store custom packages in your repository, and keep unrelated files outside this directory. Use a current module version so its built-in catalog knows the apps present on your USB flash drive.

Preview unmanaged top-level folders and loose files, then apply the reviewed plan:

```powershell
Clear-OSDAppCache -BuiltIn -Prune -WhatIf
Clear-OSDAppCache -BuiltIn -Prune -Confirm
Get-OSDAppCacheHealth -Offline
```

Unlike `Clear-OSDAppCache -BuiltIn` alone, adding `-Prune` **retains every current built-in application directory**, including all architecture, language and channel variants. Legacy `Package.*` and `teams.msix` filenames inside those app directories are still supported and are not a reason to delete or download anything. Retired unregistered directories such as `VisualCppRedist` or `SevenZip`, and unrelated top-level files, are candidates for removal; their contents are not migrated.

Registered aliases, filesystem links and transaction/recovery content are preserved for review and reported in the result's `Review` property. Registered aliases use their canonical app's replacement-validation flow. Pruning does not clean arbitrary nested files inside a current app directory; each app's generation handling owns that layout. Missing or invalid current app content remains visible to cache health and requires synchronization or investigation, not namespace pruning.

Known retired variants are cleaned automatically after successful synchronization, both through Sync cmdlets and Windows PreInstall: `VisualCppRedist` becomes `VisualCRedist`, and `SevenZip` becomes `7Zip`. Only the matching architecture is removed, after revalidating its current replacement and confirming the old metadata identity. Other variants, unknown folders, links and recovery content remain untouched. Cleanup failure warns without failing the successfully synchronized app. The empty retired parent is removed after its last variant. See [automatic retired-cache cleanup logs](maintenance.md#automatic-retired-cache-cleanup-logs) for removal, preservation and failure records in Client.log and Runtime.log.

The broader namespace prune above remains explicit USB maintenance. The apply operation uses the cache writer lock and honors confirmation. `-WhatIf` does not create a lock or log. Repository cache and target staging remain separate; app synchronization continues to replace superseded managed generations transactionally.

## What happens if the USB is removed too early?

It may no longer be available for the intended cache refresh or for missing content. A deployment can work without USB when its local content or online acquisition path is sufficient, but do not assume that a partially prepared target is self-contained.

Keep the USB flash drive attached through SetupComplete until OOBE appears when following the USB examples. Do not move one USB flash drive between two PCs while either is still using it.

## What happens if there is no network?

A complete, matching local payload can be used without vendor refresh. Supported built-in MSI/EXE files must **still pass signature and expected-publisher checks**, and repository archives must pass their SHA-256 checks. With no usable source, the affected app is recorded as failed or skipped while independent entries can continue. Manifest, integrity and supported-publisher trust failures stop processing.

The fully offline eight-app 0.34.0 test passed on the tested Windows trust configuration. It does not guarantee that every fresh Windows image has all certificate chain/revocation data needed for every vendor signature.

`BuiltInRefreshSkipped` means PreInstall recognized no available network and used staged content. `BuiltInRefreshFailed` is different: a refresh failed and an acceptable local fallback was used. An available network interface does not itself prove that a vendor endpoint is reachable.

## Does -Offline disable internet access?

No. On `Show-OSDAppUI` and app discovery it disables online repository lookup. It does not disconnect adapters, change a staged deployment's acquisition policy or suppress Windows trust/revocation network traffic.

For the Viewer only, `-SkipSignatureVerification` suppresses its signature inspection. This does not relax Sync or SetupComplete enforcement. For an actual offline deployment test, disconnect networking and provide the required cache; see [Offline WinPE deployment](../Examples/WinPE-Offline.md).

## Why do Files present, SHA-256 verified and Signature valid differ?

They describe different evidence:

| Result | Meaning |
| --- | --- |
| Files present | The required built-in files/directories exist. |
| SHA-256 verified | The checked file matches its referenced hash. Repository ZIPs use the catalog hash; some built-ins also check recorded release hashes. |
| Signature valid | A supported cached MSI/EXE passed Windows Authenticode and the expected built-in publisher check. |

A built-in `Valid=True` cache entry is not a claim that its whole package chain was signature-verified. Office data, Teams MSIX and Adobe's outer ZIP are outside the specific MSI/EXE signature scope. The exact local checks differ by app; `Healthy=True` does not establish vendor freshness or compatibility with every Office configuration. See [what a cache check proves](maintenance.md#what-a-cache-check-proves). Read the [Viewer status guide](viewer.md#integrity-and-signature-are-different-checks) and [publisher policy](built-in-apps.md#authenticode-and-publisher-policy-0340).

## Why did a signature or publisher check fail?

Read the actual status, signer and file path. Check the device clock and availability of Windows certificate trust/revocation data. A valid signature from an unexpected organization is not an approved built-in publisher. Do not edit the allowlist or bypass deployment checks just to make a status green.

On full Windows, inspect the existing cache without changing packages:

```powershell
Get-OSDAppCache -VerifySignatures |
    Select-Object Id, Valid, SignatureStatus, SignatureScope, SignatureSigner, SignatureDetail
```

The Viewer reports unsupported checks separately: WinPE does not invoke Windows Authenticode verification, repository ZIPs use their independent hash checks, and Adobe's outer ZIP is not assessed as a signed executable.

## What happens if Office refresh hangs?

The standalone Office refresh has a 20-minute timeout by default. On a failed refresh, an available staged Office fallback must still satisfy its source and ODT signature/publisher checks. Without an acceptable fallback, Office acquisition fails and Runner skips Office while independent entries can continue. A manifest or supported-publisher trust failure remains fatal. The timeout is not a promise that an arbitrary cached Office configuration can satisfy a changed deployment.

## Where are the logs?

The usual locations are:

| Context | Location |
| --- | --- |
| Module/cache work with USB | `<cache volume>:\OSDApps\Logs\Client.log` |
| Standalone PreInstall and Runner | `%ProgramData%\OSDApps\Logs\Runtime.log` by default |

Runtime `LogPath` is configurable; use the path written into the device manifest for that deployment. The Viewer discovers known default log locations, not every custom path. The runtime log rotates, so include relevant `.1`, `.2` or `.3` files if the events have moved there.

See [Runtime logging](runtime.md#logging). Check the final event and individual installer/provisioning exit codes, not only a successful staging message.

## How do I see which source path was selected?

In the WinPE staging session, add `-Verbose` to the built-in Add command:

```powershell
Add-OSDAppMicrosoft365Apps -Verbose
Add-OSDAppMicrosoftTeams -Verbose
```

These commands **perform staging**; they are not read-only diagnostics. Their output identifies the Windows target, cache detection and intended acquisition path. For inspection without changes, use the Viewer or read the existing Client/Runtime logs.

## Why did my runtime source disappear?

The default `CleanupMode` is `OnSuccess`. After success, cleanup removes temporary source under `Windows\Temp\OSDApps`; persistent logs remain at the configured log location. Select `CleanupMode Never` before staging to retain source for troubleshooting.

An empty Staged for device tab after cleanup does not mean installation failed. Consult `InstallComplete` and individual app outcomes.

## Does a failed installation remove the source?

No. The runtime retains source on failure so the manifest, payload and work directory can be inspected. Do not delete that evidence before collecting the relevant log. `CleanupMode=OnSuccess` in a completion line names the policy; use the cleanup events or filesystem state to verify cleanup itself.

## Does SetupComplete retry a failed application after reboot?

No. SetupComplete is a one-shot Windows Setup phase and OSDApps does not create a scheduled task, RunOnce value or service to repeat it. During that single run, an ordinary app-local acquisition or installer failure is recorded and independent remaining applications continue. The final result is still `Failed`, staging is retained and remediation is an explicit administrator action. Manifest, hash and supported-publisher trust failures stop the queue instead of continuing.

## What is the difference between catalog.json, CacheCatalog.json, and DeviceManifest.json?

| File | Role |
| --- | --- |
| `catalog.json` | Online repository index |
| `Apps/<Id>/<Version>/<Architecture>/manifest.json` | Per-package metadata, including archive hash, optional Vendor and optional `PackageType` (`Application` or `Script`) |
| `CacheCatalog.json` | Local repository-cache metadata snapshot |
| `CacheInfo.json` | Per-built-in cache metadata |
| `DeviceManifest.json` | The selected Windows target's ordered application queue and runtime configuration |

The old `CacheManifest.json` filename is not used. USB cache and device staging are separate locations.

## Can I request another built-in application?

Yes. Review the [built-in request policy](built-in-apps.md#requesting-a-new-built-in-application) and [contribution guide](../CONTRIBUTING.md). Built-ins are reserved for broadly useful integrations with stable vendor-native acquisition and unattended installation paths.

Customer-specific, authenticated or otherwise non-generic content belongs in an organization-managed repository instead.

## Does OSDApps distribute built-in installers?

No. The module provides acquisition and deployment logic, not vendor installer binaries. Vendor content may be cached locally on deployment media, but OSDApps itself does not mirror or redistribute built-in payloads. Repository owners are responsible for their packages' provenance, hosting, licensing and redistribution rights.

[Back to documentation](README.md)
