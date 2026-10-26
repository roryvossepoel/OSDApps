# Wi-Fi profile staging

Run `Add-OSDAppWiFiProfile -Path <export.xml>` in WinPE after Windows has been applied. The command stages one built-in `WiFiProfiles` Script entry. Repeated calls merge profiles; a repeated, case-sensitive profile name replaces its previous staged definition. `-WindowsPath` is optional and uses normal offline Windows discovery.

The initial implementation accepts Windows WLAN XML exports for WPA2-Personal, WPA3-Personal and unencrypted open networks. Enterprise/EAP credentials, WEP and machine-protected shared keys are rejected before staging. Export personal profiles on the preparation PC using `netsh wlan export profile name="profile-name" folder="C:\OSDApps\TestWiFi" key=clear`. Do not commit or upload the export: it contains a clear-text shared key.

During SetupComplete the runtime starts WlanSvc if necessary, enumerates enabled WLAN interfaces and imports each profile on every interface using WlanSetProfile (flags=0, overwrite=true). Existing same-name profiles are updated. Import success means Windows accepted the profile; it does not prove authentication or connectivity. The XML connection mode is preserved, so Windows may connect automatically if the exported profile requests it. OSDApps does not issue a connect command.

No adapter, unavailable/disabled WLAN service, missing driver, unsupported security or any failed interface import produces a failed result in that same run. There is no retry task, reboot request or post-reboot verification. Independent profiles continue after individual import failures.

## Credential handling

Staging contains the profile XML in `BuiltIn\WiFiProfiles\config.json`. Before writing credentials, the staging directory receives a protected ACL granting only SYSTEM and Administrators full control. Script and configuration hashes are checked by the deployment validator and runner. Logs and reports contain profile names and numeric WLAN return/reason codes, never XML or shared keys.

The runtime removes its credential-bearing config in its `finally` block after a single attempt, including on failure and with `CleanupMode Never`. Reports remain. This is normal file deletion, not secure disk erasure. If execution never reaches the Wi-Fi runtime (for example power loss or an earlier integrity failure), the restricted config remains until staging is removed. The source export on the preparation PC/USB is never deleted by OSDApps. Removing the config means this entry cannot be rerun or revalidated after execution; use fresh deployment staging for another attempt.

## WinPE example

```powershell
$usb = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($usb.Count -ne 1) { throw 'Expected exactly one OSDCloud volume.' }
$profile = Join-Path "$($usb[0].DriveLetter):\" 'OSDApps-TestData\WiFi\Wi-Fi-FSOCIETY.xml'
Add-OSDAppWiFiProfile -Path $profile
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

Read `WiFiProfiles-Result.json` alongside the normal deployment reports. Physical SetupComplete validation is still required before release.

API references: [WlanSetProfile](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlansetprofile), [WlanEnumInterfaces](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlanenuminterfaces).
