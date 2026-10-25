# Replace ONLY the OSDApps block in your launcher for this registry-only test.
# Run in WinPE after OSDCloud has applied Windows. No Gallery access or cache reset.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'This launcher block must run in WinPE, not on the preparation PC.'
}
$usb = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($usb.Count -ne 1) { throw 'Expected exactly one OSDCloud USB.' }
$moduleRoot = "$($usb[0].DriveLetter):\OSDApps-Registry"
Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force -Global -ErrorAction Stop
$loaded=Get-Module OSDApps
if ($loaded.ModuleBase -ne $moduleRoot) { throw 'The registry test module was not loaded from USB.' }
Get-Command Add-OSDAppRegistryKey,Add-OSDAppRegistryValue -Module OSDApps -ErrorAction Stop | Out-Null
Set-OSDAppConfiguration -CacheVolumeLabel 'OSDCloud' -CleanupMode Never
$key='HKLM:\SOFTWARE\OSDApps\Tests\RegistryStaging\Level1\Level2\Level3'
Add-OSDAppRegistryKey -Path "$key\EmptyKey" -Registry64 | Out-Null
Add-OSDAppRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn64BitView' -Registry64 | Out-Null
Add-OSDAppRegistryValue -Path $key -Name TestNumber -Type DWord -Value 64 -Registry64 | Out-Null
Add-OSDAppRegistryKey -Path "$key\EmptyKey" -Registry32 | Out-Null
Add-OSDAppRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn32BitView' -Registry32 | Out-Null
Add-OSDAppRegistryValue -Path $key -Name TestNumber -Type DWord -Value 32 -Registry32 | Out-Null
Add-OSDAppRegistryKey -Path "$key\Default\EmptyKey" | Out-Null
Add-OSDAppRegistryValue -Path "$key\Default" -Name Marker -Type String -Value 'HostDefault' | Out-Null
Add-OSDAppRegistryValue -Path "$key\Default" -Name TestNumber -Type DWord -Value 0 | Out-Null
$validation=Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
$validation | Format-List Valid,OfflineReady,NetworkRequired,AppCount,WindowsPath
if ($validation.AppCount -ne 1 -or @($validation.Apps | Where-Object Id -eq 'RegistrySettings').Count -ne 1) {
    throw 'This test requires exactly one RegistrySettings entry. Use fresh offline Windows staging.'
}
Write-Host 'Registry staging passed: one Script entry, nine operations. The launcher may continue to Windows.'
