# OSDApps Viewer – read-only device inspector

OSDApps is CLI-first. **All configuration, package acquisition, cache changes,
staging, unstaging, and automation must be performed through PowerShell cmdlets
and existing orchestration.** The GUI is a read-only inspection tool only.

The read-only Viewer is introduced with OSDApps 0.34.0. It has no
organization-specific repository URL or deployment profile presets.

## Four read-only tabs

| Tab | Purpose | Data source |
| --- | --- | --- |
| Staged for device | Exactly what is queued for SetupComplete, in manifest order, including source and details | DeviceManifest.json on selected Windows target |
| Apps | Built-in and repository applications, their availability and staged status | Get-OSDApp and the staged manifest |
| Cache | Cached built-in and repository packages, sizes and validation status | Get-OSDAppCache on the OSDCloud volume |
| Logs | Last 500 lines from existing logs shown in a structured, read-only table | Existing log files only |

The GUI never claims that **staged** means **installed**. Runtime logs for
SetupComplete may not exist until after the deployment has executed.

Configuration is displayed from the actual staged manifest, not recomputed
from assumed default settings. The details panel deliberately omits installer
command lines and authenticated package download URLs.

## Quick Windows 11 read-only test

Run in Windows PowerShell 5.1, in STA:

    Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json'
    Show-OSDAppUI -TestMode -Offline

If the isolated test folder from previous GUI tests exists, its
DeviceManifest is inspected, **without creating or changing anything**.
If it is absent, the interface simply reports that no manifest exists.

To inspect a specific prepared Windows directory from full Windows:

    Show-OSDAppUI -WindowsPath 'D:\' -Offline

With no WindowsPath on full Windows, the current Windows system drive is
inspected read-only. In WinPE, the module attempts to discover the offline
Windows target automatically, or specify the target using -WindowsPath.

No download, staging, cache-clearing or configuration controls exist in the GUI.
The only actions are **Refresh**, choosing an item to inspect, switching tabs,
reading existing logs and **Close**.

## On WinPE

After the OSDCloud CLI deployment has applied Windows and staged applications,
load OSDApps 0.34.0 and run:

    powershell.exe -STA -NoProfile
    Import-Module 'E:\Modules\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -Offline

The exact USB drive letter can vary. A WinPE image must include the required
PowerShell, Windows Forms and .NET components. The read-only Viewer was
validated on two x64 WinPE test PCs; other WinPE builds and architectures
must provide the same prerequisites.

## Important distinctions

- **Device staging** is under the selected Windows root, normally
  Windows\Temp\OSDApps. It contains DeviceManifest.json.
- **USB cache** is normally under the volume labeled OSDCloud, at \OSDApps.
  Get-OSDAppCache reads that inventory without changing or clearing it.
- **Built-ins** and **repository apps** have distinct Source values.
- The CLI, not the GUI, controls whether either type is staged or removed.
- Online catalog reading is optional. Use -Offline to avoid remote catalog
  lookups and inspect the local staged manifest and USB cache.
- The GUI is intentionally not a replacement for full CLI logging,
  configuration management, synchronization, or deployment automation.

## Troubleshooting

    try { Show-OSDAppUI -TestMode -Offline -ErrorAction Stop }
    catch { $_ | Format-List * -Force; $_.ScriptStackTrace }

## Status and sorting guide

Built-in application Version / policy always shows Current, meaning vendor-managed acquisition rather than an exact version or a claim that it is up to date. USB version shows a real recorded version only, where available and valid. A Current placeholder in cache metadata displays as Not recorded. Repository apps retain their explicit package versions.

In Get-OSDApp, Cached means valid local repository cache plus an online catalog match. CachedOnly means valid local cache without a current online catalog match, which is expected when Offline is selected. The GUI deliberately shows both as USB cached, because valid local availability is identical. The header separately displays Catalog: Offline mode (not queried) when -Offline is used. The CLI statuses are unchanged. The configured OSDCloud volume directory is separate from Windows target staging. Repository archives are SHA-256 checked; built-in cache validity checks required files, not full hashes.

Search filters table contents without new downloads. Clicking column headers sorts the visible table only; it never changes DeviceManifest order or the actual setup sequence. The GUI resizes table columns with the window (while keeping space for long versions, including Teams). Logs are shown with separate timestamp, severity, component, event, and message columns, plus a details pane. Events such as CacheDetection are extracted from the log message into their own column. All operations remain read-only.

## Inspect cached vendor versions without downloads

From Windows PowerShell 5.1 on **full Windows** with the OSDCloud USB cache attached:

    Get-OSDAppCache -ResolveVersions |
        Select-Object Id, Source, Version, VersionSource, Valid, CachePath |
        Format-Table -AutoSize

The optional `-ResolveVersions` switch inspects **existing, valid** cached packages without writing to cache metadata or downloading payloads. It reads Windows Installer `ProductVersion` from Google Chrome, Webex and Firefox MSI packages through read-only MSI COM APIs. It reads the `PATCH=` entry from `Adobe Acrobat/setup.ini` **inside** the Acrobat ZIP without extracting the entire ZIP. Example `AcrobatDCx64Upd2600221931.msp` is reported as `26.002.21931`, with `VersionSource=AdobePatchFileName`. This is a patch build, not necessarily the version of the base AcroPro.msi. Microsoft 365 Apps and Teams continue to use their existing cache metadata. Repository apps use their catalog package versions.

If a package has no discoverable version, the UI shows `Not recorded` rather than inventing one. The GUI automatically requests this inspection on full Windows, while in WinPE it reads the saved `CacheInfo.json` version because Windows Installer COM is not guaranteed to be available. The four built-in sync commands for Acrobat, Chrome, Webex and Firefox now persist extracted versions and their `VersionSource` into `CacheInfo.json` during **future** synchronizations. Existing caches can be inspected today with `-ResolveVersions` without a sync or download, but their metadata files are left untouched.

The GUI displays Adobe's version without an extra MSP suffix. The metadata field VersionSource=AdobePatchFileName still records that it came from the included patch filename. All staging and cache actions remain CLI-only.

### Cache integrity meaning

The Cache tab shows two different checks by design:

- **SHA-256 verified** on a repository application means its ZIP hash matches the package manifest.
- **Files present** on a built-in application means OSDApps checked that its required files and directories exist. This is not a cryptographic integrity or code-signature check.

Both report a local USB cache, not Windows target staging. No GUI action modifies the cache or SetupComplete.

## Built-in digital signature inspection

Full Windows, Windows PowerShell 5.1:

    Get-OSDAppCache -VerifySignatures |
        Select-Object Id, Valid, SignatureStatus, SignatureScope, SignatureSigner, SignatureFile |
        Format-Table -AutoSize

Signature verification is **on by default in OSDApps Viewer on full Windows**:

    Show-OSDAppUI -TestMode -Offline

To deliberately skip OS trust verification in an isolated test:

    Show-OSDAppUI -TestMode -Offline -SkipSignatureVerification

- The **CLI** retains opt-in Get-OSDAppCache -VerifySignatures for fast inventory scripts. The **Viewer** performs checks by default; it never changes USB package files, cache metadata, DeviceManifest or SetupComplete.
- Chrome, Cisco Webex and Firefox: inspect the cached Package.msi using Windows Authenticode.
- Microsoft 365 Apps: inspect setup.exe only, not the entire Office data tree.
- Microsoft Teams: inspect teamsbootstrapper.exe only, not the MSIX. The GUI identifies the exact scope in the cache-row tooltip.
- Adobe Acrobat Unified: not assessed, because a ZIP container is not equivalent to a signed executable.
- Custom repository ZIPs display Signature N/A in the GUI; their integrity is instead checked separately against the repository manifest SHA-256.
- The signature result is separate from Valid, which still reports package file-presence checks or repository archive SHA-256 validation.
- For signable built-ins, OSDApps now checks both Windows Authenticode trust and the expected certificate **organization**, such as Microsoft Corporation, Google LLC, Cisco Systems, Inc. or Mozilla Corporation. PublisherMismatch is a separate warning/error. This is organization-name allowlisting rather than certificate thumbprint pinning; it does not attest the entire bundled application, freshness, absence of malware or guaranteed revocation freshness.
- Other results including NotSigned, NotTrusted, HashMismatch, UnknownError and Check failed are reported distinctly.
- WinPE does not run the Windows Authenticode checker; in the Viewer, the signable built-ins report Unavailable in WinPE. It is not silently marked valid.
- Windows signature verification may involve certificate trust or revocation network traffic, even when -Offline disables online repository lookup. For a strictly network-isolated Viewer on full Windows, use -SkipSignatureVerification. The CLI only checks signatures when -VerifySignatures is requested.

## Compact header

The header occupies approximately 80 pixels, showing OSDApps Viewer, Deployment overview and Read-only. A single compact row underneath displays Target, USB and Offline/catalog status separated by vertical dividers (for example: Target: Test environment | USB: G:\\OSDApps | Offline). A tooltip retains full target, USB and catalog details. No editable controls have been introduced.

The Cache Architecture column is wide enough to show its full header at the standard desktop window size. On narrower screens, scrolling can still be necessary.

## Consistent application names and Vendor

The GUI displays the human-readable DisplayName for Staged for device, Apps and Cache, using the built-in metadata file when a cache entry only supplies a technical ID. The underlying CLI package Id and manifest order are never changed. Apps has a separate read-only Vendor column. For built-ins Vendor is sourced from metadata/builtins.json; for repository apps Vendor is only shown when the repository catalog/cache entry actually provides it. If unknown, it displays '-'. The Cache tab also shows Vendor, sourced from the same available built-in or repository metadata, using responsive widths and horizontal scrolling only when the viewport becomes too narrow. Staged application details show Vendor where known.

## First field test with two WinPE PCs

Stage apps as usual using the OSDApps **CLI**, after OSDCloud has applied Windows but before the first boot into SetupComplete. Run the read-only GUI with the same module build on both PCs:

    powershell.exe -STA -NoProfile
    Import-Module 'E:\Modules\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -Offline

Replace the drive letter with the actual OSDCloud USB path. Do not use -TestMode in WinPE; it targets the previous Windows 11 temporary test folder and is intended only for full-Windows preview.

Confirm that the target Windows volume is detected, that DeviceManifest.json and SetupComplete.cmd are present, that staged app count/source/order match the CLI, and that Cache and Logs can be opened without changing the device. Run normally without extra signature parameters in WinPE; the Viewer reports that signature checks are unavailable without invoking Windows trust providers. If a suitable WinPE image lacks Windows Forms, capture the error; the GUI requires Windows Forms, PowerShell and .NET optional components. Only proceed to reboot/install after closing the read-only inspection window.

## Display terminology (GUI)

The human-readable column is labeled **Display Name** in Staged for device, Apps, and Cache. The full application identifier (`Id`) remains unchanged in the manifest and CLI. The former Applications tab is now **Apps**; this is a presentation-only name change. **Vendor** is visible in both Staged for device and Apps and comes from the resolved built-in or repository metadata. The Cache tab includes Vendor as well, with widths rebalanced to keep full Teams versions visible in the normal desktop window. The original staging order in DeviceManifest.json is not modified, including when the screen table is sorted by a different column.

## Final read-only presentation polish

The GUI now selects the first visible staged application after an inventory refresh and immediately shows its *actual* manifest configuration in the details panel. In Logs it selects the most recent visible entry on initial load and displays its full parsed message in the details pane. Selecting another row changes only what is displayed; it does not modify files, staging or cache. When no staged apps or log rows are visible, the respective pane explains why it is empty.

The supplementary descriptions above the Apps, Cache and Staged tables and the footer are shorter and avoid repeating Read-only/CLI-only everywhere. The dark header continues to indicate Read-only. Log line component and event names can still be truncated in the table at lower display resolutions; selecting a row shows their full values in its details, and raw data remain available on the row tooltip.

## Final Viewer labeling

The Windows title and dark header use **OSDApps Viewer**; the public entry point is still `Show-OSDAppUI`. The compact target strip displays **Target | USB | Offline/Online** on one line. **Vendor** appears in Staged for device, Apps and Cache when metadata supplies it. The Cache tab retains its independent integrity and signature checks; numeric Size sorting uses the updated column index and never modifies the original cache or manifest.

## Cache sync and SetupComplete enforcement

On full Windows, the built-in MSI/EXE synchronization cmdlets for Google Chrome, Cisco Webex, Mozilla Firefox, Microsoft 365 Apps (setup.exe) and Microsoft Teams (bootstrapper EXE) now require a valid Authenticode signature **and** a certificate organization matching the expected publisher. Downloads are saved to a temporary candidate on the same disk and validated before promoting them to the cache. A rejected candidate does **not** overwrite the existing cached file. Existing cache hits are also rechecked before being reported as current. Synchronization errors are not suppressed or silently downgraded to success.

The standalone SetupComplete PreInstall script (which runs independently of the PowerShell module) now validates the MSI and EXE before refreshing or using cached payloads; it also rejects an unsigned or unexpected-publisher fallback. This is intentionally fail-closed for signable installer types: Windows trust-store or revocation problems can therefore prevent installation until a trustworthy package is available. These checks do **not** by themselves verify the entire Microsoft 365 Apps data tree or the Teams MSIX package. The outer Adobe Acrobat ZIP remains *Not assessed* for Authenticode and is not presented as signature-valid. Repository ZIPs remain SHA-256-validated against their manifests.

Release-candidate field validation on 11 October 2026 confirmed Windows 11 signature-status inspection, read-only WinPE Viewer behavior on two x64 PCs, and eight-app SetupComplete installations from both an initially empty online USB cache and an offline populated USB cache. See [validation details](testing.md#osdapps-0340-release-candidate-physical-validation--11-october-2026). These checks do not guarantee behavior on every WinPE image, hardware architecture or certificate trust configuration.
