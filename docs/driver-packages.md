# Repository driver packages

`Add-OSDStageDriver -Id WorkstationDrivers` stages a repository `PackageType: Driver` using the standard catalog, version selection, `Package.zip`, USB cache and SHA-256 verification. It does not install drivers on the preparation PC or into WinPE. Drivers required to boot Windows must already be supplied by the Windows deployment; this feature runs after Windows has booted. SetupComplete processes the package once as SYSTEM in the applied Windows installation.

## Build and publish

Put the complete extracted vendor driver tree in the source folder. Keep every INF and referenced CAT/SYS/DLL, co-installer and support file together in its original relative directory structure. Nested INFs and repeated filenames in different directories are supported. Hidden support files are preserved. At least one INF is required; reparse points are rejected. The ZIP must contain only the top-level `Package/` directory.

```powershell
$package = New-OSDStagePackage -Id WorkstationDrivers -Version 1.0.0 `
    -PackageType Driver -SourcePath C:\Work\Drivers `
    -OutputPath C:\Work\Build\WorkstationDrivers

Add-OSDStagePackage -Id WorkstationDrivers -DisplayName 'Workstation drivers' `
    -Version 1.0.0 -Architecture x64 -PackageType Driver `
    -PackagePath $package.PackagePath -RepositoryPath C:\Work\Repository
```

No `Install.ps1` is needed. If vendor files include scripts or EXEs, OSDStage preserves them but never launches them as the package installer. Windows driver installation may use vendor-defined co-installers according to the INF. Do not modify signed vendor files or fabricate missing files.

Build/publication checks are structural, not a driver certification test. Windows PnPUtil validates the INF, signatures and necessary payload during native import. The repository owner chooses the correct vendor/model, architecture and version. There is no OSDStage hardware/model matching, vendor downloader, forced downgrade, unsigned-driver bypass or deletion of existing drivers.

Upload the repository using your normal publication process, then prepare the USB cache on the development machine:

```powershell
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud
Sync-OSDStageRepository -Name WorkstationDrivers -Architecture x64
```

In WinPE, after OSDCloud has applied Windows:

```powershell
Add-OSDStageDriver -Id WorkstationDrivers -SkipCacheRefresh
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

The cache volume is found by label `OSDCloud`, never a fixed drive letter. Without SkipCacheRefresh, the normal repository synchronization/fallback behavior applies. WinPE checks the archive hash and stages the ZIP; it does not repeatedly extract a large driver package into its RAM disk. Extraction and INF discovery occur during SetupComplete.

## One-shot native execution

Each INF is processed in deterministic path order with two explicit operations in the same run:

1. `pnputil.exe /add-driver "full-path.inf"` adds the package to the Driver Store.
2. After store success, `pnputil.exe /add-driver "full-path.inf" /install` asks Windows to apply it to matching devices.

These separate store success from device applicability. They are not retries: each phase runs once, and a failed store phase skips that INF's device phase. Remaining INFs are still attempted. Support files stay in place throughout execution. Windows decides matching and ranking; adding a driver to the store does not mean Windows selected it for a device.

The runtime never supplies `/reboot` or `/force`. Reboot requirements are reported, with no scheduled retry, post-reboot check or corrective pass. Repository SuccessCodes customization does not override Driver runtime results.

`Driver-WorkstationDrivers-Result.json`, next to `Latest.json`, contains per-INF relative paths, full command output, native exit codes, store/device outcomes, aggregate failures and RestartNeeded/RebootRequested. The module does not parse localized output to infer state:

| Native result | Reported behavior |
|---|---|
| Store 0 or 3010 | `AddedOrAlreadyPresent`; the native text retains any finer distinction |
| Install 0 | `SucceededBindingNotReported`; a new device binding is not asserted |
| Install 259 | `NoMatchingDeviceOrBetterDriver`; successful store import remains useful, no device update claimed |
| Install 3010 | `InstalledRebootRequired`; requirement recorded without requesting a reboot |
| Other codes / invocation failure | Failed INF, error retained, remaining INFs continue |

An already-present package can be processed successfully again by Windows; OSDStage does not claim it was newly added. Package exit code is 1 if any INF fails, otherwise 3010 when a phase requires reboot, otherwise 0. A partially successful package is reported as failed without rolling back successful driver imports. If additional native detail is needed, Windows maintains `%WINDIR%\INF\setupapi.dev.log`.

Public payload cleanup follows the existing global CleanupMode. `Never` retains staging for tests. No retry is added by this feature.

References: [PnPUtil syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) and [return values](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-return-values).
