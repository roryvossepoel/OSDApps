# Offline WinPE deployment

[Examples](README.md) · [USB preparation](Prepare-UsbCache.md) · [Online alternative](WinPE-Online.md)

**Run on the x64 target PC in WinPE after OSDCloud has applied Windows and before the first Windows boot.** This is not a preparation-machine script.

Complete [Prepare a USB cache](Prepare-UsbCache.md) first, including x64 Teams and Firefox Rapid/en-US content. Disconnect LAN and Wi-Fi before using this example and keep networking disconnected through SetupComplete when testing the fully offline path. Leave the USB attached.

A matching cache must contain the required content, and supported MSI/EXE files must still pass the Windows signature/publisher checks after reboot. File presence in WinPE is not a substitute for that verification.

## 1. Validate the environment and cached variants

```powershell
$ErrorActionPreference = 'Stop'

$IsWinPE = (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') -or
    ($env:SystemDrive -eq 'X:' -and $env:windir -like 'X:\Windows*')
if (-not $IsWinPE) { throw 'Run this deployment example in WinPE.' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This example selects x64 app variants and expects x64 WinPE.'
}
if ([System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
    throw 'Windows reports an available network interface. Disconnect LAN/Wi-Fi and inspect adapters before this offline example.'
}

$Usb = @(Get-Volume | Where-Object {
    $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter
})
if ($Usb.Count -ne 1) { throw 'Expected exactly one OSDCloud cache volume.' }
$UsbRoot = "$($Usb[0].DriveLetter):\"
$ModulePath = Join-Path $UsbRoot 'Modules\OSDApps\0.37.0\OSDApps.psd1'
if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
    throw 'Saved module missing. Complete the Windows USB preparation example first.'
}

$Targets = @(Get-Volume | Where-Object {
    $_.DriveLetter -and $_.DriveLetter -ne $Usb[0].DriveLetter -and
    "$($_.DriveLetter):" -ne $env:SystemDrive
} | ForEach-Object {
    $Root = "$($_.DriveLetter):\"
    if (Test-Path -LiteralPath (Join-Path $Root 'Windows\System32\Config\SYSTEM') -PathType Leaf) {
        $Root
    }
})
if ($Targets.Count -ne 1) {
    throw "Offline Windows target is not unique: $($Targets -join ', ')"
}
$WindowsPath = $Targets[0]
$ManifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDApps\DeviceManifest.json'
if (Test-Path -LiteralPath $ManifestPath) {
    throw 'A device queue already exists. Inspect it before starting a new example.'
}

Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
Import-Module $ModulePath -Force -ErrorAction Stop
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess

$Entries = @(Get-OSDAppCache -Name MicrosoftTeams,MozillaFirefoxEnterprise)
$Teams = @($Entries | Where-Object {
    $_.Id -eq 'MicrosoftTeams' -and $_.Source -eq 'BuiltIn' -and
    $_.Architecture -eq 'x64' -and $_.Valid
})
$Firefox = @($Entries | Where-Object {
    $_.Id -eq 'MozillaFirefoxEnterprise' -and $_.Source -eq 'BuiltIn' -and
    $_.Architecture -eq 'x64' -and $_.Channel -eq 'Rapid' -and
    $_.Language -eq 'en-US' -and $_.Valid
})
if ($Teams.Count -ne 1 -or $Firefox.Count -ne 1) {
    throw 'Required x64 Teams and Firefox Rapid/en-US cache entries are missing, invalid or ambiguous.'
}

$Entries | Select-Object Id, Architecture, Channel, Language, Version, Valid
Write-Host "Windows target: $WindowsPath"
```

The network guard checks whether Windows reports an available interface; it is not an Internet connectivity test. A virtual or additional active adapter can require investigation even when the physical LAN cable is disconnected. It also does not control networking after the reboot.

## 2. Stage the cached built-ins

**Run in the same WinPE session after step 1 succeeds.** These commands write the offline Windows staging queue and copy available cache content:

```powershell
Add-OSDAppMicrosoftTeams -Architecture x64 -WindowsPath $WindowsPath
Add-OSDAppMozillaFirefoxEnterprise `
    -Channel Rapid -Language en-US -Architecture x64 -WindowsPath $WindowsPath
```

Do not run full-Windows built-in `Sync-OSDApp*` commands here. The content has already been prepared; the first Windows boot uses the staged fallback when networking remains unavailable.

## 3. Optionally stage a previously cached repository app

Omit this section for built-ins-only deployment. The app must already exist as a valid, compatible package in `CacheCatalog.json` and the USB cache. `-SkipCacheRefresh` explicitly prevents a repository synchronization attempt.

```powershell
$RepoAppId = Read-Host 'Enter a repository application Id already cached on this stick'
Add-OSDApp -Name $RepoAppId -SkipCacheRefresh -WindowsPath $WindowsPath
```

This command validates requested repository archive hashes before staging. It does not create missing packages. When preparation and target architectures differ, verify the cached repository variant explicitly before deployment; this example assumes matching x64 media.

## 4. Review and continue the offline deployment

```powershell
(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json).Apps |
    Select-Object Id, Source, Architecture, Channel, Language, Version

# Optional read-only Viewer, with Windows Forms and an STA session available.
Show-OSDAppUI -WindowsPath $WindowsPath -Offline
```

Review the queue, then close the Viewer. Reboot through your normal deployment process only after staging succeeds. This example does not reboot automatically. Keep the cache stick attached and LAN/Wi-Fi disconnected through SetupComplete.

## 5. Confirm actual offline behavior

In deployed Windows after SetupComplete, inspect the default persistent log using the [Getting started log check](../docs/getting-started.md#5-check-the-outcome).

Expected evidence for this example is `BuiltInRefreshSkipped` for Teams and Firefox, `BuiltInSignatureVerified` for their supported installer files, successful individual installer/provisioning results and `InstallComplete` with the expected app count. A repository app adds another queue entry only if step 3 was used.

An offline trust failure is not a reason to disable the signer policy. Preserve the log and investigate the device's clock/trust data and the package provenance. After the offline phase is verified, restore networking for subsequent OOBE/Autopilot or normal use as appropriate.
