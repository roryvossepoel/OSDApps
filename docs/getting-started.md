# Getting started

[Documentation](README.md) · [Examples](../Examples/README.md) · [Troubleshooting](faq.md)

Run the Add commands in WinPE after Windows has been applied. The documented examples use OSDCloud because OSDStage was designed around that workflow, but OSDCloud is not a technical dependency. OSDStage prepares the queue; SetupComplete installs it before OOBE. A separate preparation PC is optional for online deployments.

## Before you start

Run OSDStage after the Windows image has been applied and before the first Windows boot. OSDStage does not replace Windows image deployment, Microsoft Entra join, Intune enrollment or Autopilot. OSDCloud is the primary documented companion workflow, but another deployment method can be used when it leaves a supported offline Windows target available for staging before first boot.

OSDStage 1.0.0-rc4 is the current release candidate. Check [release availability](release-status.md) when upgrading from RC1 or testing newer development changes. Preview installation requires PowerShellGet 1.6 or later and `-AllowPrerelease`.

The examples target x64. Individual built-ins have different architecture options; consult [Built-in apps](built-in-apps.md) before changing them. The documented WinPE flow uses Windows PowerShell 5.1. The optional Viewer also needs Windows Forms, .NET and an STA PowerShell session.

Decide which source types you need:

| Choice | What you supply |
| --- | --- |
| Built-ins only | Select their dedicated `Add-OSDStage*` commands and configuration. No repository URL is needed. |
| Repository packages | Publish your own catalog, manifests and packages; configure the catalog URL and use actual package IDs from that repository. |
| Both | Add both types to the same ordered device queue. |

For an online deployment, vendor/repository access must be available when acquisition occurs. A fully offline deployment requires complete content for the selected app variants **before** reboot; supported MSI/EXE files must still pass Windows signature and expected-publisher validation.

## Choose your route

| Deployment | Start here |
| --- | --- |
| Online, module already included by the launcher | [Stage in WinPE](#2-target-machine--stage-in-winpe) |
| Online, module not loaded yet | Install from Gallery in the WinPE example below |
| Fully offline | [Prepare the module and matching cache](../Examples/WinPE-Offline.md) |
| Read results on the deployed PC | [Check the outcome](#5-check-the-outcome) |

## 1. Preparation machine — install or save the module

**Environment: full Windows.** Saving the module is optional for online deployment: the WinPE example below loads it directly from Gallery. Company Portal and CMTrace Open support automatic online acquisition. Preparation can write module files and USB cache content. It must not stage apps against the preparation machine's Windows installation.

```powershell
Install-Module OSDStage -Repository PSGallery -AllowPrerelease -Force -ErrorAction Stop
Import-Module OSDStage -Force
```

An OSDCloud cache volume is identified by its label, `OSDCloud` by default; its drive letter can change between machines. The cache is stored in `\OSDStage` on that volume. Storing the PowerShell module in `\Modules` keeps the module separate from installer content.

The [USB preparation example](../Examples/Prepare-UsbCache.md) saves the current Gallery release to the USB flash drive. It can also pre-cache Microsoft 365 Apps, Adobe Acrobat Unified and Google Chrome Enterprise. For those three apps, pre-caching is optional for online deployment, but necessary for the corresponding offline example. It never formats the USB flash drive; its optional repository cleanup is separated behind an explicit `-Prune` preview and confirmation.

Before reusing long-lived media, inspect it without changes:

```powershell
Get-OSDStageCacheHealth -Offline |
    Select-Object Healthy, ActiveCount, RenamedCount, IncompleteCount, CorruptCount
```

Repository owners can compare against their complete desired catalog and
preview transactional cleanup with `Sync-OSDStageRepository -Prune -WhatIf`.
See [Cache health and reconciliation](repository.md#cache-health-and-reconciliation)
before approving removals.

## 2. Target machine — stage in WinPE

**Environment: WinPE, after Windows has been applied and before the first Windows boot.** The examples use OSDCloud, but the staging contract is the same for another deployment method that exposes a supported offline Windows target. Run this phase on the target machine, not the preparation machine.

Load the module from Gallery and add the intended apps. OSDStage discovers the offline Windows target automatically. Choose the appropriate workflow:

- [Online WinPE deployment](../Examples/WinPE-Online.md): use the current Gallery module with or without a USB flash drive; optionally add repository packages.
- [Offline WinPE deployment](../Examples/WinPE-Offline.md): validate the expected cache entries, stage them locally and skip repository refresh explicitly.

This complete online example needs PowerShellGet and Gallery access in WinPE:

```powershell
Install-Module OSDStage -Repository PSGallery -AllowPrerelease -Force -ErrorAction Stop
Import-Module OSDStage -Force

Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language en-us
Add-OSDStageAdobeAcrobatUnified
Add-OSDStageGoogleChromeEnterprise
```

The defaults already use cache label `OSDCloud`, cleanup mode `OnSuccess` and automatic sleep prevention during PreInstall and Runner. Keep AC power connected; see [sleep prevention and its limits](runtime.md#automatic-sleep-prevention). No version pin, explicit Windows path or configuration call is needed for this example. `-SkipPublisherCheck` bypasses PowerShellGet's module publisher comparison; it does not disable OSDStage installer signature checks.

With an OSDCloud-labeled USB flash drive connected, matching cache content is staged as fallback and PreInstall can reuse or refresh it for built-ins that support first-boot acquisition. Leave the USB flash drive connected until OOBE appears. Without a USB flash drive, PreInstall downloads supported built-in content to local staging. Keep the PC online in either case. To test without cache, use only built-ins that support first-boot acquisition and disconnect the USB flash drive before staging on a fresh deployment; removing it after staging may leave cached fallback content on the target.

**Company Portal and CMTrace Open:** both follow the automatic online PreInstall acquisition and cache-refresh flow. For a fully offline deployment, every selected app needs verified content and `Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure`. See [release availability](release-status.md).

If you need different settings, `Set-OSDStageConfiguration` applies to the **current PowerShell session**. Set overrides before adding apps.

Both sources are enabled by default. Restrict one deployment session when needed:

```powershell
# Built-ins only
Set-OSDStageConfiguration -EnableRepository $false

# Repository/catalog packages only
Set-OSDStageConfiguration -EnableBuiltIns $false
```

At least one source must remain enabled. Explicit Add commands fail clearly when their source is disabled, while `Get-OSDStage` and the Viewer omit disabled sources. Sync commands remain available for cache preparation: source selection controls deployment/discovery, not whether an operator may prepare cache content. Registry staging is an OSDStage-owned built-in feature and therefore follows `EnableBuiltIns`.

Runtime settings, including source selection, are copied into the device manifest during staging; changing the session afterward does not rewrite an existing manifest by itself. If multiple Windows installations are found, specify `-WindowsPath` on the Add and preflight commands.

New app IDs are appended to `DeviceManifest.json` in staging order. Runtime prerequisites are placed before apps. Re-adding an existing app ID replaces its entry; it does not create a duplicate. Configuration commands can combine several operations into one entry; see each guide for its ordering rules. Sorting the Viewer table does not change that order.

For repository apps, configure your actual catalog URL and use app IDs that it contains. `-SkipCacheRefresh` belongs to the generic repository `Add-OSDStage`; it does not control built-in freshness checks.

## 3. Inspect before reboot

**Environment: the same WinPE session.** Optionally run the deployment preflight after the last Add command:

```powershell
Test-OSDStageDeployment -ThrowOnFailure |
    Format-List Valid, OfflineReady, NetworkRequired, PackageCount
```

`Valid=True` means the manifest, queue, SetupComplete integration, staged runtime and required repository packages passed. `OfflineReady=False` is allowed for an online cold deployment: it means content acquisition is needed. Most built-ins acquire content in PreInstall; Windows capability additions can require Windows Update during SetupComplete. For a deliberately disconnected deployment, make that a hard requirement:

```powershell
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

Optional read-only visual inspection:

```powershell
Show-OSDStageUI -Offline
```

Check the Windows target, app count/order and actual staged configuration. The Viewer does not change the queue or cache. Its `-Offline` option only disables online catalog lookup; it is not a deployment mode or a switch that disconnects networking.

The staging directory is normally:

```text
<Windows target>\Windows\Temp\OSDStage\
    DeviceManifest.json
    Invoke-OSDStagePreInstall.ps1
    Invoke-OSDStageRunner.ps1
    Restore-OSDStageCacheGeneration.ps1
    Assert-OSDStageTransactionSpace.ps1
    Enter-OSDStageCacheLock.ps1
    BuiltIn\
    Packages\
```

Built-in payloads can still be absent before the first boot in an online cold deployment. That is different from an offline deployment, where matching content must already be available. Repository packages are downloaded/staged before reboot, not acquired later by SetupComplete.

Close the Viewer before continuing the deployment. Keep the USB flash drive attached until OOBE is reached when it is part of the workflow. Use your existing deployment's reboot step, or the separate manual command in the online guide. Staging itself does not reboot the PC.

## 4. First Windows boot — let SetupComplete run

**Environment: deployed Windows, automatically through SetupComplete.** Do not launch the runtime scripts manually as an alternative to the normal deployment sequence.

PreInstall prepares the built-in content, validates supported installer signatures/publishers and uses a usable local fallback when refresh is unavailable. Runner then processes the full built-in/repository queue from local staging. A normal app-local acquisition or installer failure is recorded and does not prevent independent apps from being attempted. Integrity, trust and invalid-manifest failures remain blocking. The module does not need to be installed in this Windows installation.

A successful staging command is not a successful installation. SetupComplete is a one-shot execution: OSDStage does not automatically retry after a reboot or leave a scheduled task, RunOnce entry or service behind. A failed installer will normally leave a final `Failed` result and retained staging even when later queue entries succeeded.

## 5. Check the outcome

**Environment: deployed Windows after SetupComplete.** Start with the automatic [delivery report](delivery-report.md); installing the module or opening the Viewer is not required.

```powershell
$results = Join-Path $env:ProgramData 'OSDStage\Results'
Start-Process (Join-Path $results 'DeliveryReport.html')
```

The offline HTML groups built-in and repository apps separately, with individual cards for configurations and expandable component details. The same folder contains `DeliveryReport.json` for structured inspection. If no browser is available in OOBE, read the JSON from an elevated console or copy the HTML to your preparation PC. A custom runtime result path also relocates these sibling reports.

Check both execution and follow-up status. `Attention` can mean a required restart or later update scan even when execution succeeded. The report records this run and does not refresh automatically after restart. Review identifying fields before sharing it.

For the original runtime result and acquisition details:

```powershell
$Result = Get-Content -LiteralPath "$env:ProgramData\OSDStage\Results\Latest.json" -Raw | ConvertFrom-Json
$Result | Format-List Status, SuccessfulPackageCount, FailedPackageCount, SkippedPackageCount
$Result.Packages | Format-Table Id, PackageType, Status, ExitCode, DurationSeconds
$Result | Select-Object -ExpandProperty PreInstall -ErrorAction SilentlyContinue |
    Format-List Status, HasAcquisitionWarnings, FallbackPackageCount, OfflineCachePackageCount
$Result.Packages | Format-Table Id, AcquisitionOutcome, RefreshFailureType
```

Check installation and acquisition separately: `Succeeded` means processing succeeded, while `FallbackCacheUsed` means a refresh failed and an acceptable cached payload was used. `OfflineCacheUsed` records intentionally or automatically detected offline use. `CacheReused` means vendor metadata allowed reuse; `Downloaded` records acquired content. Repository entries report `NotApplicable` for this built-in acquisition field. Older results may omit these fields or report `Unknown`.

If a refresh needs investigation, inspect its error without confusing it with the installer error:

```powershell
$Result.Packages |
    Where-Object AcquisitionOutcome -eq 'FallbackCacheUsed' |
    Format-List Id, Status, AcquisitionOutcome, RefreshFailureType, RefreshError, Error
```

See [acquisition outcomes](runtime.md#acquisition-and-installation-are-separate-results) for the full field definitions. You can also copy `Latest.json` to the preparation PC and use the [read-only maintenance check](maintenance.md#inspect-a-saved-deployment-result).

The default persistent runtime log is:

```text
%ProgramData%\OSDStage\Logs\Runtime.log
```

When the OSDStage module is available, read the atomic machine result first:

```powershell
$Result = Get-OSDStageDeploymentResult
$Result | Format-List Status, DeploymentId, SuccessfulPackageCount, FailedPackageCount, SkippedPackageCount, DurationSeconds
$Result.Packages | Format-Table Id, Status, AcquisitionOutcome, FailureType, ExitCode, Version, DurationSeconds
```

The default file is `%ProgramData%\OSDStage\Results\Latest.json`. It remains outside local staging, so `CleanupMode OnSuccess` does not remove it. Without the module, the JSON can be read with `Get-Content -Raw | ConvertFrom-Json`.

Read detailed events in a PowerShell window:

```powershell
$Log = Join-Path $env:ProgramData 'OSDStage\Logs\Runtime.log'
if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) {
    throw "Runtime log not found: $Log"
}

Get-Content -LiteralPath $Log |
    Select-String 'AppAcquisitionComplete|BuiltInSignatureVerified|BuiltInRefreshSkipped|BuiltInRefreshFailed|AppRefreshFailed|PreInstallComplete|AppInstallComplete|AppInstallFailed|AppInstallSkipped|InstallComplete|InstallCompletedWithErrors|RefreshFailed|InstallFailed'
```

Look for individual install/provisioning outcomes and exactly one final `InstallComplete`, `InstallCompletedWithErrors` or `InstallFailed` outcome. In an intentionally offline deployment, `BuiltInRefreshSkipped` reports use of existing staged content; it is recorded as a warning, not an installer failure.

With `CleanupMode OnSuccess`, the runtime schedules removal of temporary staging after a successful run; persistent logs remain at the configured log path. `CleanupMode Never` retains staging for troubleshooting. A failed run retains its source. See [Runtime and cleanup](runtime.md).

## Next steps

[Built-in configuration](built-in-apps.md) covers Office licensing flags, channels, language, Firefox variants, Webex options and Zoom settings. [Repository packages](repository.md) explains organization-managed packages and optional Vendor metadata. [Viewer](viewer.md) explains the difference between staged, cached, version and signature information.
