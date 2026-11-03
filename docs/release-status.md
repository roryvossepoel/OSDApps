# Release availability

[Documentation](README.md) · [Getting started](getting-started.md) · [Changelog](../CHANGELOG.md)

**Release candidate: OSDStage 1.0.0-rc4 (3 November 2026).** This is not GA.
RC4 adds automatic JSON/HTML delivery reports and continues to the final Windows
Update pass after individual package failures. It includes the existing apps,
configuration, file operations, automatic content acquisition/caching and compact output.

The GitHub prerelease is published and the [Gallery publication and package verification](https://github.com/roryvossepoel/OSDStage/actions/runs/41699262042)
succeeded. A merge alone does not publish a package. Exact version links:
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

On full Windows or online WinPE with PowerShellGet:

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

## Published RC4 acceptance

The [3 November Gallery acceptance record](rc4-gallery-acceptance.md) covers the
published package on two physical x64 devices running Windows 11 26H2 build
26300.9711. Both used the same three-entry profile: 7-Zip, XPS Viewer and Windows
Update last, with driver updates enabled.

| Result | Dell Pro Micro QCM1250 | Surface Laptop Go 2 |
| --- | --- | --- |
| OSDStage packages | 3/3 succeeded; no failures or skips | 3/3 succeeded; no failures or skips |
| Delivery-report checks | 8/8 passed | 8/8 passed |
| Selected Windows Updates | 36/36 installed | 4/4 installed |
| Restart required by this OSDStage run | Yes | No |
| Restart requested by OSDStage | No | No |

The maintainer separately confirmed normal OOBE completion and first sign-in on
both devices, with Autopilot/Intune proceeding normally where applicable. This is
operator-confirmed handoff evidence; the supplied OSDStage reports do not audit
enrollment or identify which device was registered in Autopilot.

The [delivery report guide](delivery-report.md#broad-component-acceptance-3-november-2026)
retains the earlier broad 19-package test, all 18 report checks and confirmed
manual checks. That source test and the two published-package runs cover
different scopes; the broad test does not need repeating solely for closeout.

Monthly cumulative Windows/.NET updates were not offered in the two RC4 runs.
Their physical servicing test remains open, along with the explicit variant
limits in the [validation register](feature-status.md). Neither an empty future
update scan nor every architecture/hardware combination is implied. RC4 remains
a prerelease; a stable 1.0.0 version requires a separate reviewed release decision
and the [release procedure](releasing.md).
