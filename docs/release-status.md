# Release availability

[Documentation](README.md) · [Getting started](getting-started.md) · [Changelog](../CHANGELOG.md)

**Release candidate: OSDStage 1.0.0-rc4 (3 November 2026).** This is not GA.
RC4 adds automatic JSON/HTML delivery reports and continues to the final Windows
Update pass after individual package failures. It includes the existing apps,
configuration, file operations, automatic content acquisition/caching and compact output.

Publication is complete only when the [release and Gallery workflows](https://github.com/roryvossepoel/OSDStage/actions)
succeed. A merge alone does not publish a package. Exact version links:
[PowerShell Gallery](https://www.powershellgallery.com/packages/OSDStage/1.0.0-rc4) ·
[GitHub prerelease](https://github.com/roryvossepoel/OSDStage/releases/tag/v1.0.0-rc4).

| Capability | RC3 | RC4 |
| --- | --- | --- |
| Apps, repository packages and device configuration | Available | Available |
| Automatic Company Portal/CMTrace acquisition and USB caching | Available | Available |
| File/directory commands and compact output | Available | Available |
| One Windows Update pass last in SetupComplete | Available | Available |
| Opt-in all-class drivers/firmware and optional class selection | Available | Available |
| JSON/HTML delivery report with component evidence | Not included | Available |
| Attempt Windows Update after an earlier individual package failure | Skipped | Attempted; earlier failure preserved |

## Install the release candidate

After verified publication, on full Windows or online WinPE with PowerShellGet:

```powershell
Install-Module OSDStage -Repository PSGallery -RequiredVersion '1.0.0-rc4' `
    -AllowPrerelease -Force -ErrorAction Stop
Import-Module OSDStage -RequiredVersion '1.0.0' -Force
```

PowerShell uses numeric module version `1.0.0`; `rc4` is separate prerelease
metadata. RC1 through RC4 share that numeric folder. Close existing PowerShell
sessions before upgrading, then verify the identity and loaded path in a fresh session:

```powershell
Get-Module OSDStage | Select-Object Name, Version, Path,
    @{Name='Prerelease';Expression={$_.PrivateData.PSData.Prerelease}}
```

The [Windows Update guide](windows-update.md) records the successful x64
SetupComplete and regular OOBE test, the separate post-restart Settings round,
and remaining field coverage. It does not claim Autopilot or monthly cumulative
Windows/.NET acceptance. See [release procedure](releasing.md) for maintainers.

The [delivery report guide](delivery-report.md#broad-component-acceptance-3-november-2026) records the broad 19-package test, all 18 report checks and the confirmed manual checks. Reports describe execution and evidence; they do not certify Autopilot enrollment or that no future updates remain.
