# CMTrace Open (built-in)

This optional built-in installs the CMTrace Open MSI sourced directly from [adamgell/cmtraceopen GitHub releases](https://github.com/adamgell/cmtraceopen/releases). No binary is committed to OSDStage.

## Full Windows preparation

```powershell
Import-Module OSDStage
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud
Sync-OSDStageCMTraceOpen -Architecture x64
```

The synchronizer reads the latest **stable** release from the exact upstream GitHub repository, requires a matching architecture-specific MSI, compares downloaded bytes with the asset's official SHA-256 digest and checks the MSI Authenticode signature. Cached content remains unchanged if a download fails.

The confirmed upstream release on 24 October 2026 is **1.6.3**. Upstream asset SHA-256 values:
- x64: `C6529792AA13761A432FF93B91E13816FF991DDD53E9E59FFE1D3588D7251B45`
- ARM64: `D7ED45A451FA3D3ADEB4AEC4A8DECC3FC4B27BA6B9D6FB94F1C99023AC9BFDD8`

## WinPE

```powershell
Import-Module OSDStage
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess
Add-OSDStageCMTraceOpen -Architecture x64 -DisableUpdateChecks $true
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

The built-in uses a **pre-synchronized MSI**, rather than downloading the MSI during SetupComplete. OSDStage retains the upstream vendor filename (for x64 release 1.6.3, `CMTrace-Open_1.6.3_x64.msi`). Build a fresh cache; no generic-filename cache is accepted or converted. It reuses the existing built-in VendorMsi runner with `/qn /norestart` and optional `DISABLEUPDATECHECKS=1`. MSI hash and Authenticode checks run again before installation.

## Validation and remaining tests

- Windows PowerShell 5.1 and 7 CI passed on PR #68 after incorporating the merged Company Portal changes.
- Physical x64 validation on PC1 succeeded: SetupComplete checked SHA-256 and Authenticode, silently installed CMTrace Open 1.6.3 with exit code 0, and the Windows uninstall inventory confirmed 1.6.3.
- The update-check setting was passed as `DISABLEUPDATECHECKS=1` during the successful install.
- ARM64 deployment and end-user functional behavior were not independently validated.
