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

In WinPE, import `OSDApps.psd1` from that exact test folder and run its `Examples/Stage-OSDAppsDesktopTest.ps1` after deployment completes. The example requests `Tokyo Standard Time` as deliberately different test input; the public command requires an explicit ID for every deployment.

## Configuration contract

- `Add-OSDAppTimeZone -Id` stages a literal Windows time zone ID. Runtime validates against the target catalogue, applies it once and reads it back during that same invocation. It does not disable automatic time zone updates or impose a policy. Subsequent OOBE location detection or management can change the zone. Use Intune or other management if a lasting enforced zone is required.
- `Add-OSDAppStartPins -Pins` accepts ordered objects with exactly one `desktopAppId`, `packagedAppId` or `desktopAppLink`. IDs identify installed Windows apps, not OSDApps repository packages. Prefer IDs for international deployments. Literal local .lnk paths with supported Windows environment variables are also accepted. No new shortcuts are created.
- `Add-OSDAppStartPins -JsonPath` accepts an existing exported JSON containing `pinnedList` and optionally `applyOnce: true`. `applyOnce: false`, unknown keys and website secondary tiles are rejected in this first version. The staged data is normalized, so the source file is not needed at execution.
- `Add-OSDAppTaskbarPins -Pins` uses the same pin objects and order. XML is generated with the Windows namespaces and `PinListPlacement="Replace"`. Only the requested app pins should appear at first sign-in; extra Windows defaults are a failed acceptance test. Each actual pin has `PinGeneration="1"` so supported Windows versions remember user unpinning. An empty list uses Microsoft's internal `#leaveempty` sentinel. Start, Search, Widgets and other taskbar controls are not app pins and are not changed.
- An explicit empty array requests an empty app pin list. Omission means no change.
- Calling a command again replaces that entire setting, preserving the other desktop settings. All three share one `DesktopSettings` bundled Script queue entry, with SHA-256-validated script and configuration. No repository, cache synchronization, download or `Expand-Archive` is used.

## Start execution and support

One-time Start configuration requires Windows 11 Pro, Enterprise, Education or IoT Enterprise, build **26100.4770 (24H2 + KB5062660)** or later. Older systems and Home/Server are refused. The target StartMenu.admx must contain the supported file-based Configure Start Pins policy. Both staging and runtime validate compatibility.

SetupComplete writes `%ProgramData%\OSDApps\Configuration\StartPins.json` with `applyOnce: true` and enables the native machine policy (`ConfigureStartPins` DWORD and `ConfigureStartPinsJSON` file path). The mapping is verified against the target ADMX. The file deliberately remains outside temporary staging so Windows can initialize future user profiles. There is no Start2.bin copy, fake MDM provider, scheduled task, RunOnce or per-user script.

Windows applies the list when the user signs in. Users can then change their pins. A later Intune/GPO Start policy can supersede this initial configuration. Apps must be installed and registered for their pins to appear; OSDApps does not install a missing app simply because it appears in this list. No automatic verification or correction occurs after sign-in.

## Taskbar application and ownership

Taskbar configuration requires the same Windows 11 business-edition baseline as Start pins: **26100.4770 or later**. This includes support for `PinGeneration`. OSDApps validates the target build and the `LockedStartLayout` / `StartLayoutFile` mapping in the target StartMenu.admx. Unsupported targets are refused rather than receiving a layout that restores user-unpinned apps.

The Add command prepares the **native machine Start Layout file policy** in the offline SOFTWARE hive, before first boot. It does not use the OEM `LayoutXMLPath` method: the first physical test of that method left Store and Outlook pins present despite `Replace` in the XML. Windows applies the taskbar-only XML at first sign-in. The separate Start JSON continues to use `applyOnce: true`.

The durable XML is `Windows\OEM\OSDApps\TaskbarLayoutModification.xml` on the target volume. The policy stores the future SystemRoot-based path, never the WinPE drive letter. `LockedStartLayout` is DWORD 1 and `StartLayoutFile` is the XML path under target `SOFTWARE\Policies\Microsoft\Windows\Explorer`. OSDApps temporarily mounts only the target SOFTWARE hive, disposes every registry handle and unloads it. The host registry is not configured.

**This is persistent native Windows policy, not taskbar `applyOnce`.** Windows can reread the configuration; the fixed `PinGeneration="1"` allows users to remove pins without restoring them on policy refresh. OSDApps does not schedule a logon script, cleanup task, post-boot verification, correction, or reboot. Later Intune/GPO policies may supersede these settings. Exact first-sign-in replacement and continued editability of both Start and taskbar remain physical acceptance criteria; registry/file success alone does not prove them.

A hash ownership marker protects replacements. Existing foreign or modified policy/layout values are refused, and failed commits restore the XML and both typed policy values. Unrelated Start policy values are preserved. This test revision requires a **freshly applied image**; do not apply it over the previous OEM test. `Remove-OSDAppStaging -Name DesktopSettings` refuses when TaskbarPins is present because removing the queue alone would leave the already-prepared image configuration behind. Reapply the image to discard it. Runtime cleanup retains the durable layout.

## Results and validation

`DesktopSettings-Result.json` is written alongside the configured runtime result file. It includes DeploymentId, separate setting outcomes, errors and success/failure counts. TimeZone reports Applied/Unchanged. StartPins reports ConfiguredForFirstSignIn. TaskbarPins reports PreparedOffline, not a claim that Windows rendered the expected pins.

The existing deployment preflight validates script/configuration integrity and the generated taskbar XML. SetupComplete runs once; no restart is forced and no follow-up correction is scheduled.

Automated coverage uses disposable files/registry hives and mocks for unavailable Windows 11 shell behavior. The end-to-end runner test deliberately selects a different time zone, checks `Applied` plus before/after values, and restores the original CI host zone in `finally`. **Physical Windows 11/OOBE validation is still required**, including the exact Edge/Explorer/Settings Start order, **Settings/Explorer only** on the taskbar (no Edge, Store or Outlook), and successful opening of each app. Confirm that pins in both Start and taskbar can still be changed. The time zone result must report `Applied`, different before/after IDs, and `After: Tokyo Standard Time`; `Unchanged` does not validate changing a time zone. OOBE may subsequently change the time zone; record that separately rather than masking it with a correction task. Normal first sign-in is sufficient for the initial visual test; no extra reboot is required.

## Microsoft references

- [Configure Start layout and applyOnce](https://learn.microsoft.com/windows/configuration/start/layout)
- [Start CSP and Group Policy mapping](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-start#configurestartpins)
- [Taskbar app IDs and replacement layout](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps)
