# Wallpaper and lock screen configuration

Status: implemented in the development branch; not yet released. Physical WinPE/OOBE rendering and user editability still require the test described below.

## Command contract

Two independent commands select images from repository packages:

```powershell
# Initial images that users may change later
Add-OSDAppWallpaper -Id 'FinanceWallpaper'
Add-OSDAppLockScreen -Id 'FinanceLockScreen'

# Managed images that users may not change
Add-OSDAppWallpaper -Id 'FinanceWallpaper' -Enforce
Add-OSDAppLockScreen -Id 'FinanceLockScreen' -Enforce
```

`-Id` identifies a repository package, not a department, URL or Windows app ID. Each package uses `package.zip` and the existing repository cache and integrity checks. Use `PackageType Image` and `Architecture any`. `Package.zip` must contain exactly one JPG, JPEG or PNG file directly inside `Package/`, no scripts or nested directories. The image is limited to 20 MiB and the ZIP to 21 MiB. Use a simple ASCII filename; validation checks signatures and structure, not full pixel decoding. Existing App or Script packages are not reinterpreted as images.

Omitting a command leaves that background unconfigured by OSDApps. Omitting `-Enforce` requests a changeable initial image; it does not remove another administrator's policy. `-Enforce` controls user editability, not overwrite permission, cache refresh, approval bypass or repeated execution.

Themes, light/dark mode, accent colors and screensavers are outside this feature. Wallpaper and lock screen may be configured independently, with different enforcement choices.

## Mechanism and user experience

The same command interface does not imply the same Windows implementation. The implemented routes are:

| Command | Without `-Enforce` | With `-Enforce` |
| --- | --- | --- |
| Wallpaper | Windows Setup `Microsoft-Windows-Shell-Setup\Themes`: merge `DesktopBackground` and the required `ThemeName` into the target answer file before first boot. Set an initial background; users may change it. | Personalization CSP `DesktopImageUrl`, called through the documented WMI Bridge in the installed Windows system under SYSTEM. Users cannot change the managed image. |
| Lock screen | Native machine policy `Force a specific default lock screen and logon image`, without enabling `Prevent changing lock screen and logon image`. Establish the default image; users may choose another. | Personalization CSP `LockScreenImageUrl`, called through the documented WMI Bridge under SYSTEM. Users cannot change the managed image. |

The required internal `ThemeName` for the wallpaper Setup route does not introduce a public theme-setting feature. Existing color, mode and other answer-file settings must be preserved. The command merges the oobeSystem pass in `Windows\Panther\unattend.xml`, or creates that file when absent. Alternative answer files, conflicting background definitions, processed passes and a conflicting SYSTEM Setup UnattendFile selection are refused. The target kernel determines amd64 versus arm64. OSDCloud compatibility still requires a physical test.

The default lock screen route itself uses persistent native policy: "changeable default" does not mean "no policy exists." Microsoft documents that the separate prevent-changing policy is needed to always force that default image. The default policy also affects the logon image when nobody is signed in. This behavior and continued user editability require physical validation.

The CSP route uses `MDM_Personalization` in `root\cimv2\mdm\dmmap`. Its URLs point to persistent local image files. It runs once through SetupComplete; it does not call the installed system's provider from WinPE. Direct writes to internal `PersonalizationCSP` or PolicyManager state are not a substitute for invoking the provider. Read status from Windows; never manufacture a success status.

## Edition and policy boundaries

The documented effective target for the lock screen default route is Windows 11 Enterprise/Education or IoT Enterprise, build 22000 or later, subject to physical validation. Microsoft's policy description explicitly limits that setting to Enterprise, Education and Server editions; this module design does not add Server support.

Personalization CSP documentation is inconsistent about ordinary Pro support: its reference describes Enterprise/Education support and conditional Pro support, while the background configuration guide lists Pro as supported. Do not advertise unconditional Pro support for the CSP routes until this discrepancy and the target behavior are resolved. Do not enable Shared PC or education policies as a workaround.

Default wallpaper supports Windows 11 Pro, Enterprise, Education and IoT Enterprise. For lock screen in either mode and enforced wallpaper, Pro-family editions now produce an advisory warning instead of a terminating edition error. Both WinPE staging and the one-shot SetupComplete runtime continue, because subscription activation may step up Pro to Enterprise, or Pro Education to Education, at user sign-in. This does not guarantee that Windows honors the setting on Pro or automatically applies it after an edition change. The native default lock screen policy and image remain available; there is no retry or post-sign-in task. With Enforce, actual CSP/provider failures still fail normally and roll back; a possible future upgrade is not treated as a successfully applied image. All routes require Windows 11 client build 22000 or later; Home and Server are still refused before image acquisition. Existing local background policy and answer-file conflicts are refused. This cannot predict policy that a future Intune enrollment will deliver. A later management policy can supersede these settings; OSDApps must not fight it.

## Storage and lifecycle

Persistent images are stored under `%SystemRoot%\OEM\OSDApps\Branding\<RepositoryId>\<SHA256>.<extension>`. Resolve the offline target and its eventual Windows path separately; do not persist a temporary WinPE drive letter. Discover USB cache volumes by their configured label, never by a fixed drive letter.

The existing cache supplies validated content. Temporary deployment staging may be cleaned up after success, but active background files remain. ZIP extraction must use the existing WinPE-compatible extraction path, not `Expand-Archive`. System-owned Windows wallpaper files and their permissions are not replaced.

No additional reboot, scheduled logon task, post-sign-in correction or recurring enforcement script is introduced. Windows handles initial profile creation and native policy enforcement. A successful staging result must not be reported as proof that the shell displayed the image.

## Department selection

Keep separate packages in the repository for different departments. The launcher chooses one wallpaper and one lock screen for each device deployment, for example:

```powershell
# The launcher supplies a validated department selection.
$departmentImages = @{
    Finance = @{ Wallpaper = 'FinanceWallpaper'; LockScreen = 'FinanceLockScreen' }
    Operations = @{ Wallpaper = 'OperationsWallpaper'; LockScreen = 'OperationsLockScreen' }
}

if (-not $departmentImages.ContainsKey($Department)) {
    throw "No background packages configured for department '$Department'."
}
$images = $departmentImages[$Department]
Add-OSDAppWallpaper -Id $images.Wallpaper
Add-OSDAppLockScreen -Id $images.LockScreen -Enforce
```

These are device deployment choices, not automatic department discovery or per-user group targeting. A shared computer does not select a different departmental image for each user through these commands. Multiple repository packages are supported, but only one active image per background setting is selected for a deployment; no slideshow is implied.

## Package authoring and cache

On the full Windows preparation PC, place one image in the source directory:

```powershell
$package = New-OSDAppPackage -Id FinanceWallpaper -Version 1.0.0 -PackageType Image -SourcePath 'C:\Images\Finance' -OutputPath 'C:\ImageBuild'
Add-OSDAppPackage -Id FinanceWallpaper -DisplayName 'Finance wallpaper' -Version 1.0.0 -PackageType Image -Architecture any -PackagePath $package.PackagePath -RepositoryPath 'C:\OSDAppsRepo'
Sync-OSDAppRepository -Name FinanceWallpaper
```

The last command uses your configured published catalog and the normal cache. Publish the repository using your existing workflow first. `Add-OSDAppWallpaper` and `Add-OSDAppLockScreen` refresh their selected package unless `-SkipCacheRefresh` is supplied. A failed refresh may fall back only to a SHA-256 validated cached Image archive. A missing USB uses a temporary cache on the target disk. `-WhatIf` does not acquire or stage content.

Both settings share the `DesktopSettings` queue entry with Start/taskbar settings. The generated script and configuration are hash-validated; each persistent image is hash-validated during preflight and runtime. The ZIP is extracted with .NET, never executed. Direct `Add-OSDApp` rejects Image packages: the background command must select their purpose and enforcement mode.

Select each background once per fresh image. A second call for the same background is refused to avoid leaving an earlier answer-file setting behind. `Remove-OSDAppStaging` refuses to discard DesktopSettings once background files/settings have been prepared; reapply a fresh image to discard them.

## Physical test preparation

Run `tools/Prepare-OSDAppsBackgroundTest.ps1 -Revision <full commit SHA>` on your full Windows preparation PC with the OSDCloud USB connected. It copies a pinned test module to a new folder, generates two distinctly labeled test PNGs, builds Image packages and synchronizes only those test IDs into the existing cache. It does not change your configured production catalog or reset the cache. Optional WallpaperPath and LockScreenPath parameters use your own images instead.

In WinPE, after OSDCloud applies **Windows 11 Pro, Enterprise or Education**, import that exact test module and run `Examples/Stage-OSDAppsBackgroundTest.ps1`. The default test sets both images as changeable defaults. On Pro, expect an edition warning for the lock screen and continued staging; its visible effect before or after subscription activation still requires observation. On a separate fresh deployment, add `-EnforceWallpaper -EnforceLockScreen` to test both enforced variants; switches can also be selected independently. Use the normal installation reboot only. Do not add checks or correction scripts to the deployed system.

At first sign-in, visually check the labeled wallpaper. Lock the session to check the lock screen. In Settings, manually test changing the images: allowed without Enforce, blocked with Enforce. These are acceptance observations, not deployment automation. The CSP may report `Submitted` with status 2 while Windows is copying; this is not reported as proof that the image was applied. No retry loop is added.

`DesktopSettings-Result.json` records the mode, technique, image path and per-setting outcome. Retain that result plus the normal runtime log for diagnosis. SetupComplete never reapplies these settings on later sign-ins.

## Acceptance requirements

- Validate package integrity, image format, persistent destination and target compatibility before committing changes.
- Preserve unrelated answer-file content and refuse conflicting settings; restore owned changes if staging fails.
- Test wallpaper and lock screen separately, both with and without enforcement, on each advertised Windows edition/build.
- Confirm images at normal first sign-in and lock, and manually confirm whether changing each image is allowed. These are development acceptance tests, not added deployment tasks.
- Confirm staging cleanup retains active images and that no additional restart or follow-up task is created.
- Include the actual Windows mechanism, edition support, persistence and user editability in command help and the released user guide.

## Microsoft references

- [Subscription activation and edition changes at user sign-in](https://learn.microsoft.com/en-us/windows/deployment/windows-subscription-activation)

- [Themes settings and required default-theme elements](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-themes)
- [Default lock screen and prevent-changing policies](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-controlpaneldisplay#cpl_personalization_forcedefaultlockscreen)
- [Personalization CSP behavior and edition restrictions](https://learn.microsoft.com/en-us/windows/client-management/mdm/personalization-csp)
- [Background configuration guide and edition tables](https://learn.microsoft.com/en-us/windows/configuration/background/)
- [MDM_Personalization WMI class](https://learn.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-personalization)
- [PowerShell WMI Bridge and SYSTEM context](https://learn.microsoft.com/en-us/windows/client-management/using-powershell-scripting-with-the-wmi-bridge-provider)
