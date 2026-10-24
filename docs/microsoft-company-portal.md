# Microsoft Company Portal (built-in test candidate)

This integration provisions the official Microsoft Company Portal Preinstall Kit for **future Windows user profiles** during SetupComplete. The OSDApps module contains **no Microsoft application binaries or licenses**. The operator obtains the kit from Microsoft's official download center and places its contents into the OSDCloud USB cache with `Sync-OSDAppMicrosoftCompanyPortal`.

## Preparation PC (full Windows)

```powershell
Import-Module OSDApps
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud
Sync-OSDAppMicrosoftCompanyPortal -KitPath 'C:\Temp\CompanyPortal-Universal-Production_x64_x86_ARM_ARM64.appxupload_Windows10_PreinstallKit.zip' -Architecture x64
```

This operation validates that the ZIP has exactly one Company Portal appbundle, an offline license, and one x64 dependency package for each of five known dependency families. It reads the Microsoft.CompanyPortal version from the bundle manifest. The supplied kit tested for this candidate contained bundle version **11.2.1495.0** (not the older 11.2.1393.0 listed in some descriptions).

## WinPE after OSDCloud

```powershell
Import-Module OSDApps
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess
Add-OSDAppMicrosoftCompanyPortal -Architecture x64
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

During first boot, SetupComplete runs `Add-AppxProvisionedPackage -Online` with the appbundle, offline license and five x64 Appx dependency packages, using `-Regions all`. Appx signature validation is handled by Windows provisioning. Windows 11 build and license compatibility must be verified on a disposable deployment target. After first user login, verify `Get-AppxPackage -Name Microsoft.CompanyPortal`, as provisioning alone is not proof of user registration.

The prepare/sync phase is intentionally **offline-source only**. The Microsoft download page provides a kit file, not a documented evergreen MSI endpoint. No external download is performed during WinPE or SetupComplete. For ARM64, synchronize and stage `-Architecture arm64` using the same vendor kit; test separately.

## Test gates

- Windows PowerShell 5.1 parser and Pester tests
- Cache structure and SHA-256 validation
- Unmodified deployment manifest and preflight
- New user profile registration after Autopilot
- Microsoft Store update behavior / version compatibility
- No installation if offline cache is incomplete
