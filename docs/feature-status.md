# Feature scope and validation register

[Documentation](README.md) · [Getting started](getting-started.md) · [Release availability](release-status.md)

**Status baseline: 3 November 2026.** OSDStage `1.0.0-rc4` is published on PowerShell Gallery and GitHub as a release candidate. Windows Update and automatic JSON/HTML delivery reports are included; see [release availability](release-status.md). A stable `1.0.0` release remains a separate decision.

The combined, repository-only, renamed empty-cache and published RC4 deployments have recorded acceptance within their stated limits. Identify development test modules by commit and published packages by release version and tag. No migration or old-command aliases are planned.

## Current work order

1. Preserve the accepted deployment evidence and technical contracts; investigate
   changed behavior or a specific remaining coverage gap.
2. Collect targeted monthly cumulative Windows/.NET update evidence when those
   updates are offered on a test device.
3. Review the documented scope and limits, then explicitly decide whether to
   prepare a stable `1.0.0` release using the [release procedure](releasing.md).

The Windows Viewer and web catalog viewer are read-only. Neither is an interactive deployment editor. See [the viewer guide](viewer.md).

The OSDStage name and public GitHub Pages site at [osdstage.com](https://osdstage.com/)
are delivered, including the mobile navigation in
[PR #124](https://github.com/roryvossepoel/OSDStage/pull/124). Interactive Viewer
expansion remains deferred.

The tables retain earlier device evidence with its original commit and deployment
IDs. Earlier test completion does not establish every architecture or variant.

## RC4 acceptance — 3 November 2026

The [published Gallery RC4 acceptance](rc4-gallery-acceptance.md) records WinPE
staging and normal SetupComplete execution on a Dell Pro Micro QCM1250 and a
Surface Laptop Go 2, both running Windows 11 build 26300.9711 x64. Each completed
the same three-entry profile: 7-Zip, XPS Viewer and a final Windows Update pass.
All three entries and all eight report checks passed on each device. Neither
run requested an automatic restart.

The earlier [broad component acceptance](delivery-report.md#broad-component-acceptance-3-november-2026)
remains valid: 19 packages, 18 report checks and 11 matched component evidence
groups on the Dell. The focused Gallery runs establish the published package
path; they do not replace or require repetition of that broader acceptance.

The maintainer confirmed normal OOBE and first sign-in on both devices, with
Autopilot/Intune proceeding normally where applicable. Those observations are
operator evidence, separate from the execution reports. Monthly cumulative Windows/.NET updates
were not exercised by the offers in these runs. ARM64 and the individual variant
limits below remain outside the recorded physical coverage.

## Deployment contract

- Prepare content on full Windows; stage against the applied Windows image in
  WinPE after OSDCloud. Discover USB media by label `OSDCloud`, never a fixed letter.
- Repository payloads use `Package.zip` with the existing catalog, version,
  cache and SHA-256 checks. Use WinPE-compatible ZIP handling, not a dependency
  on `Expand-Archive` being loadable there.
- Execute once during the normal deployment flow. No forced extra reboot,
  scheduled retry, post-sign-in correction or recurring enforcement is added.
  Report a Windows restart requirement without arranging the restart.
- Manual observation during a test is evidence collection, not a new automated
  deployment step. Do not introduce post-reboot repair to make a test pass.
- Keep the module international: no implicit regional defaults, organization
  identity, pin list or hardware applicability inference.
- Record partial failure and limits honestly. Staging, installer exit codes,
  rendered UI, connectivity and hardware function are different outcomes.

## Evidence labels

**Recorded pass** means the linked record describes a physical result for a
specific scenario. **Operator-confirmed** means the maintainer reported the
observation, with the stated limits. **Evidence pending** means implementation
exists but a sufficient practical result is not recorded here; it does not mean
the feature failed or was never tried. CI is separate evidence and never proves
WinPE, hardware, OOBE or user-visible behavior by itself.

Older PR descriptions sometimes still say draft or pending after merge. Their
merge state does not fill a practical evidence gap. Recover existing results
before asking for another deployment; do not repeat a passed scenario solely
to complete this table.

## Existing deployment foundation

| Feature | Contract and evidence | Remaining boundary |
| --- | --- | --- |
| Repository apps and scripts | Built. [Repository guide](repository.md), [physical validation history](testing.md) and [native-filename acceptance](native-filename-acceptance.md) cover package staging and runner execution. | A package success does not prove all later app behavior. Package authors own their install scripts. |
| Cache, source acquisition and offline readiness | Built. Version selection, integrity, reusable USB content, preflight and per-deployment reporting. Recorded online/offline and cold/warm scenarios in [testing](testing.md). | Legacy metadata recovery was merged in [PR #94](https://github.com/roryvossepoel/OSDStage/pull/94), tracked by [issue #92](https://github.com/roryvossepoel/OSDStage/issues/92). Both Windows CI hosts passed on `71ae31f49cfb6f16e93f8ec61454a57120cca5f2`. **Operator-confirmed, 30 October:** the production Sync helper refreshed an isolated Chrome cache with the three legacy metadata fields removed; hash/size validation and Google signature validation passed, and original cache hashes remained unchanged. This is a full-Windows helper test, not a physical public-wrapper, WinPE or PreInstall run. The fix is included in this baseline; the physical acceptance limits remain unchanged. Offline readiness still requires verified content. |
| Built-in-only / repository-only selection | Built in [PR #80](https://github.com/roryvossepoel/OSDStage/pull/80). Session options control deployment/discovery; both disabled is refused. The [RC4 Gallery runs](rc4-gallery-acceptance.md) used built-ins with repository integration disabled; the repository-only path is recorded in the 31 October acceptance below. Sync remains available for preparation. | Physical results cover those selected source combinations. The both-disabled refusal remains automated coverage. |
| Ordered runtime, fault isolation, logs and cleanup | Built. [Runtime guide](runtime.md) and [testing history](testing.md) describe one-shot execution and retained failure evidence. The 31 October acceptance below records operator-confirmed OnSuccess staging removal; both RC4 Gallery runs record OnSuccess cleanup scheduling. | Scheduling alone does not prove removal. Continuation to Windows Update after failed or skipped packages has automated coverage; the two successful Gallery runs do not exercise those failure paths. |
| Windows Update: `Add-OSDStageWindowsUpdate` | Included in RC3 and RC4. One optional pass runs last in SetupComplete, with opt-in drivers/firmware and no automatic restart. The [RC4 Gallery runs](rc4-gallery-acceptance.md) installed 36/36 offers on Dell and 4/4 on Surface; [contract and earlier evidence](windows-update.md). | Monthly cumulative Windows/.NET field coverage remains open. A successful pass does not mean no updates remain after a restart or later scan. |
| Delivery reports | Included in RC4. Standalone JSON/HTML reports correlate package and component results; [broad report acceptance](delivery-report.md#broad-component-acceptance-3-november-2026) and [published Gallery acceptance](rc4-gallery-acceptance.md) record matching evidence and report checks. | Reports describe execution and follow-up requirements; they do not certify hardware health, complete patching or Autopilot enrollment. |
| Inspection and diagnostics | Built. Read-only Viewer, cache health, deployment-result inspection and [maintenance diagnostics](maintenance.md). | Interactive selection/configuration expansion remains deferred; [draft PR #39](https://github.com/roryvossepoel/OSDStage/pull/39) is separate from the delivered read-only Viewer. |

### Vendor built-ins

The existing set is Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified,
Google Chrome Enterprise, Mozilla Firefox Enterprise, Cisco Webex, Zoom
Workplace, 7Zip, Visual Studio Code, Visual C++ redistributables, .NET runtimes,
Microsoft Company Portal and CMTrace Open. See [per-app contracts](built-in-apps.md),
[metadata](../metadata/builtins.json) and [version-specific test evidence](testing.md).

Keep these integrations in scope. Historical successful deployments do not
validate every architecture, product version, channel, licensing choice or
interactive workflow. In particular, interface support for ARM64/x86 is not a
physical acceptance result. No additional vendor integration is selected by
this register.

## Machine configuration and repository data

All rows below are implemented in the baseline. The public command and linked
guide define the supported parameters; this table records the practical state.

| Feature / interface | Defined scope | Practical evidence and next decision |
| --- | --- | --- |
| Registry: `Add-OSDStageRegistryKey`, `Add-OSDStageRegistryValue` | Keys and typed values; explicit 32/64-bit or process-default view. [Contract](registry-staging.md). | **Recorded pass:** nine operations and independent read-back on x64, documented in the [candidate evidence](release-candidate-0.52.0.md). Other roots/architectures are not implied. |
| Optional features: `Add-OSDStageWindowsFeature` | Enable/disable Windows feature names once with NoRestart. No source-media management. [PR #81](https://github.com/roryvossepoel/OSDStage/pull/81), [runtime](../Runtime/Invoke-OSDStageWindowsFeatures.ps1). | **Operator-confirmed workflow:** on 31 October the maintainer confirmed the earlier practical tests had already been completed. TelnetClient enable and WorkFolders-Client disable were the selected pair; the new combined run now records actual Disabled-to-Enabled and Enabled-to-Disabled transitions respectively. See the 31 October acceptance update below. FOD capabilities use the separate command below. |
| Fonts: `Add-OSDStageFont -Id` | Repository Font package, machine-wide TTF/OTF; no TTC. No overwrite on conflicting font content. | **Recorded pass:** seven fonts installed/registered and natively loaded in [PR #82](https://github.com/roryvossepoel/OSDStage/pull/82). Separate ARM64, repeat/conflict and user-app rendering tests are not established. |
| Certificates: `Add-OSDStageCertificate` | Repository Id or local file; public CA certificates into LocalMachine Root or CA only. No private keys/PFX/user stores. [Contract](certificate-staging.md). | **Recorded pass:** local-file and repository-package Root import in [PR #85](https://github.com/roryvossepoel/OSDStage/pull/85). Native automated CA-store coverage exists; separate physical intermediate-CA scenario remains unrecorded. |
| Drivers: `Add-OSDStageDriver -Id` | Repository Driver package; full vendor tree; SetupComplete adds INFs to the Driver Store and requests matching-device installation. No boot-driver injection. [Contract](driver-packages.md). | **Operator-confirmed:** Realtek drivers were present in the Driver Store; maintainer accepted that outcome. Actual selection/binding and device function are not claimed. Implementation and CI: [PR #86](https://github.com/roryvossepoel/OSDStage/pull/86). |
| Wi-Fi: `Add-OSDStageWiFiProfile` | WLAN XML or parameters; WPA2-Personal, WPA3-Personal and Open. No EAP/Enterprise. All-user profile import, no explicit connect. [Contract](wifi-staging.md). | **Recorded pass:** XML input accepted on one adapter in [PR #84](https://github.com/roryvossepoel/OSDStage/pull/84). Parameter-generated input has automated coverage but no separate physical pass recorded there. Neither import nor merge proves connectivity. |
| Machine variables: `Add-OSDStageEnvironmentVariable` | Set/remove literal or expandable machine values; append PATH without new lexical duplicates. Existing processes are not refreshed. [Contract](environment-variables.md). | **Operator-confirmed workflow:** maintainer reconfirmed completion of earlier practical tests on 31 October. The new combined run records four actual changes: literal and expandable values, one PATH append and removal of the seeded variable. Earlier confirmation remains valid; see the acceptance update below. |
| Services: `Add-OSDStageService` | Exact existing service name; startup mode and running/stopped state; bounded wait in the same run. No credentials, dependency edits or recurring enforcement. [Contract](services.md). | **Operator-confirmed workflow:** same combined run as variables, reconfirmed by the maintainer on 31 October. The new combined run records WSearch changing from Running/AutomaticDelayedStart to Stopped/Manual; Spooler was already Running/Automatic. Native automated disposable-service coverage remains separate evidence. |
| Inbox app removal: `Add-OSDStageWindowsInboxCleanup` | Explicit selection or Tested13 preset, optional diagnosis. [Built-in guide](built-in-apps.md). | **Recorded pass:** 13 selected packages removed and reported absent after Autopilot; separate three-package run also recorded in [testing](testing.md). No blanket claim for every inbox package/build. |
| Windows capabilities: `Add-OSDStageWindowsCapability` | Explicit Add/Remove by full capability identity; Windows 11 client 25H2+ at runtime; online servicing sources under existing policy. No custom source/repository integration, reboot or follow-up correction. [Contract](windows-capabilities.md). | **Log-backed, 30 October:** actual XPS `NotPresent` to `Installed` and OpenSSH Client `Installed` to `NotPresent`; both exit 0, no restart required/requested. One successful SetupComplete Script, zero failures, 328.2 seconds; independent OOBE query confirms final states. DISM target is build **26300.9711 x64**, not a separate build-26200/25H2 test. [Evidence and limits](windows-capabilities.md#physical-acceptance-on-30-october-2026). **Recorded pass, 3 November:** published Gallery RC4 installed XPS Viewer from `NotPresent` to `Installed` on both Dell and Surface with exit 0 and no restart requested; see [RC4 acceptance](rc4-gallery-acceptance.md). These passes do not diagnose or establish a fix for the earlier Surface `0x800f0831` failure. ARM64 and other capabilities remain unvalidated in practice. |
| Initial file/protocol associations: `Add-OSDStageDefaultAssociation` | Explicit identifier/ProgId/app-name parameters or XML input. Install apps first, then select associations; installing an app does not implicitly select it. One-shot DISM baseline export/merge/import during SetupComplete; user-editable initial defaults, no enforcement. [Contract](default-associations.md), [PR #91](https://github.com/roryvossepoel/OSDStage/pull/91). | **Operator-confirmed on PC1, 30 October:** corrected test revision `2b9dfd303c186302414d52b94f306215883904d4` opens `.pdf` in Adobe Acrobat and HTTP/HTTPS in Chrome. Changing PDF and both protocol defaults through Windows Settings also worked. No new runtime logs were supplied for this run. Separate HTML opening, XML-input deployment and ARM64 are not physically confirmed. |
| Start pins: `Add-OSDStageStartPins` | Supplied ordered pin list or JSON; applyOnce; supported Windows build/ADMX required. [Contract](desktop-settings.md). | **Operator-confirmed:** Edge/Explorer/Settings pins correct. Continued user editability not separately confirmed. |
| Taskbar pins: `Add-OSDStageTaskbarPins` | Native persistent layout policy with Replace and PinGeneration; supplied ordered list. [Contract](desktop-settings.md). | **Operator-confirmed with accepted limit:** Settings/Explorer appeared, with extra Outlook. Maintainer accepted this result; Outlook's source is unproven. Do not promise exact exclusion of all additional pins. Continued user editability remains unconfirmed. |

### Wi-Fi credential acceptance

Keep the existing [credential-handling limits](wifi-staging.md#credential-handling)
explicit. OSDStage logs/results must omit passwords and profile XML. After one
runtime attempt the credential-bearing staging config must be removed, including
on failure and with CleanupMode Never. The XML-input test reports successful
cleanup without a separate disk inventory; do not label complete on-disk absence
as independently verified. Early interruption before the runtime can leave
restricted staging behind. Caller scripts/original exports are outside automatic
cleanup, and the installed Windows WLAN profile necessarily remains.

## Files and directories accepted — 1 November 2026

Files and directories passed physical testing after the RC1 acceptance run. `Add-OSDStageDirectory` and `Add-OSDStageFile` stage ordered
create/copy/remove operations with separate Force and Recurse options. See the
[contract and test example](file-system.md). All nine SetupComplete operations
succeeded, and all five independent content/removal checks passed. The published
RC1 module is unchanged; these commands are included in RC2.

## Feature-scope closeout — 31 October 2026

No additional feature candidate remains selected for investigation in this
register. Language packs are excluded by maintainer decision after a successful
standalone experiment; see [the evaluation record](language-evaluation.md).
Existing Windows capabilities (FoDs) remain in scope. This is a scope decision,
not a claim that every implemented variant has passed physical acceptance or
that a Gallery release is ready.

### Physical acceptance update

The selected combined and repository-only execution scenarios passed on
31 October. The detailed sanitized record is in
[PR #97](https://github.com/roryvossepoel/OSDStage/pull/97), in
`docs/combined-acceptance.md` under "Recorded acceptance on 31 October 2026".
The maintainer supplied the matching runtime/feature results and confirmed that
`C:\Windows\Temp\OSDStage` was absent after each run. Raw private logs and Wi-Fi
inputs are not committed to the repository.

| Scenario | Correlated evidence and result |
| --- | --- |
| Combined retained features | DeploymentId `ac04a216-0a5f-4cf7-b88d-c4ba93528f07`; selected module commit `9ad02052b4f721bd7ca8e70c8f422bd67b5fb1ee`; build 26300.9711 x64. All 16 entries succeeded, zero failures/skips, 553.6 seconds. Covers apps, Script, fonts, Root certificate, six driver INFs, registry, variables, services, optional features, capabilities, Wi-Fi XML import, pin preparation, inbox removal and initial association import. Acrobat returned successful code 3010; no claim that every installer needed no restart. |
| HTTP catalog to cache to SetupComplete | DeploymentId `41654f0d-451c-4444-8012-f6b2613f49ca`; same base test module with manifest-reader fix `c6f007436a2f20fe95bdf6b266931ea43637247d`. Four fresh repository IDs synchronized with Valid=True, all four staged ZIP hashes verified before execution, all four entries exited 0 in 16.3 seconds. Seven fonts installed, Root certificate imported, six INFs ready in Driver Store and one Wi-Fi profile imported through a Script package. |
| Runtime cleanup | CleanupMode OnSuccess for both runs. Logs show cleanup scheduling; the maintainer separately confirmed Test-Path returned False after each. Results remain available outside staging. |

The BOM-prefixed manifest defect discovered during the HTTP synchronization test
is addressed by [PR #98](https://github.com/roryvossepoel/OSDStage/pull/98). The
maintainer's successful four-package Sync and deployment validate that fix in
the tested path. The fix is included in the current baseline; physical evidence
and CI remain separate checks. These combined tests used the original
Stage/runtime path. The later Prepare-phase change for valid cached-only
packages has automated coverage and is not presented as part of those physical
runs.

Repository Wi-Fi in this test is a generic Script package, not a new native
package type or a repository-Id parameter on Add-OSDStageWiFiProfile. The selected
package intentionally carries the XML/key inside its ZIP. Its wrapper deletes
extracted XML and temporary config on normal completion/handled failure, and
fails if that cleanup fails. The supplied reports contain no password/profile
XML. The runtime staging directory was confirmed absent, but original exports,
repository/USB cache ZIPs and Windows' installed WLAN profile are outside that
cleanup claim.

These logs establish execution/configuration success, not additional proof of
rendered user pins, actual Wi-Fi connectivity, hardware binding or every parameter
set. Existing operator-confirmed PDF/protocol behavior and accepted extra Outlook
pin remain valid. Parameter-generated Wi-Fi and pin editability are still explicit
coverage limits, not reasons to repeat these completed installations.

## Excluded or deferred decisions

| Item | Decision |
| --- | --- |
| Language packs and multilingual OOBE preparation | Excluded on 31 October 2026. The standalone Dutch-image/English-language experiment passed after the update step was included, but language-media, build matching and cumulative/checkpoint update management are outside OSDStage. Select the base language in OSDCloud; prepare a multilingual WIM separately when needed, or add languages later in Windows. No language-installation cmdlet is introduced. [Evidence and limits](language-evaluation.md). |
| Wallpaper, lock screen, themes, colors and screensavers | Excluded from OSDStage. [PR #89](https://github.com/roryvossepoel/OSDStage/pull/89) closed without merge. Do not replace/delete Windows-owned images as a workaround. Start/taskbar pins remain in scope. |
| Regional settings | Dropped from the current feature scope; leave the normal OOBE/Autopilot choices to that flow. |
| Time zone | Dropped after the test still showed Western Europe instead of the requested Tokyo zone. No working time-zone feature is claimed. |
| Browser first-run experience | Dropped; handled through browser policy. |
| First-sign-in animation and support information | Not requested for this module. |
| Shortcut creation | Not selected. Pin configuration does not create missing shortcuts/apps. |
| Separate OneDrive per-machine integration | No new work selected. Revisit only after an explicit need and current installation behavior are established. |
| Interactive Viewer expansion | Deferred. The current Windows and web viewers remain read-only; the earlier [draft PR #39](https://github.com/roryvossepoel/OSDStage/pull/39) is not part of the accepted RC4 deployment path. Naming and public Pages delivery are complete, as recorded above. |

## Next closeout work

1. Preserve the published RC4 Gallery acceptance, broad 19-package report
   acceptance and earlier operator confirmations. No additional installation is
   required solely to repeat those completed scenarios.
2. Collect a targeted physical result for monthly cumulative Windows/.NET
   updates when offered, recording the actual installation and restart outcome.
   An offer set containing only other software and drivers does not establish
   that coverage.
3. Keep parameter-generated Wi-Fi and Start/taskbar editability marked as
   unconfirmed in practice, alongside the architecture and variant limits in
   this register. If separately selected, collect only the relevant observation;
   do not introduce a follow-up task or force a reboot.
4. The accepted legacy-cache helper test remains limited to the tested isolated
   full-Windows refresh. The accepted deployments used valid cache generations
   and do not broaden legacy-cache recovery evidence to new failure scenarios.
5. Make an explicit stable `1.0.0` release decision against this scope and its
   recorded limits, then follow the [release procedure](releasing.md). This
   documentation closeout does not publish or change RC4. Language packs,
   branding, regional settings and time zone remain outside scope.

For each accepted scenario record: feature, source commit, Windows build/edition
and architecture, input excluding secrets, expected change, observed change,
DeploymentId when available, result/log references and limits. Separate CI,
physical results and operator observations. Keep raw private logs outside the
public repository. Record an accepted limitation explicitly rather than turning
it into an unrequested workaround.

[Back to documentation](README.md)
