# Prepare a USB cache

[Examples](README.md) · [Next: online WinPE](WinPE-Online.md) · [Next: offline WinPE](WinPE-Offline.md)

**Run on a full Windows preparation machine, not in WinPE.** This example saves the module to an existing USB volume and optionally refreshes application content. It does not stage apps against the preparation machine's Windows drive, format the volume or create bootable OSDCloud media. The optional repository reconciliation section can remove stale repository cache folders only after a separate `-Prune` confirmation.

Use Windows PowerShell 5.1 with PowerShellGet available and internet access. Attach exactly one intended cache volume labeled `OSDCloud`; prepare/label the media separately before running this example. There must be enough free space for the module and selected payloads, including any existing content.

## 1. Save the exact module to the stick

```powershell
$ErrorActionPreference = 'Stop'

$IsWinPE = (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') -or
    ($env:SystemDrive -eq 'X:' -and $env:windir -like 'X:\Windows*')
if ($IsWinPE) {
    throw 'Run USB preparation on full Windows, not in WinPE.'
}

$Usb = @(Get-Volume | Where-Object {
    $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter
})
if ($Usb.Count -ne 1) {
    throw 'Attach exactly one intended OSDCloud cache volume.'
}

$UsbRoot = "$($Usb[0].DriveLetter):\"
if ($UsbRoot.TrimEnd('\') -ieq $env:SystemDrive) {
    throw 'The selected cache volume is the active Windows system drive.'
}

$ModuleParent = Join-Path $UsbRoot 'Modules'
New-Item -ItemType Directory -Path $ModuleParent -Force | Out-Null

Save-Module -Name OSDApps -RequiredVersion 0.39.0 `
    -Repository PSGallery -Path $ModuleParent -Force

$ModulePath = Join-Path $ModuleParent 'OSDApps\0.39.0\OSDApps.psd1'
if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
    throw "Saved module not found: $ModulePath"
}

Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
Import-Module $ModulePath -Force -ErrorAction Stop
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud

Get-Module OSDApps | Select-Object Name, Version, Path
```

`Save-Module` places the module in a version subdirectory. The following WinPE examples import that exact saved path, so an older module elsewhere on the stick is not selected accidentally.

At this point an **online** target can use the saved module even when the app cache has not yet been populated. Continue below before an **offline** deployment.

## 2. Pre-cache the matching built-ins

**Run in the same full-Windows PowerShell session.** These commands download or refresh the USB cache; they do not install Teams or Firefox on the preparation machine.

```powershell
Sync-OSDAppMicrosoftTeams -Architecture x64
Sync-OSDAppMozillaFirefoxEnterprise -Channel Rapid -Language en-US -Architecture x64

Get-OSDAppCache -Name MicrosoftTeams,MozillaFirefoxEnterprise -ResolveVersions -VerifySignatures |
    Select-Object Id, Version, Architecture, Channel, Language, Valid, SignatureStatus

Get-OSDAppCacheHealth -Offline |
    Select-Object Healthy, ActiveCount, RenamedCount, IncompleteCount, CorruptCount
```

Review both file availability and signature results. The corresponding WinPE examples use the same x64 Teams and Firefox Rapid/en-US variants. `Updated=False` means existing content was reused; it is not a synchronization failure. Built-in signed-file trust/publisher failures must be investigated before relying on the cache.

To add Office or another built-in, choose its required configuration from the [built-in guide](../docs/built-in-apps.md). Do not assume a cache for one channel, language, product set or architecture satisfies another configuration.

## 3. Optionally pre-cache your repository app

Skip this section for built-ins-only deployment. It requires an already published repository and an actual app Id in that repository; no sample catalog is provided as a hosted service.

```powershell
# Full Windows, same session. Enter values for your own published repository.
$CatalogUri = Read-Host 'Enter the HTTPS URL of your repository catalog.json'
$RepoAppId = Read-Host 'Enter an application Id present in that repository'

Set-OSDAppConfiguration -CatalogUri $CatalogUri
Sync-OSDAppRepository -Name $RepoAppId

Get-OSDAppCache -Name $RepoAppId |
    Select-Object Id, DisplayName, Vendor, Version, Architecture, Valid
```

Selective synchronization does not remove unrelated packages. To maintain a
long-lived repository cache against the complete configured catalog, inspect
the plan first and approve it separately:

```powershell
Get-OSDAppCacheHealth
Sync-OSDAppRepository -Prune -WhatIf
# After reviewing the exact cache volume and WhatIf output:
Sync-OSDAppRepository -Prune -Confirm
```

Repository synchronization resolves a variant for the **current host architecture**. When preparing media on an ARM64 machine for an x64 target, do not assume that a host-selected repository variant is suitable for that target. These paired examples assume an x64 preparation/deployment workflow; verify the architecture shown in the cache results.

## 4. Move the stick to the target

Wait for all commands and file activity to finish. The relevant layout is:

```text
<USB>:\
    Modules\OSDApps\0.39.0\OSDApps.psd1
    OSDApps\BuiltIn\...
    OSDApps\Packages\...          (when repository content was synced)
    OSDApps\CacheCatalog.json    (when repository content was synced)
```

Existing OSDCloud boot/image files remain separate and unchanged. Continue on the target machine with [Online WinPE deployment](WinPE-Online.md) or [Offline WinPE deployment](WinPE-Offline.md). Do not run those staging commands on the preparation machine.
