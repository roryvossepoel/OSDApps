# Microsoft Company Portal (built-in)

This optional integration provisions the official Microsoft Company Portal Preinstall Kit for **future Windows user profiles** during SetupComplete. OSDStage includes no Microsoft app binaries or licenses. WinPE stages deployment intent and any validated cached kit. During SetupComplete, PreInstall checks the official kit and refreshes the connected OSDCloud cache automatically, or downloads to the local Windows disk when no USB is present.

## Optional cache preparation (full Windows)

For a fully offline deployment, connect the OSDCloud USB device and run:


~~~powershell
Import-Module OSDStage
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud

# Default: download the official kit directly from Microsoft's Download Center.
Sync-OSDStageMicrosoftCompanyPortal -Architecture x64
~~~

The automatic source is an official `download.microsoft.com` Preinstall Kit ZIP. OSDStage records its source URI and SHA-256, extracts the appxbundle, offline license and five architecture-specific Appx dependencies, reads the Microsoft Company Portal package identity and version, preserves the kit bundle/license/dependency filenames, and records individual file hashes. `PayloadFileName` and `LicenseFileName` record the exact bundle and license names. A download or validation failure does not replace the previous cache; an automatic refresh can reuse content only after checking cached file hashes. The actual Appx signature is validated by Windows when provisioning.

An operator-supplied kit is also supported, with **no automatic download**:


~~~powershell
Sync-OSDStageMicrosoftCompanyPortal -KitPath 'C:\Temp\CompanyPortal-Universal-Production_x64_x86_ARM_ARM64.appxupload_Windows10_PreinstallKit.zip' -Architecture x64
~~~

The tested Microsoft kit contained Company Portal **11.2.1495.0**. That is an observed bundle version, not a guarantee that the Microsoft download URL always serves the latest Microsoft Store version.

## WinPE after OSDCloud


~~~powershell
Import-Module OSDStage
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess
Add-OSDStageMicrosoftCompanyPortal -Architecture x64
Test-OSDStageDeployment -ThrowOnFailure
~~~

During first boot, SetupComplete uses `Add-AppxProvisionedPackage -Online` with the app bundle, offline license and five dependencies, using `-Regions all`. Company Portal is then available to provision for new user profiles. Check after Autopilot sign-in:


~~~powershell
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq 'Microsoft.CompanyPortal'
Get-AppxPackage -Name Microsoft.CompanyPortal | Select-Object Name, Version, Status
~~~

## Validation and boundaries

- Windows PowerShell 5.1 and 7 CI passed on PR #67.
- Physical x64 staging, offline provisioning and post-Autopilot user registration succeeded on PC1.
- A separate full-Windows x64 test downloaded the kit directly from Microsoft with **no** `-KitPath`: `Updated=True`, `CacheReused=False`, seven cached files, version 11.2.1495.0.
- WinPE does not download the kit. Online PreInstall checks HTTP ETag (or Last-Modified plus content length), validates cached files and downloads when changed or when usable metadata is unavailable. Fully offline deployment still requires prepared content and `Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure`.
- Automatic PreInstall acquisition is a new path; the historical physical tests above covered prepared-cache installation. Validate cold-cache and refreshed-cache runs before release.
- ARM64 uses `-Architecture arm64` with the same Microsoft kit, but has **not** been physically tested. Interactive Intune registration and Store-update behavior were not separately validated by the preparation test.
