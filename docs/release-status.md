# Release availability

[Documentation](README.md) · [Getting started](getting-started.md) · [Changelog](../CHANGELOG.md)

**Documentation baseline: 2 November 2026.** The published preview is [OSDStage 1.0.0-rc2](https://www.powershellgallery.com/packages/OSDStage/1.0.0-rc2), with its matching [GitHub release](https://github.com/roryvossepoel/OSDStage/releases/tag/v1.0.0-rc2). It is a release candidate, not GA.

RC2 includes the tested changes merged after RC1. A later merge does not automatically update the Gallery package.

| Capability | Gallery 1.0.0-rc1 | Gallery 1.0.0-rc2 |
| --- | --- | --- |
| Built-in app installers, repository packages and device configuration | Available | Available |
| Company Portal and CMTrace Open | Prepare their cache on full Windows, then stage in WinPE | Also acquire, refresh and cache automatically during online PreInstall |
| File and directory commands | Not included | Available; see [file operations](file-system.md) |
| Timestamped compact output | Not included | Available; see [console output](console-output.md) |
| Windows Update staging | Not included | Not included; separate experimental [PR #111](https://github.com/roryvossepoel/OSDStage/pull/111) |

## Install the published preview

On full Windows or online WinPE with PowerShellGet available:

```powershell
Install-Module OSDStage -Repository PSGallery -RequiredVersion '1.0.0-rc2' `
    -AllowPrerelease -Force -ErrorAction Stop
Import-Module OSDStage -RequiredVersion '1.0.0' -Force
```

PowerShell uses numeric module version `1.0.0`; `rc2` is separate prerelease metadata. RC1 and RC2 share that numeric folder. Close existing PowerShell sessions before upgrading, then verify both the identity and loaded path in a fresh session:

```powershell
Get-Module OSDStage | Select-Object Name, Version, Path,
    @{Name='Prerelease';Expression={$_.PrivateData.PSData.Prerelease}}
```

A published preview cannot contain changes merged after its release. Use an explicitly reviewed commit or CI artifact when testing those changes; identify the revision in the test result. See [release procedure](releasing.md) for maintainers and [validation records](testing.md) for what has actually been tested.
