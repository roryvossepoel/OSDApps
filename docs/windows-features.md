# Windows optional features

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

`Add-OSDStageWindowsFeature` stages explicit Windows optional feature names and applies them once during SetupComplete under SYSTEM. OSDStage does not maintain a feature-name catalog, offer feature-name autocomplete, infer dependencies, or select source media. The operator is responsible for supplying feature names that exist on the target Windows build.

```powershell
Add-OSDStageWindowsFeature -Enable @(
    'TelnetClient'
) -Disable @(
    'WorkFolders-Client'
)
```

The staged `WindowsFeatures` script itself requires no repository or payload download. Enabling a feature may still require Windows servicing content; there is no source-media parameter. Check the selected feature on your target image before relying on offline execution. Repeated Add calls build one operation set; the most recently staged desired state for a feature replaces its earlier state. Supplying the same feature to both `-Enable` and `-Disable` in one call is rejected.

SetupComplete queries the current state before changing anything. Already enabled/disabled features succeed idempotently. Remaining operations are still attempted when one feature fails. The aggregate script returns failure when any operation failed. Windows servicing is always called with `-NoRestart`; OSDStage records `RestartNeeded` and may return the normal 3010 success code to Runner, but does not reboot the device.

Results are written to `%ProgramData%\OSDStage\Results\WindowsFeatures-Result.json` by default. No DISM source/media management is included in this first implementation.

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
