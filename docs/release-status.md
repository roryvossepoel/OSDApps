# Release availability

[Documentation](README.md) · [Getting started](getting-started.md) · [Changelog](../CHANGELOG.md)

**Release candidate: OSDStage 1.0.0-rc3 (3 November 2026).** This is not GA.
RC3 adds the Windows Update pass and includes the existing RC2 apps, configuration,
file operations, automatic content acquisition/caching and compact output.
The JSON/HTML delivery report is a separate planned addition and is not included.

Publication is complete only when the [release and Gallery workflows](https://github.com/roryvossepoel/OSDStage/actions)
succeed. A merge alone does not publish a package. Exact version links:
[PowerShell Gallery](https://www.powershellgallery.com/packages/OSDStage/1.0.0-rc3) ·
[GitHub prerelease](https://github.com/roryvossepoel/OSDStage/releases/tag/v1.0.0-rc3).

| Capability | RC2 | RC3 |
| --- | --- | --- |
| Apps, repository packages and device configuration | Available | Available |
| Automatic Company Portal/CMTrace acquisition and USB caching | Available | Available |
| File/directory commands and compact output | Available | Available |
| One Windows Update pass last in SetupComplete | Not included | Available |
| Opt-in all-class drivers/firmware and optional class selection | Not included | Available |
| JSON/HTML delivery report | Not included | Not included |

## Install the release candidate

After verified publication, on full Windows or online WinPE with PowerShellGet:

```powershell
Install-Module OSDStage -Repository PSGallery -RequiredVersion '1.0.0-rc3' `
    -AllowPrerelease -Force -ErrorAction Stop
Import-Module OSDStage -RequiredVersion '1.0.0' -Force
```

PowerShell uses numeric module version `1.0.0`; `rc3` is separate prerelease
metadata. RC1, RC2 and RC3 share that numeric folder. Close existing PowerShell
sessions before upgrading, then verify the identity and loaded path in a fresh session:

```powershell
Get-Module OSDStage | Select-Object Name, Version, Path,
    @{Name='Prerelease';Expression={$_.PrivateData.PSData.Prerelease}}
```

The [Windows Update guide](windows-update.md) records the successful x64
SetupComplete and regular OOBE test, the separate post-restart Settings round,
and remaining field coverage. It does not claim Autopilot or monthly cumulative
Windows/.NET acceptance. See [release procedure](releasing.md) for maintainers.
