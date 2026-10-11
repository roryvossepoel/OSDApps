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

In Get-OSDApp, Cached means valid local repository cache plus an online catalog match. CachedOnly means valid local cache without a current online catalog match, which is expected when Offline is selected. The GUI explains both as OSDCloud USB cache states, not as different disks. The configured OSDCloud volume directory is separate from Windows target staging. Repository archives are SHA-256 checked; built-in cache validity checks required files, not full hashes.

Search filters table contents without new downloads. Clicking column headers sorts the visible table only; it never changes DeviceManifest order or the actual setup sequence. Logs are shown with separate timestamp, severity, component and message columns, plus a details pane. All operations remain read-only.
