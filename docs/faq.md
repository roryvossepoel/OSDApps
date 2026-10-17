# FAQ and troubleshooting

[Documentation](README.md) · [Getting started](getting-started.md) · [Viewer](viewer.md) · [Runtime](runtime.md)

## Which commands belong on the preparation machine and which belong in WinPE?

Use a **full Windows preparation machine** to install/save the module, build repository packages and run built-in `Sync-OSDApp*` commands. Use **WinPE on the target PC** for deployment staging after OSDCloud has applied Windows and before its first Windows boot.

The Add cmdlets write to a selected Windows target. Do not run deployment examples against your active preparation-machine Windows drive. The [examples](../Examples/README.md) state their environment and include WinPE guards where they stage applications.

The Viewer is different: it can inspect current Windows, an explicit Windows root, or a supported WinPE target without modifying the deployment.

## Does OSDApps need to be installed in Windows?

Not in the deployed Windows installation for SetupComplete to work. The CLI stages `DeviceManifest.json`, the standalone PreInstall and Runner scripts, and the required available content. SetupComplete does not import the OSDApps module.

The module is needed wherever you run its public CLI commands or open the Viewer.

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

No. With no cache volume, the Add cmdlets can stage intent and PreInstall can acquire built-ins directly to the local Windows runtime when online. Repository Add commands can use a temporary cache on the offline Windows disk when no USB cache is present.

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

## What happens if the USB is removed too early?

It may no longer be available for the intended cache refresh or for missing content. A deployment can work without USB when its local content or online acquisition path is sufficient, but do not assume that a partially prepared target is self-contained.

Keep the USB flash drive attached through SetupComplete until OOBE appears when following the USB examples. Do not move one USB flash drive between two PCs while either is still using it.

## What happens if there is no network?

A complete, matching local payload can be used without vendor refresh. Supported built-in MSI/EXE files must **still pass signature and expected-publisher checks**, and repository archives must pass their SHA-256 checks. With no usable source, PreInstall or Runner stops instead of pretending the app was installed.

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
| SHA-256 verified | A repository archive matches its manifest hash. |
| Signature valid | A supported cached MSI/EXE passed Windows Authenticode and the expected built-in publisher check. |

A built-in `Valid=True` cache entry is not a claim that its whole package chain was signature-verified. Office data, Teams MSIX and Adobe's outer ZIP are outside the specific MSI/EXE signature scope. Read the [Viewer status guide](viewer.md#integrity-and-signature-are-different-checks) and [publisher policy](built-in-apps.md#authenticode-and-publisher-policy-0340).

## Why did a signature or publisher check fail?

Read the actual status, signer and file path. Check the device clock and availability of Windows certificate trust/revocation data. A valid signature from an unexpected organization is not an approved built-in publisher. Do not edit the allowlist or bypass deployment checks just to make a status green.

On full Windows, inspect the existing cache without changing packages:

```powershell
Get-OSDAppCache -VerifySignatures |
    Select-Object Id, Valid, SignatureStatus, SignatureScope, SignatureSigner, SignatureDetail
```

The Viewer reports unsupported checks separately: WinPE does not invoke Windows Authenticode verification, repository ZIPs use their independent hash checks, and Adobe's outer ZIP is not assessed as a signed executable.

## What happens if Office refresh hangs?

The standalone Office refresh has a 20-minute timeout by default. On a failed refresh, an available staged Office fallback must still satisfy its source and ODT signature/publisher checks. Without an acceptable fallback, PreInstall fails before Runner starts. The timeout is not a promise that an arbitrary cached Office configuration can satisfy a changed deployment.

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
