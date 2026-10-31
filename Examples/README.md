# Examples

[Project](../README.md) · [Getting started](../docs/getting-started.md) · [Documentation](../docs/README.md)

Choose an example for the environment you are using. These are reference workflows, not additional recorded hardware test results; the actual test evidence is in the [validation matrix](../docs/testing.md).

| Example | Run on | Changes made |
| --- | --- | --- |
| [Combined feature acceptance](../docs/combined-acceptance.md) | Full Windows preparation, then WinPE staging | Uses a pinned test module, explicit repository IDs and normal cache; stages a representative test across retained configuration families. |
| [Prepare a USB cache](Prepare-UsbCache.md) | Full Windows preparation machine | Saves module files, optionally downloads/refreshes content, and shows explicit repository health/prune preview; does not stage apps against Windows. |
| [Online WinPE deployment](WinPE-Online.md) | WinPE after OSDCloud has applied Windows | Loads the module from Gallery and stages apps with or without a USB flash drive; optional repository sync downloads packages. |
| [WinPE launcher integration](Launcher-Integration.md) | WinPE, called by OSDT or another launcher | Loads from Gallery, stages the example queue and returns a checked exit code; the launcher owns the reboot. |
| [Offline WinPE deployment](WinPE-Offline.md) | WinPE with complete matching cache and networking disconnected | Stages cached content and SetupComplete without repository refresh. |
| [Build a repository package](Build-Repository-Package.md) | Full Windows authoring machine | Creates a package archive and local repository metadata. |

The deployment examples use x64 Microsoft 365 Apps (MonthlyEnterprise/en-us), Adobe Acrobat Unified and Google Chrome Enterprise. Preparation and staging select the same variants. The online example loads the module from Gallery and discovers an optional USB flash drive by label. The offline example loads the newest saved module from the USB flash drive and requires prepared content. Staging does not format disks or reboot automatically; the online guide shows a separate manual reboot command. Repository pruning appears only as a separate preview-and-confirm maintenance step.

Add other apps only after selecting their intended configuration. For example, match Office architecture, channel, language and products between cache preparation and staging. See [Built-in apps](../docs/built-in-apps.md).

## Build a repository package

Follow [From Install.ps1 to a repository package](Build-Repository-Package.md)
for a complete workflow on the Windows preparation machine:

1. Prepare your own unattended `Install.ps1` and supporting files.
2. Build the ZIP, add package metadata and check validation results.
3. Publish the static files and update the catalog last.
4. Stage the app or script package in WinPE.

The existing `PackageSource/ExampleApp/Install.ps1` file is only a layout
placeholder that prints a message and exits 0. It does not install an app;
replace it with your own logic before using it in a deployment.

## Repository template

`Repository/catalog.json` is an empty valid catalog template. It deliberately contains no real vendor installers or deployable sample apps. To start a new local repository without copying the template:

```powershell
New-OSDAppRepository -Path C:\OSDApps\Repository
```

See [Repository apps](../docs/repository.md) for per-app manifests, archive hashes, publishing and deployment. No tenant-specific URL, credential or organization deployment profile is supplied by these examples.
