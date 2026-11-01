# OSDStage rename acceptance

Recorded on 31 October 2026 for candidate
`5c0bd44f734296709439e3707337bb3291f29874` in PR #99.
Deployment ID: `1f2adf99-55d4-4880-b359-419f78eb52a4`.

## Scope and result

The maintainer deployed the renamed module after OSDCloud, using a schema 2
HTTP repository and an initially empty OSDStage cache. The staging record
confirms `EmptyCacheAtStart=true`. The normal commands acquired their content;
there was no separate deployment-cache preparation step.

All seven selected entries succeeded, with zero failures or skipped entries.
PreInstall completed in 17.6 seconds and runtime execution in 40.4 seconds.
All supplied results match the deployment ID above. Runtime result schemas are
2.0 and feature result schemas are 2.

| Entry | Recorded result |
| --- | --- |
| RepoTestFonts | Seven font files installed machine-wide and natively loaded; zero failures. |
| RepoTestRootCA | Public test CA imported into LocalMachine Root; zero failures. The historical certificate subject still contains OSDApps. |
| RepoTestRealtekUSB | Six INFs added to the Driver Store; zero failures and no restart requested. Device binding was not confirmed. |
| RepoTestWiFiProfile | Version 2.0.0 generic Script package imported one WLAN profile with native error/reason codes zero. Connectivity was not tested by these results. |
| GoogleChromeEnterprise | Downloaded into the automatically detected OSDCloud USB cache, Google publisher validated, then MSI installed with exit code zero. No acquisition fallback or warnings. Interactive app launch was not reported. |
| RegistrySettings | One revision marker created in the explicit 64-bit registry view. |
| EnvironmentVariables | One machine variable set; notification succeeded, with no reboot requested. |

The four repository payloads passed SHA-256 validation before execution.
Owned cache, staging and result paths use OSDStage. The USB drive letter was
resolved dynamically; it was E: in this run, not a configured requirement.

## Independent device confirmation

The maintainer reported all four read-only checks returned True:

- `C:\Windows\Temp\OSDStage` no longer exists after OnSuccess cleanup.
- Machine variable `OSDStageSmoke` equals `5c0bd44`.
- The 64-bit `HKLM:\SOFTWARE\OSDStage\Tests\Rename` Revision value equals
  the full tested candidate SHA above.
- Test certificate thumbprint `F9B39A963076665861302A72E523C54C320AC8BA`
  exists in `Cert:\LocalMachine\Root`.

The runtime log records cleanup scheduling; the separate device check confirms
actual removal. Supplied logs/results contain no Wi-Fi password or profile XML.
This is not a whole-disk secret scan: original XML exports, repository and USB
cache ZIPs, and the installed Windows WLAN profile remain outside the runtime
staging-cleanup claim. Raw private logs and credential-bearing payloads are not
committed to this repository.

## Limits and follow-up

This validates the selected rename and empty-cache deployment path, not every
architecture, vendor app or configuration variant. Earlier feature evidence is
retained in [the feature register](feature-status.md). No additional device
reinstallation is required for this same acceptance scenario.

Two cosmetic start/completion messages still said OSD App Runner in the tested
candidate; the follow-up changes these to OSDStage Runner without changing
execution or cleanup behavior. Automated CI on that follow-up remains separate
from the physical evidence for the candidate SHA above.

Repository renaming, Gallery publication and public Pages publication are
separate actions, not implied by this acceptance record.
