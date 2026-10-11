# OSDApps Manager – read-only device inspector (development preview)

OSDApps is CLI-first. **All configuration, package acquisition, cache changes,
staging, unstaging, and automation must be performed through PowerShell cmdlets
and existing orchestration.** The GUI is a read-only inspection tool only.

The GUI is available on the development branch in PR #14; it is not yet in
the stable 0.33.0 PowerShell Gallery release. It has no organization-specific
repository URL or deployment profile presets.

## Four read-only tabs

| Tab | Purpose | Data source |
| --- | --- | --- |
| Staged for device | Exactly what is queued for SetupComplete, in manifest order, including source and details | DeviceManifest.json on selected Windows target |
| Applications | Built-in and repository applications, their availability and staged status | Get-OSDApp and the staged manifest |
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
load the same development module and run:

    powershell.exe -STA -NoProfile
    Import-Module 'E:\Modules\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -Offline

The exact USB drive letter can vary. A WinPE image must include the required
PowerShell, Windows Forms and .NET components. This runtime must still be
manually validated on a WinPE device.

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
