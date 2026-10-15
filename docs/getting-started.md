# Getting started

[Documentation](README.md) · [Examples](../Examples/README.md) · [Troubleshooting](faq.md)

This guide separates the three environments used by OSDApps. The commands you run on a **full Windows preparation machine** are not the same commands you run against an **offline Windows target in WinPE**.

## Before you start

Use an OSDCloud v2 deployment that leaves time to stage applications after the Windows image has been applied and before the first Windows boot. OSDApps does not replace Windows image deployment.

The examples target x64 and use the current Gallery release or the newest module version saved on your USB. Individual built-ins have different architecture options; consult [Built-in applications](built-in-apps.md) before changing them. The documented WinPE flow uses Windows PowerShell 5.1. The optional Viewer also needs Windows Forms, .NET and an STA PowerShell session.

Decide which source types you need:

| Choice | What you supply |
| --- | --- |
| Built-ins only | Select their dedicated `Add-OSDApp*` commands and configuration. No repository URL is needed. |
| Repository apps and scripts | Publish your own catalog, manifests and packages; configure the catalog URL and use actual app IDs from that repository. |
| Both | Add both types to the same ordered device queue. |

For an online deployment, vendor/repository access must be available when acquisition occurs. A fully offline deployment requires complete content for the selected app variants **before** reboot; supported MSI/EXE files must still pass Windows signature and expected-publisher validation.

## 1. Preparation machine — install or save the module

**Environment: full Windows.** This phase can write module files and USB cache content. It must not stage applications against the preparation machine's Windows installation.

```powershell
Install-Module OSDApps
Import-Module OSDApps
```

An OSDCloud cache volume is identified by its label, `OSDCloud` by default; its drive letter can change between machines. The cache is stored in `\OSDApps` on that volume. Storing the PowerShell module in `\Modules` keeps the module separate from installer content.

The [USB preparation example](../Examples/Prepare-UsbCache.md) saves the current Gallery release to the stick. It can also pre-cache Microsoft 365 Apps, Adobe Acrobat Unified and Google Chrome Enterprise. Pre-caching is optional for online deployment, but necessary for the corresponding offline example. It never formats the stick; its optional repository cleanup is separated behind an explicit `-Prune` preview and confirmation.

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

Load the saved module, identify the offline Windows target and then add the intended applications. The complete examples handle USB/target discovery and refuse to run outside WinPE:

- [Online WinPE deployment](../Examples/WinPE-Online.md): prepare built-ins for vendor acquisition and optionally synchronize repository packages.
- [Offline WinPE deployment](../Examples/WinPE-Offline.md): validate the expected cache entries, stage them locally and skip repository refresh explicitly.

`Set-OSDAppConfiguration` applies to the **current PowerShell session**. Set the required values in the same session before adding apps. Runtime values such as `CleanupMode`, `CacheVolumeLabel`, `LogPath` and `ResultPath` are copied into the device manifest during staging; changing the session later does not rewrite an already staged manifest by itself.

```powershell
# WinPE staging session, after importing OSDApps:
Set-OSDAppConfiguration -CleanupMode OnSuccess

Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language en-us
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
```

New app IDs are appended to `DeviceManifest.json` in the order they are added. Re-adding an existing ID replaces its entry and moves it to the end; it does not create another entry. Sorting the Viewer table does not change that order.

For repository apps, configure your actual catalog URL and use app IDs that it contains. `-SkipCacheRefresh` belongs to the generic repository `Add-OSDApp`; it does not control built-in freshness checks.

## 3. Inspect before reboot

**Environment: the same WinPE session.** Run the deployment preflight after the last Add command:

```powershell
$Preflight = Test-OSDAppDeployment -WindowsPath 'C:\'
$Preflight | Format-List Valid, OfflineReady, NetworkRequired, ApplicationCount

if (-not $Preflight.Valid) {
    $Preflight.Checks | Where-Object { $_.Required -and -not $_.Passed }
    throw 'OSDApps staging did not pass preflight.'
}
```

`Valid=True` means the manifest, queue, SetupComplete integration, staged runtime and required repository packages passed. `OfflineReady=False` is allowed for an online cold deployment: it means PreInstall must acquire one or more built-ins. For a deliberately disconnected deployment, make that a hard requirement:

```powershell
Test-OSDAppDeployment -WindowsPath 'C:\' -RequireOfflineReady -ThrowOnFailure
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
    BuiltIn\
    Packages\
```

Built-in payloads can still be absent before the first boot in an online cold deployment. That is different from an offline deployment, where matching content must already be available. Repository packages are downloaded/staged before reboot, not acquired later by SetupComplete.

Close the Viewer before continuing the deployment. Keep the cache USB attached until OOBE is reached when it is part of the workflow. Use your existing OSDCloud deployment's reboot step; the examples do not trigger it automatically.

## 4. First Windows boot — let SetupComplete run

**Environment: deployed Windows, automatically through SetupComplete.** Do not launch the runtime scripts manually as an alternative to the normal deployment sequence.

PreInstall prepares the built-in content, validates supported installer signatures/publishers and uses a usable local fallback when refresh is unavailable. Runner then processes the full built-in/repository queue from local staging. A normal app-local acquisition or installer failure is recorded and does not prevent independent applications from being attempted. Integrity, trust and invalid-manifest failures remain blocking. The module does not need to be installed in this Windows installation.

A successful staging command is not a successful installation. SetupComplete is a one-shot execution: OSDApps does not automatically retry after a reboot or leave a scheduled task, RunOnce entry or service behind. A failed installer will normally leave a final `Failed` result and retained staging even when later queue entries succeeded.

## 5. Check the outcome

**Environment: deployed Windows after SetupComplete.** Read the saved result directly; installing the module or opening the Viewer is not required.

```powershell
$Result = Get-Content -LiteralPath "$env:ProgramData\OSDApps\Results\Latest.json" -Raw | ConvertFrom-Json
$Result | Format-List Status, SuccessfulApplicationCount, FailedApplicationCount, SkippedApplicationCount
$Result.Applications | Format-Table Id, PackageType, Status, ExitCode, DurationSeconds
```

The default persistent runtime log is:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

When the OSDApps module is available, read the atomic machine result first:

```powershell
$Result = Get-OSDAppDeploymentResult
$Result | Format-List Status, DeploymentId, SuccessfulApplicationCount, FailedApplicationCount, SkippedApplicationCount, DurationSeconds
$Result.Applications | Format-Table Id, Status, FailureType, ExitCode, Version, DurationSeconds
```

The default file is `%ProgramData%\OSDApps\Results\Latest.json`. It remains outside local staging, so `CleanupMode OnSuccess` does not remove it. Without the module, the JSON can be read with `Get-Content -Raw | ConvertFrom-Json`.

Read detailed events in a PowerShell window:

```powershell
$Log = Join-Path $env:ProgramData 'OSDApps\Logs\Runtime.log'
if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) {
    throw "Runtime log not found: $Log"
}

Get-Content -LiteralPath $Log |
    Select-String 'BuiltInSignatureVerified|BuiltInRefreshSkipped|BuiltInRefreshFailed|ApplicationRefreshFailed|PreInstallComplete|ApplicationInstallComplete|ApplicationInstallFailed|ApplicationInstallSkipped|InstallComplete|InstallCompletedWithErrors|RefreshFailed|InstallFailed'
```

Look for individual install/provisioning outcomes and exactly one final `InstallComplete`, `InstallCompletedWithErrors` or `InstallFailed` outcome. In an intentionally offline deployment, `BuiltInRefreshSkipped` reports use of existing staged content; it is recorded as a warning, not an installer failure.

With `CleanupMode OnSuccess`, the runtime schedules removal of temporary staging after a successful run; persistent logs remain at the configured log path. `CleanupMode Never` retains staging for troubleshooting. A failed run retains its source. See [Runtime and cleanup](runtime.md).

## Next steps

[Built-in configuration](built-in-apps.md) covers Office licensing flags, channels, language, Firefox variants and Webex options. [Repository applications](repository.md) explains organization-managed packages and optional Vendor metadata. [Viewer](viewer.md) explains the difference between staged, cached, version and signature information.
