# Getting started

[Documentation](README.md) · [Examples](../Examples/README.md) · [Troubleshooting](faq.md)

This guide separates the three environments used by OSDApps. The commands you run on a **full Windows preparation machine** are not the same commands you run against an **offline Windows target in WinPE**.

## Before you start

Run OSDApps after OSDCloud has applied the Windows image and before the first Windows boot. OSDApps does not replace Windows image deployment.

The examples target x64 and use the current Gallery release or the newest module version saved on your USB. Individual built-ins have different architecture options; consult [Built-in apps](built-in-apps.md) before changing them. The documented WinPE flow uses Windows PowerShell 5.1. The optional Viewer also needs Windows Forms, .NET and an STA PowerShell session.

Decide which source types you need:

| Choice | What you supply |
| --- | --- |
| Built-ins only | Select their dedicated `Add-OSDApp*` commands and configuration. No repository URL is needed. |
| Repository apps and scripts | Publish your own catalog, manifests and packages; configure the catalog URL and use actual app IDs from that repository. |
| Both | Add both types to the same ordered device queue. |

For an online deployment, vendor/repository access must be available when acquisition occurs. A fully offline deployment requires complete content for the selected app variants **before** reboot; supported MSI/EXE files must still pass Windows signature and expected-publisher validation.

## 1. Preparation machine — install or save the module

**Environment: full Windows.** Saving the module is optional for online deployment: the WinPE example below loads it directly from Gallery. Preparing the app cache is still required for Company Portal and CMTrace Open, as described below. Preparation can write module files and USB cache content. It must not stage apps against the preparation machine's Windows installation.

```powershell
Install-Module OSDApps -Force -SkipPublisherCheck
Import-Module OSDApps -Force
```

An OSDCloud cache volume is identified by its label, `OSDCloud` by default; its drive letter can change between machines. The cache is stored in `\OSDApps` on that volume. Storing the PowerShell module in `\Modules` keeps the module separate from installer content.

The [USB preparation example](../Examples/Prepare-UsbCache.md) saves the current Gallery release to the USB flash drive. It can also pre-cache Microsoft 365 Apps, Adobe Acrobat Unified and Google Chrome Enterprise. For those three apps, pre-caching is optional for online deployment, but necessary for the corresponding offline example. It never formats the USB flash drive; its optional repository cleanup is separated behind an explicit `-Prune` preview and confirmation.

Before reusing long-lived media, inspect it without changes:

```powershell
Get-OSDAppCacheHealth -Offline |
    Select-Object Healthy, ActiveCount, RenamedCount, IncompleteCount, CorruptCount
```

Repository owners can compare against their complete desired catalog and
preview transactional cleanup with `Sync-OSDAppRepository -Prune -WhatIf`.
See [Cache health and reconciliation](repository.md#cache-health-and-reconciliation)
before approving removals.

## 2. Target machine — stage in WinPE

**Environment: WinPE, after OSDCloud has applied Windows and before the first Windows boot.** Run this phase on the target machine, not the preparation machine.

Load the module from Gallery and add the intended apps. OSDApps discovers the offline Windows target automatically. Choose the appropriate workflow:

- [Online WinPE deployment](../Examples/WinPE-Online.md): use the current Gallery module with or without a USB flash drive; optionally add repository packages.
- [Offline WinPE deployment](../Examples/WinPE-Offline.md): validate the expected cache entries, stage them locally and skip repository refresh explicitly.

This complete online example needs PowerShellGet and Gallery access in WinPE:

```powershell
Install-Module OSDApps -Force -SkipPublisherCheck
Import-Module OSDApps -Force

Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language en-us
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
```

The defaults already use cache label `OSDCloud`, cleanup mode `OnSuccess` and automatic sleep prevention during PreInstall and Runner. Keep AC power connected; see [sleep prevention and its limits](runtime.md#automatic-sleep-prevention). No version pin, explicit Windows path or configuration call is needed for this example. `-SkipPublisherCheck` bypasses PowerShellGet's module publisher comparison; it does not disable OSDApps installer signature checks.

With an OSDCloud-labeled USB flash drive connected, matching cache content is staged as fallback and PreInstall can reuse or refresh it for built-ins that support first-boot acquisition. Leave the USB flash drive connected until OOBE appears. Without a USB flash drive, PreInstall downloads supported built-in content to local staging. Keep the PC online in either case. To test without cache, use only built-ins that support first-boot acquisition and disconnect the USB flash drive before staging on a fresh deployment; removing it after staging may leave cached fallback content on the target.

**Pre-cached exceptions:** Microsoft Company Portal and CMTrace Open must first be synchronized on a full-Windows preparation machine and staged in WinPE from the populated OSDCloud cache. Neither is downloaded during SetupComplete. For Company Portal, `Sync-OSDAppMicrosoftCompanyPortal -Architecture x64` downloads the official Microsoft kit automatically; `-KitPath` is only an optional local-kit fallback. Use `Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure` before reboot for these entries.

If you need different settings, `Set-OSDAppConfiguration` applies to the **current PowerShell session**. Set overrides before adding apps.

Both sources are enabled by default. Restrict one deployment session when needed:

```powershell
# Built-ins only
Set-OSDAppConfiguration -EnableRepository $false

# Repository/catalog packages only
Set-OSDAppConfiguration -EnableBuiltIns $false
```

At least one source must remain enabled. Explicit Add commands fail clearly when their source is disabled, while `Get-OSDApp` and the Viewer omit disabled sources. Sync commands remain available for cache preparation: source selection controls deployment/discovery, not whether an operator may prepare cache content. Registry staging is an OSDApps-owned built-in feature and therefore follows `EnableBuiltIns`.

Runtime settings, including source selection, are copied into the device manifest during staging; changing the session afterward does not rewrite an existing manifest by itself. If multiple Windows installations are found, specify `-WindowsPath` on the Add and preflight commands.

New app IDs are appended to `DeviceManifest.json` in the order they are added. Re-adding an existing ID replaces its entry and moves it to the end; it does not create another entry. Sorting the Viewer table does not change that order.

For repository apps, configure your actual catalog URL and use app IDs that it contains. `-SkipCacheRefresh` belongs to the generic repository `Add-OSDApp`; it does not control built-in freshness checks.

## 3. Inspect before reboot

**Environment: the same WinPE session.** Optionally run the deployment preflight after the last Add command:

```powershell
Test-OSDAppDeployment -ThrowOnFailure |
    Format-List Valid, OfflineReady, NetworkRequired, AppCount
```

`Valid=True` means the manifest, queue, SetupComplete integration, staged runtime and required repository packages passed. `OfflineReady=False` is allowed for an online cold deployment: it means content acquisition is needed. Most built-ins acquire content in PreInstall; Windows capability additions can require Windows Update during SetupComplete. For a deliberately disconnected deployment, make that a hard requirement:

```powershell
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

Optional read-only visual inspection:

```powershell
Show-OSDAppUI -Offline
```

Check the Windows target, app count/order and actual staged configuration. The Viewer does not change the queue or cache. Its `-Offline` option only disables online catalog lookup; it is not a deployment mode or a switch that disconnects networking.

The staging directory is normally:

```text
<Windows target>\Windows\Temp\OSDApps\
    DeviceManifest.json
    Invoke-OSDAppPreInstall.ps1
    Invoke-OSDAppRunner.ps1
    Restore-OSDAppCacheGeneration.ps1
    Assert-OSDAppTransactionSpace.ps1
    Enter-OSDAppCacheLock.ps1
    BuiltIn\
    Packages\
```

Built-in payloads can still be absent before the first boot in an online cold deployment. That is different from an offline deployment, where matching content must already be available. Repository packages are downloaded/staged before reboot, not acquired later by SetupComplete.

Close the Viewer before continuing the deployment. Keep the USB flash drive attached until OOBE is reached when it is part of the workflow. Use your existing deployment's reboot step, or the separate manual command in the online guide. Staging itself does not reboot the PC.

## 4. First Windows boot — let SetupComplete run

**Environment: deployed Windows, automatically through SetupComplete.** Do not launch the runtime scripts manually as an alternative to the normal deployment sequence.

PreInstall prepares the built-in content, validates supported installer signatures/publishers and uses a usable local fallback when refresh is unavailable. Runner then processes the full built-in/repository queue from local staging. A normal app-local acquisition or installer failure is recorded and does not prevent independent apps from being attempted. Integrity, trust and invalid-manifest failures remain blocking. The module does not need to be installed in this Windows installation.

A successful staging command is not a successful installation. SetupComplete is a one-shot execution: OSDApps does not automatically retry after a reboot or leave a scheduled task, RunOnce entry or service behind. A failed installer will normally leave a final `Failed` result and retained staging even when later queue entries succeeded.

## 5. Check the outcome

**Environment: deployed Windows after SetupComplete.** Read the saved result directly; installing the module or opening the Viewer is not required.

```powershell
$Result = Get-Content -LiteralPath "$env:ProgramData\OSDApps\Results\Latest.json" -Raw | ConvertFrom-Json
$Result | Format-List Status, SuccessfulAppCount, FailedAppCount, SkippedAppCount
$Result.Apps | Format-Table Id, PackageType, Status, ExitCode, DurationSeconds
$Result | Select-Object -ExpandProperty PreInstall -ErrorAction SilentlyContinue |
    Format-List Status, HasAcquisitionWarnings, FallbackAppCount, OfflineCacheAppCount
$Result.Apps | Format-Table Id, AcquisitionOutcome, RefreshFailureType
```

Check installation and acquisition separately: `Succeeded` means processing succeeded, while `FallbackCacheUsed` means a refresh failed and an acceptable cached payload was used. `OfflineCacheUsed` records intentionally or automatically detected offline use. `CacheReused` means vendor metadata allowed reuse; `Downloaded` records acquired content. Repository entries report `NotApplicable` for this built-in acquisition field. Older results may omit these fields or report `Unknown`.

If a refresh needs investigation, inspect its error without confusing it with the installer error:

```powershell
$Result.Apps |
    Where-Object AcquisitionOutcome -eq 'FallbackCacheUsed' |
    Format-List Id, Status, AcquisitionOutcome, RefreshFailureType, RefreshError, Error
```

See [acquisition outcomes](runtime.md#acquisition-and-installation-are-separate-results) for the full field definitions. You can also copy `Latest.json` to the preparation PC and use the [read-only maintenance check](maintenance.md#inspect-a-saved-deployment-result).

The default persistent runtime log is:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

When the OSDApps module is available, read the atomic machine result first:

```powershell
$Result = Get-OSDAppDeploymentResult
$Result | Format-List Status, DeploymentId, SuccessfulAppCount, FailedAppCount, SkippedAppCount, DurationSeconds
$Result.Apps | Format-Table Id, Status, AcquisitionOutcome, FailureType, ExitCode, Version, DurationSeconds
```

The default file is `%ProgramData%\OSDApps\Results\Latest.json`. It remains outside local staging, so `CleanupMode OnSuccess` does not remove it. Without the module, the JSON can be read with `Get-Content -Raw | ConvertFrom-Json`.

Read detailed events in a PowerShell window:

```powershell
$Log = Join-Path $env:ProgramData 'OSDApps\Logs\Runtime.log'
if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) {
    throw "Runtime log not found: $Log"
}

Get-Content -LiteralPath $Log |
    Select-String 'AppAcquisitionComplete|BuiltInSignatureVerified|BuiltInRefreshSkipped|BuiltInRefreshFailed|AppRefreshFailed|PreInstallComplete|AppInstallComplete|AppInstallFailed|AppInstallSkipped|InstallComplete|InstallCompletedWithErrors|RefreshFailed|InstallFailed'
```

Look for individual install/provisioning outcomes and exactly one final `InstallComplete`, `InstallCompletedWithErrors` or `InstallFailed` outcome. In an intentionally offline deployment, `BuiltInRefreshSkipped` reports use of existing staged content; it is recorded as a warning, not an installer failure.

With `CleanupMode OnSuccess`, the runtime schedules removal of temporary staging after a successful run; persistent logs remain at the configured log path. `CleanupMode Never` retains staging for troubleshooting. A failed run retains its source. See [Runtime and cleanup](runtime.md).

## Next steps

[Built-in configuration](built-in-apps.md) covers Office licensing flags, channels, language, Firefox variants, Webex options and Zoom settings. [Repository apps and scripts](repository.md) explains organization-managed packages and optional Vendor metadata. [Viewer](viewer.md) explains the difference between staged, cached, version and signature information.
