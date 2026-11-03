# Windows inbox cleanup

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

The optional **built-in script** is staged in WinPE and runs once in SetupComplete under SYSTEM, before OOBE. It removes **only the package names you select**, from provisioning and existing user registrations. Protected and Windows NonRemovable components are skipped. The script logs a per-app result and returns nonzero if a requested removal failed. Because Appx behavior can change between Windows builds, test your selection on your own image before broad deployment.

```powershell
# WinPE after OSDCloud. No CatalogUri or USB cache is needed.
Import-Module OSDStage
Add-OSDStageWindowsInboxCleanup -Preset Tested13
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

The `Tested13` preset matches the 13 package names tested on Windows 11 25H2 during the repository proof of concept. The preset is opt-in: simply importing OSDStage never removes anything. For a custom list:

```powershell
Add-OSDStageWindowsInboxCleanup -Remove @(
    'Microsoft.BingWeather',
    'Microsoft.MicrosoftSolitaireCollection'
)
```

Use `-DiagnoseOnly` to inspect and log selected packages during SetupComplete without removing them. OSDStage copies the script plus `config.json` from the module to `BuiltIn\WindowsInboxCleanup` in the offline Windows staging folder, pins their SHA-256 hashes in `DeviceManifest.json`, and validates both before execution. The built-in script does not use Azure Blob Storage, package archives, publisher URLs or pre-install downloads. `Remove-OSDStageStaging -Name WindowsInboxCleanup` can remove it from the pending queue in WinPE.

The earlier standalone repository package is named `WindowsInboxAppCleanup`; the new built-in ID is `WindowsInboxCleanup`, so both identities remain distinct. Avoid selecting both on the same device.

After the first boot, check `%ProgramData%\OSDStage\Results\Latest.json`, `%ProgramData%\OSDStage\Results\InboxCleanup-Result.json`, and `%ProgramData%\OSDStage\Logs\InboxCleanup.log`. Additional early diagnostics are written to `%SystemRoot%\Temp\OSDStage-InboxCleanup-Diagnostics.log`. A successful OSDStage result is not a replacement for post-Autopilot verification.

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)

## Review the recorded result

The automatic [delivery report](delivery-report.md) includes the cleanup package status in its own configuration card. Keep the original cleanup result and runtime log for detailed removals; the delivery report does not invent per-item details when supported matching evidence is absent.
