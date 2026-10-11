# Online WinPE deployment

[Examples](README.md) · [USB preparation](Prepare-UsbCache.md) · [Offline alternative](WinPE-Offline.md)

**Run on the target PC in WinPE after OSDCloud has applied Windows, before its first Windows boot.** Do not run this on the full-Windows preparation machine.

This example assumes an x64 target and the module saved by [Prepare a USB cache](Prepare-UsbCache.md). Keep the cache stick and working network connection available through SetupComplete. The script stages two built-ins; it neither formats a disk nor clears a cache nor reboots automatically.

## 1. Import the module and stage built-ins

```powershell
$ErrorActionPreference = 'Stop'

$IsWinPE = (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') -or
    ($env:SystemDrive -eq 'X:' -and $env:windir -like 'X:\Windows*')
if (-not $IsWinPE) { throw 'Run this deployment example in WinPE.' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This example selects x64 app variants and expects x64 WinPE.'
}

$Usb = @(Get-Volume | Where-Object {
    $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter
})
if ($Usb.Count -ne 1) { throw 'Expected exactly one OSDCloud cache volume.' }
$UsbRoot = "$($Usb[0].DriveLetter):\"
$ModulePath = Join-Path $UsbRoot 'Modules\OSDApps\0.34.0\OSDApps.psd1'
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

Write-Host "Windows target: $WindowsPath"
Write-Host "USB cache: $(Join-Path $UsbRoot 'OSDApps')"

Add-OSDAppMicrosoftTeams -Architecture x64 -WindowsPath $WindowsPath
Add-OSDAppMozillaFirefoxEnterprise `
    -Channel Rapid -Language en-US -Architecture x64 -WindowsPath $WindowsPath
```

The guard against an existing manifest is part of this **example**, not a general module requirement. OSDApps can add to an existing queue, but a first-run example must not silently alter someone else's staging.

No built-in payload needs to be downloaded in WinPE for a cold online deployment. PreInstall acquires the selected content during the first Windows boot; existing matching cache content is staged as fallback when available.

## 2. Optionally add your repository app

**Run in the same WinPE session, after step 1.** Omit this section for the two-built-in example. Repository packages are synchronized and staged now, before reboot, not downloaded later by Runner.

```powershell
$CatalogUri = Read-Host 'Enter the HTTPS URL of your repository catalog.json'
$RepoAppId = Read-Host 'Enter an application Id present in that repository'

Set-OSDAppConfiguration -CatalogUri $CatalogUri
Add-OSDApp -Name $RepoAppId -WindowsPath $WindowsPath
```

Use your own published catalog and app Id. `ExampleApp`, Notepad++ and Omnissa Horizon Client are not built-ins that OSDApps supplies automatically.

## 3. Review before continuing

Read the actual queue:

```powershell
(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json).Apps |
    Select-Object Id, Source, Architecture, Channel, Language, Version

# Optional Viewer; requires Windows Forms and an STA session.
Show-OSDAppUI -WindowsPath $WindowsPath -Offline
```

Expect Teams first, Firefox second, followed by a repository app only if step 2 was used. `-Offline` here limits Viewer catalog lookup; it does **not** turn the deployment into an offline installation.

Close the Viewer and continue the normal deployment reboot only after staging has completed without errors. Keep LAN and the cache USB connected until SetupComplete is finished. Do not rerun step 1 to bypass a partial failure; inspect its manifest and log instead.

## 4. Confirm the installation result in Windows

After SetupComplete, use the [Getting started log check](../docs/getting-started.md#5-check-the-outcome). Review individual installer/provisioning results and `InstallComplete`, not just the WinPE staging output.

An online run with an existing cache is a warm-cache run. A deliberately empty application cache exercises new downloads, but this example does not erase existing content to force that condition.
