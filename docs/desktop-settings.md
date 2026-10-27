# Time zone and initial Start/taskbar pins

All three commands are opt-in. The module has no hardcoded region or default pin list. Configure in WinPE after OSDCloud has applied Windows and **before the first boot** into that image. See [the combined example](../Examples/Stage-OSDAppsDesktopTest.ps1).

```powershell
Add-OSDAppTimeZone -Id 'W. Europe Standard Time'
Add-OSDAppStartPins -Pins @(
    @{desktopAppId='MSEdge'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
    @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
)
Add-OSDAppTaskbarPins -Pins @(
    @{desktopAppId='MSEdge'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
)
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

## Preparing the USB test module

On a full Windows preparation PC, run `tools/Prepare-OSDAppsDesktopTest.ps1 -Revision <40-character commit SHA>`. It discovers exactly one volume labeled OSDCloud, downloads that immutable revision and copies it into a new `TestModules/OSDApps-Desktop-<short SHA>` folder. It does not replace the normal module or reset the cache. Existing test folders are not overwritten. ZIP extraction uses .NET ZipFile.

In WinPE, import `OSDApps.psd1` from that exact test folder and run its `Examples/Stage-OSDAppsDesktopTest.ps1` after deployment completes. The example uses a Dutch time zone only as test input; the public command requires an explicit ID for every deployment.

## Configuration contract

- `Add-OSDAppTimeZone -Id` stages a literal Windows time zone ID. Runtime validates against the target catalogue, applies it once and reads it back during that same invocation. It does not disable automatic time zone updates or impose a policy. Subsequent OOBE location detection or management can change the zone. Use Intune or other management if a lasting enforced zone is required.
- `Add-OSDAppStartPins -Pins` accepts ordered objects with exactly one `desktopAppId`, `packagedAppId` or `desktopAppLink`. IDs identify installed Windows apps, not OSDApps repository packages. Prefer IDs for international deployments. Literal local .lnk paths with supported Windows environment variables are also accepted. No new shortcuts are created.
- `Add-OSDAppStartPins -JsonPath` accepts an existing exported JSON containing `pinnedList` and optionally `applyOnce: true`. `applyOnce: false`, unknown keys and website secondary tiles are rejected in this first version. The staged data is normalized, so the source file is not needed at execution.
- `Add-OSDAppTaskbarPins -Pins` uses the same pin objects and order. XML is generated with the Windows namespaces and `PinListPlacement="Replace"`. Start, Search, Widgets and other taskbar controls are not app pins and are not changed.
- An explicit empty array requests an empty app pin list. Omission means no change.
- Calling a command again replaces that entire setting, preserving the other desktop settings. All three share one `DesktopSettings` bundled Script queue entry, with SHA-256-validated script and configuration. No repository, cache synchronization, download or `Expand-Archive` is used.

## Start execution and support

One-time Start configuration requires Windows 11 Pro, Enterprise, Education or IoT Enterprise, build **26100.4770 (24H2 + KB5062660)** or later. Older systems and Home/Server are refused. The target StartMenu.admx must contain the supported file-based Configure Start Pins policy. Both staging and runtime validate compatibility.

SetupComplete writes `%ProgramData%\OSDApps\Configuration\StartPins.json` with `applyOnce: true` and enables the native machine policy (`ConfigureStartPins` DWORD and `ConfigureStartPinsJSON` file path). The mapping is verified against the target ADMX. The file deliberately remains outside temporary staging so Windows can initialize future user profiles. There is no Start2.bin copy, fake MDM provider, scheduled task, RunOnce or per-user script.

Windows applies the list when the user signs in. Users can then change their pins. A later Intune/GPO Start policy can supersede this initial configuration. Apps must be installed and registered for their pins to appear; OSDApps does not install a missing app simply because it appears in this list. No automatic verification or correction occurs after sign-in.

## Taskbar timing and ownership

`LayoutXMLPath` must exist **before specialize**. Therefore TaskbarPins is applied directly to the offline image during the Add command, not deferred to SetupComplete. OSDApps temporarily loads only the target SOFTWARE hive under a unique HKLM mount, closes every registry handle and unloads it. The preparation PC/WinPE active Explorer registry is never changed.

The durable XML is `Windows\OEM\OSDApps\TaskbarLayoutModification.xml` on the target volume. The registry path uses the future SystemRoot from that image; no WinPE drive letter is hardcoded into the configuration. A hash ownership marker protects replacement of previously prepared layouts. Foreign or modified configurations fail without replacement. A failed queue/file commit restores the previous XML and registry values.

This command is for freshly applied images. Reusing an already-specialized Windows installation is not supported. Removing just the queue would not undo the taskbar configuration, so `Remove-OSDAppStaging -Name DesktopSettings` refuses when TaskbarPins is present. Reapply the image to discard offline taskbar changes. Runtime cleanup intentionally retains the durable Windows layout.

## Results and validation

`DesktopSettings-Result.json` is written alongside the configured runtime result file. It includes DeploymentId, separate setting outcomes, errors and success/failure counts. TimeZone reports Applied/Unchanged. StartPins reports ConfiguredForFirstSignIn. TaskbarPins reports PreparedOffline, not a claim that Windows rendered the expected pins.

The existing deployment preflight validates script/configuration integrity and the generated taskbar XML. SetupComplete runs once; no restart is forced and no follow-up correction is scheduled.

Automated coverage uses disposable files/registry hives and mocks for unavailable Windows 11 shell behavior. The end-to-end runner test uses the CI host's current zone to avoid changing it. **Physical Windows 11/OOBE validation is still required**, including the exact Edge/Explorer/Settings Start order, Edge/Explorer taskbar order, and successful opening of each app. Normal first sign-in is sufficient for the initial visual test; no extra reboot is required.

## Microsoft references

- [Configure Start layout and applyOnce](https://learn.microsoft.com/windows/configuration/start/layout)
- [Start CSP and Group Policy mapping](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-start#configurestartpins)
- [Taskbar offline image configuration and before-specialize timing](https://learn.microsoft.com/windows-hardware/customize/desktop/customize-the-windows-11-taskbar)
- [Taskbar app IDs and replacement layout](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps)
