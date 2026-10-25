# CMTrace Open (built-in test candidate)

This optional built-in installs the CMTrace Open MSI sourced directly from [adamgell/cmtraceopen GitHub releases](https://github.com/adamgell/cmtraceopen/releases). No binary is committed to OSDApps.

## Full Windows preparation

```powershell
Import-Module OSDApps
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud
Sync-OSDAppCMTraceOpen -Architecture x64
```

The synchronizer reads the latest **stable** release from the exact upstream GitHub repository, requires a matching architecture-specific MSI, compares downloaded bytes with the asset's official SHA-256 digest and checks the MSI Authenticode signature. Cached content remains unchanged if a download fails.

The confirmed upstream release on 24 October 2026 is **1.6.3**. Upstream asset SHA-256 values:
- x64: `C6529792AA13761A432FF93B91E13816FF991DDD53E9E59FFE1D3588D7251B45`
- ARM64: `D7ED45A451FA3D3ADEB4AEC4A8DECC3FC4B27BA6B9D6FB94F1C99023AC9BFDD8`

## WinPE

```powershell
Import-Module OSDApps
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess
Add-OSDAppCMTraceOpen -Architecture x64 -DisableUpdateChecks $true
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

The current candidate uses a **pre-synchronized MSI**, rather than downloading the MSI during SetupComplete. It reuses the existing built-in VendorMsi runner with `/qn /norestart` and optional `DISABLEUPDATECHECKS=1`. MSI hash and Authenticode checks run again before installation.

## Test gates

- PowerShell 5.1 / 7 CI; staging tests and MSI integrity failures
- Real full-Windows sync, official SHA-256 and Authenticode check
- WinPE → SetupComplete → OOBE x64 deployment
- ARM64 deployment separately; installed MSI version and update-check setting
