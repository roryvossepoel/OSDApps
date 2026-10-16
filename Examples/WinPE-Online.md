# Online WinPE deployment

[Examples](README.md) · [USB preparation](Prepare-UsbCache.md) · [Offline alternative](WinPE-Offline.md)

**Run on the target PC in WinPE after OSDCloud has applied Windows, before its first Windows boot.** Do not run this on the full-Windows preparation machine.

This example uses the current PowerShell Gallery release and three x64 built-ins. WinPE needs PowerShellGet and Gallery access. Keep the PC online until OOBE appears. A USB flash drive is optional; no module copy on the USB flash drive is required.

## 1. Import the module and stage built-ins

```powershell
Install-Module OSDApps -Force -SkipPublisherCheck
Import-Module OSDApps -Force

Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language en-us
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
```

Change the Office channel and language to suit your deployment. OSDApps discovers the offline Windows installation automatically. If multiple installations are found, specify the intended root with `-WindowsPath` on each Add command and on the preflight check.

The defaults already select the `OSDCloud` cache label and `OnSuccess` cleanup. `-SkipPublisherCheck` bypasses PowerShellGet's module publisher comparison; it does not disable OSDApps installer signature checks.

### With a USB flash drive

Connect the OSDCloud-labeled USB flash drive before staging and leave it connected until OOBE appears. Matching cached content is staged as fallback. During SetupComplete, PreInstall checks vendor sources and can reuse or refresh the cache. A connected USB flash drive does not disable online update checks.

### Without a USB flash drive

For a fresh deployment without cache, disconnect the USB flash drive **before running the staging commands** and leave it disconnected through SetupComplete. Existing USB flash drive content is preserved. PreInstall downloads the built-in payloads directly to local Windows staging during the first boot.

Removing the USB flash drive only after staging is not a clean no-cache test: cached content may already have been copied to the target.

## 2. Optionally add your repository app

**Run in the same WinPE session, after step 1.** Skip this section for the three-built-in example. Repository packages are synchronized and staged now, before reboot, not downloaded later by Runner.

```powershell
$CatalogUri = Read-Host 'Enter the HTTPS URL of your repository catalog.json'
$RepoAppId = Read-Host 'Enter an application Id present in that repository'

Set-OSDAppConfiguration -CatalogUri $CatalogUri
Add-OSDApp -Name $RepoAppId
```

Use your own published catalog and app Id. Notepad++ and Omnissa Horizon Client are examples of user-supplied packages, not built-ins supplied by OSDApps. The same command stages a repository package classified as `Script`.

## 3. Review before continuing

Optionally run the preflight after the last Add command:

```powershell
Test-OSDAppDeployment -ThrowOnFailure
```

If you run this check, resolve any reported failure before rebooting. For a fresh built-in deployment without cache, `OfflineReady=False` and `NetworkRequired=True` are expected; `Valid=True` means staging passed, not that installation has happened.

Optionally inspect the queue in the read-only Viewer:

```powershell
Show-OSDAppUI -Offline
```

Expect Microsoft 365 Apps first, Adobe Acrobat Unified second and Google Chrome Enterprise third, followed by a repository app only if step 2 was used. The Viewer needs Windows Forms and an STA session. Its `-Offline` switch limits repository lookup; it does not change deployment networking.

Close the Viewer and continue your normal deployment reboot after staging completes without errors. To reboot manually from WinPE:

```powershell
wpeutil reboot
```

SetupComplete runs the queue during the first Windows boot. Do not rerun staging to bypass a partial failure; inspect the reported error first. Successful runs remove temporary staging and retain logs and results.

## 4. Confirm the installation result in Windows

After SetupComplete, use the [Getting started log check](../docs/getting-started.md#5-check-the-outcome). Review individual installer results, acquisition outcomes and `InstallComplete`, not just the WinPE staging output.
