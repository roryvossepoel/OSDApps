# Runtime and cleanup

[Documentation](README.md) · [Architecture](architecture.md) · [Troubleshooting](faq.md)

OSDApps uses standalone scripts during SetupComplete. The module itself does **not** need to be installed in the deployed Windows installation.

![Application queue and install order](images/application-queue.svg)

## Runtime content

The public Add cmdlets prepare the selected offline Windows target. Runtime source normally lives under:

```text
<Windows target>\Windows\Temp\OSDApps\
    DeviceManifest.json
    Invoke-OSDAppPreInstall.ps1
    Invoke-OSDAppRunner.ps1
    Packages\
    BuiltIn\
    Work\
```

This is **device staging**, separate from the optional `\OSDApps` USB cache. `DeviceManifest.json` contains one ordered `Apps` array. PreInstall processes its built-ins; Runner processes the full queue in order.

## SetupComplete order

```text
SetupComplete.cmd
→ Invoke-OSDAppPreInstall.ps1
→ check PreInstall exit code
→ Invoke-OSDAppRunner.ps1
→ check Runner exit code
```

The CLI stages these scripts and updates its owned SetupComplete blocks. Do not replace the whole SetupComplete file to change OSDApps settings; other deployment tooling may have its own commands there.

### PreInstall

PreInstall runs in **full Windows**, not WinPE. It reads the manifest/runtime settings, detects the optional cache volume and reported network availability, then prepares each built-in's local source.

When online it can acquire/refresh vendor content through the cache, or directly under the local runtime when no cache volume exists. When no network is reported, it can use complete content already staged from the cache. A failed refresh may also fall back to existing staged content.

**An available file is not sufficient by itself.** Supported MSI/EXE files must pass Windows Authenticode and expected-publisher checks before they are used, including the fallback path. If there is no acceptable source, or a required trust/configuration/acquisition check fails without a usable fallback, PreInstall exits with an error and its SetupComplete block does not continue to Runner.

The signature scope is deliberately limited: Office `setup.exe`, Teams `teamsbootstrapper.exe`, and Chrome/Firefox/Webex MSI files. It does not cover the Office data tree, Teams MSIX or Adobe's outer ZIP. See the [publisher policy](built-in-apps.md#authenticode-and-publisher-policy-0340).

`NetworkInterface.GetIsNetworkAvailable()` reports interface availability; it is not proof that a vendor endpoint is reachable. The log distinguishes a directly skipped refresh from a failed refresh followed by fallback.

### Runner

Runner reads the ordered queue and installs from **local staging**. For repository apps it validates the package SHA-256 again, extracts the ZIP and executes `Package/Install.ps1`. It does not synchronize the repository after boot.

For built-ins it invokes the corresponding local installer/provisioning mechanism. Adobe's archive is extracted locally before Adobe Setup runs. Vendor MSI built-ins use Windows Installer with silent arguments. An unrecoverable app failure stops the run; complete success enables the configured cleanup behavior.

Installer/provisioning success is not independent evidence of application activation, user sign-in or every interactive feature.

## Runtime configuration

**Set these values in the WinPE staging session before adding apps:**

```powershell
Set-OSDAppConfiguration `
    -CleanupMode OnSuccess `
    -CacheVolumeLabel 'OSDCloud' `
    -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log' `
    -ResultPath '%ProgramData%\OSDApps\Results\Latest.json'
```

Configure a real `CatalogUri` in the same session when staging online repository apps. It is not needed for built-ins-only deployment.

The session's `CleanupMode`, `CacheVolumeLabel`, `LogPath` and `ResultPath` are written into the device manifest by the Add commands. A unique `DeploymentId` is also added when the manifest is first staged. SetupComplete therefore does not depend on the preparation machine's session or on importing the module. Changing session configuration alone does not retroactively rewrite an existing device manifest.

| CleanupMode | Behavior |
| --- | --- |
| `OnSuccess` | Schedule removal of temporary runtime source after a successful complete run. |
| `Never` | Retain staging, payloads and Work for troubleshooting. |

On failure, source is retained automatically.

## Machine-readable deployment result

PreInstall writes a phase record, and Runner atomically replaces `Latest.json` as the queue progresses. The final result is outside the staging directory by default and therefore survives `CleanupMode OnSuccess`:

```text
%ProgramData%\OSDApps\Results\Latest.json
```

```powershell
$Result = Get-OSDAppDeploymentResult
$Result.Status
$Result.Applications | Select-Object Id, Status, ExitCode, Version, DurationSeconds, Integrity, CacheUsed, PackageUpdated
```

The top-level status is `Running`, `Succeeded` or `Failed`. The final record includes the deployment ID, timestamps, duration, expected/success/failed counts, configured cleanup/log paths, the PreInstall phase record and one entry per attempted application. Runner updates through a temporary file and rename so readers do not observe partially written JSON.

`Integrity` records the check actually performed by Runner. Repository archives report SHA-256 validation; supported built-in publishers are validated in PreInstall and carried as phase context. `CacheUsed` and `PackageUpdated` come from built-in `CacheInfo.json` when available. Null means the fact was not available for that source, not false.

Result writing is best effort so an evidence-path problem does not convert an otherwise successful installer run into a failed deployment. A `ResultWriteFailed` warning in `Runtime.log` means the JSON is incomplete or unavailable; use the log as the authoritative fallback. A successful JSON status remains installer/provisioning evidence, not proof of activation, user sign-in or later interactive health.

## Cleanup policy

With `OnSuccess`, Runner writes its final events, starts a cleanup helper and exits; the helper removes the staging directory and itself. With `Never`, cleanup is skipped and `CleanupSkipped` is logged.

The USB cache is separate and is not deleted by local source cleanup. The persistent log should be outside the staging directory; the default ProgramData path is retained. A completion line containing `CleanupMode=OnSuccess` identifies the selected policy. Check cleanup events or filesystem state when you need to prove that cleanup itself finished.

## Logging

The default persistent runtime log is:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Module/cache actions with USB use:

```text
<cache volume>:\OSDApps\Logs\Client.log
```

Runtime `LogPath` can be configured. The Viewer discovers known default locations, so custom paths may need to be read separately. Logs are CMTrace-compatible. The runtime rotates the active log and retains numbered `.1`, `.2` and `.3` archives.

| Event | Interpretation |
| --- | --- |
| `CacheVolumeFound` / `CacheVolumeNotFound` | Whether the configured cache volume was found. |
| `DownloadStart` / `DownloadComplete` | Acquisition activity, including size/duration data. |
| `BuiltInCacheRestaged` | Existing USB content was copied into local staging. |
| `BuiltInSignatureVerified` | The specified supported MSI/EXE and expected publisher passed validation. |
| `BuiltInRefreshSkipped` | No network was reported; existing staged built-in content was selected. Recorded as a warning, not an installer failure. |
| `BuiltInRefreshStart` / `BuiltInRefreshComplete` | Refresh/acquisition attempt and successful readiness of content. |
| `BuiltInRefreshFailed` | A refresh failed and the existing local fallback was selected after applicable checks. |
| `RefreshFailed` | PreInstall failed; inspect its failure type and original message. |
| `PreInstallComplete` | The built-in preparation phase completed successfully. |
| `PackageIntegrityValidated` | A repository package passed its integrity check. |
| `BuiltInInstallComplete` / `PackageInstallComplete` | Individual installer/provisioning outcome. |
| `ApplicationInstallComplete` | Complete processing duration for one queue entry. |
| `ApplicationInstallFailed` / `InstallFailed` | Application or Runner failure; source remains for investigation. |
| `InstallComplete` | Runner completed the full queue; check its application count and individual results. |
| `CleanupScheduled` / `CleanupSkipped` | Cleanup was scheduled or intentionally skipped. |

An offline installation is not demonstrated by a short runtime alone. Review `BuiltInRefreshSkipped`, signature checks and final installation outcomes. An online cache hit can also be fast.

### Synchronization versus updated content

`CacheSynchronized=True` means cache synchronization took place, not that a new version was downloaded. Microsoft 365 Apps reports `VersionChanged`; Teams and the HTTP-metadata-based packages report `PackageUpdated`. Read those values alongside the source path and version.

### Downloads and timeouts

Large runtime downloads use streaming HttpClient and a temporary `.download` file before the completed file is moved into place. `DownloadComplete` reports bytes, size, duration and average throughput. Network/download completion is distinct from signature verification of a supported installer.

Office's standalone refresh timeout is 20 minutes by default. Adobe installation defaults to 15 minutes; its runner emits a waiting heartbeat while the installer is running. A timeout is not success: the process handling stops the failed installation and retains source.

To choose a different Adobe installation timeout, set it **when staging in WinPE**:

```powershell
Add-OSDAppAdobeAcrobatUnified -InstallTimeoutMinutes 20
```

## Vendor MSI built-ins

Chrome Enterprise, Firefox Enterprise and Cisco Webex use the `VendorMsi` runtime type. The local MSI is installed through `msiexec.exe /i ... /qn /norestart`, with any validated built-in MSI properties appended.

The generic MSI runner uses a 10-minute default installation timeout, logs waiting heartbeats, accepts exit codes `0` and `3010`, and retains source on failure. Review app-specific options before changing properties; the Viewer does not edit them.

## Timing and failure diagnostics

| Duration field | Scope |
| --- | --- |
| `PreInstallComplete.DurationSeconds` | Built-in preparation phase |
| `BuiltInRefreshComplete.DurationSeconds` | One built-in's acquisition/refresh processing |
| `ApplicationInstallComplete.DurationSeconds` | Complete queue-item processing, including validation/extraction where applicable |
| `InstallComplete.DurationSeconds` | Full Runner phase |

PreInstall failure types include `NetworkUnavailable`, `Timeout`, `CacheOrSourceMissing`, `RemoteAcquisition` and `PreInstallError`. Runner types include `HashMismatch`, `SourceMissing`, `Timeout`, `InstallerFailed` and `RuntimeError`. The original message remains alongside the category; use it to diagnose the actual cause.

The [validation matrix](testing.md) and [performance history](performance.md) distinguish measured phases from image deployment, WinPE staging, boot and OOBE time.
