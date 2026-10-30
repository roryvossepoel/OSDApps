# Feature scope and validation register

Decision snapshot: 30 October 2026. Implementation baseline: main at
`26deb9bd1e432cfc71fae848913adbe3d76e11a5` (includes PRs #91 and #93).

This register separates implemented behavior, practical evidence and decisions
still to be made. It is not a release announcement or approval to build every
candidate. The module manifest at this baseline is 0.51.0; merged features are
not automatically available in the published Gallery package. Identify test
modules by commit, not by the manifest version alone.

## Agreed order

1. Decide the feature scope, test the selected scenarios and record their
   contracts, limits and results here and in the detailed guides.
2. Decide whether to rename the project, including command names and migration
   impact, before finalizing the UI and public documentation.
3. Finish the Viewer against the agreed feature set.
4. Publish public documentation through GitHub Pages as part of that finalization.

Viewer development is deferred. [PR #39](https://github.com/roryvossepoel/OSDApps/pull/39)
is the existing selection/configuration preview, not a completed staging UI.
At this review it is draft, has merge conflicts and still needs manual WinPE
usability validation. GitHub Pages and renaming have no implementation decision
yet. Existing repository documentation continues to be maintained now.

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
| Cache, source acquisition and offline readiness | Built. Version selection, integrity, reusable USB content, preflight and per-deployment reporting. Recorded online/offline and cold/warm scenarios in [testing](testing.md). | Legacy metadata recovery is proposed in [PR #94](https://github.com/roryvossepoel/OSDApps/pull/94), tracked by [issue #92](https://github.com/roryvossepoel/OSDApps/issues/92). Both Windows CI hosts passed; a physical old-cache Sync test remains pending. The fix is not part of this baseline. Offline readiness still requires verified content. |
| Built-in-only / repository-only selection | Built in [PR #80](https://github.com/roryvossepoel/OSDApps/pull/80). Session options control deployment/discovery; both disabled is refused. Sync remains available for preparation. | Automated behavior coverage; no separate physical mode-isolation result recorded here. |
| Ordered runtime, fault isolation, logs and cleanup | Built. [Runtime guide](runtime.md) and [testing history](testing.md) describe one-shot execution, retained failure evidence and cleanup. | CleanupMode Never test runs do not prove OnSuccess cleanup. |
| Inspection and diagnostics | Built. Read-only Viewer, cache health, deployment-result inspection and [maintenance diagnostics](maintenance.md). | Interactive selection/configuration expansion remains deferred. |

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
| Registry: `Add-OSDAppRegistryKey`, `Add-OSDAppRegistryValue` | Keys and typed values; explicit 32/64-bit or process-default view. [Contract](registry-staging.md). | **Recorded pass:** nine operations and independent read-back on x64, documented in the [candidate evidence](release-candidate-0.52.0.md). Other roots/architectures are not implied. |
| Optional features: `Add-OSDAppWindowsFeature` | Enable/disable Windows feature names once with NoRestart. No source-media management. [PR #81](https://github.com/roryvossepoel/OSDApps/pull/81), [runtime](../Runtime/Invoke-OSDAppWindowsFeatures.ps1). | **Evidence pending:** TelnetClient enable and WorkFolders-Client disable were selected for testing, but no correlated practical result is recorded here. Retrieve that result or include this pair in the next test. FOD capabilities are a separate candidate below. |
| Fonts: `Add-OSDAppFont -Id` | Repository Font package, machine-wide TTF/OTF; no TTC. No overwrite on conflicting font content. | **Recorded pass:** seven fonts installed/registered and natively loaded in [PR #82](https://github.com/roryvossepoel/OSDApps/pull/82). Separate ARM64, repeat/conflict and user-app rendering tests are not established. |
| Certificates: `Add-OSDAppCertificate` | Repository Id or local file; public CA certificates into LocalMachine Root or CA only. No private keys/PFX/user stores. [Contract](certificate-staging.md). | **Recorded pass:** local-file and repository-package Root import in [PR #85](https://github.com/roryvossepoel/OSDApps/pull/85). Native automated CA-store coverage exists; separate physical intermediate-CA scenario remains unrecorded. |
| Drivers: `Add-OSDAppDriver -Id` | Repository Driver package; full vendor tree; SetupComplete adds INFs to the Driver Store and requests matching-device installation. No boot-driver injection. [Contract](driver-packages.md). | **Operator-confirmed:** Realtek drivers were present in the Driver Store; maintainer accepted that outcome. Actual selection/binding and device function are not claimed. Implementation and CI: [PR #86](https://github.com/roryvossepoel/OSDApps/pull/86). |
| Wi-Fi: `Add-OSDAppWiFiProfile` | WLAN XML or parameters; WPA2-Personal, WPA3-Personal and Open. No EAP/Enterprise. All-user profile import, no explicit connect. [Contract](wifi-staging.md). | **Recorded pass:** XML input accepted on one adapter in [PR #84](https://github.com/roryvossepoel/OSDApps/pull/84). Parameter-generated input has automated coverage but no separate physical pass recorded there. Neither import nor merge proves connectivity. |
| Machine variables: `Add-OSDAppEnvironmentVariable` | Set/remove literal or expandable machine values; append PATH without new lexical duplicates. Existing processes are not refreshed. [Contract](environment-variables.md). | **Evidence pending:** combined variables/services test was followed by a merge instruction, but exact settings and before/after outcomes are not recorded in [PR #87](https://github.com/roryvossepoel/OSDApps/pull/87). Recover results before retesting. |
| Services: `Add-OSDAppService` | Exact existing service name; startup mode and running/stopped state; bounded wait in the same run. No credentials, dependency edits or recurring enforcement. [Contract](services.md). | **Evidence pending:** same combined run as variables. Native automated disposable-service coverage exists; merge alone does not establish the physical result. |
| Inbox app removal: `Add-OSDAppWindowsInboxCleanup` | Explicit selection or Tested13 preset, optional diagnosis. [Built-in guide](built-in-apps.md). | **Recorded pass:** 13 selected packages removed and reported absent after Autopilot; separate three-package run also recorded in [testing](testing.md). No blanket claim for every inbox package/build. |
| Initial file/protocol associations: `Add-OSDAppDefaultAssociation` | Explicit identifier/ProgId/app-name parameters or XML input. Install apps first, then select associations; installing an app does not implicitly select it. One-shot DISM baseline export/merge/import during SetupComplete; user-editable initial defaults, no enforcement. [Contract](default-associations.md), [PR #91](https://github.com/roryvossepoel/OSDApps/pull/91). | **Operator-confirmed on PC1, 30 October:** corrected test revision `2b9dfd303c186302414d52b94f306215883904d4` opens `.pdf` in Adobe Acrobat and HTTP/HTTPS in Chrome. Changing PDF and both protocol defaults through Windows Settings also worked. No new runtime logs were supplied for this run. Separate HTML opening, XML-input deployment and ARM64 are not physically confirmed. |
| Start pins: `Add-OSDAppStartPins` | Supplied ordered pin list or JSON; applyOnce; supported Windows build/ADMX required. [Contract](desktop-settings.md). | **Operator-confirmed:** Edge/Explorer/Settings pins correct. Continued user editability not separately confirmed. |
| Taskbar pins: `Add-OSDAppTaskbarPins` | Native persistent layout policy with Replace and PinGeneration; supplied ordered list. [Contract](desktop-settings.md). | **Operator-confirmed with accepted limit:** Settings/Explorer appeared, with extra Outlook. Maintainer accepted this result; Outlook's source is unproven. Do not promise exact exclusion of all additional pins. Continued user editability remains unconfirmed. |

### Wi-Fi credential acceptance

Keep the existing [credential-handling limits](wifi-staging.md#credential-handling)
explicit. OSDApps logs/results must omit passwords and profile XML. After one
runtime attempt the credential-bearing staging config must be removed, including
on failure and with CleanupMode Never. The XML-input test reports successful
cleanup without a separate disk inventory; do not label complete on-disk absence
as independently verified. Early interruption before the runtime can leave
restricted staging behind. Caller scripts/original exports are outside automatic
cleanup, and the installed Windows WLAN profile necessarily remains.

## Candidates awaiting a scope decision

These are options, not approved feature work or promises of Windows support.
Research the selected option against current Microsoft guidance before design.

| Candidate | Decision needed before implementation | Suggested acceptance scenario |
| --- | --- | --- |
| Features on Demand | Add/remove capabilities; full capability identities; online source versus repository/offline media; build/language matching and restart reporting. | One supported add and one supported remove without a forced reboot or later correction. |
| Language packs | Whether this belongs in scope at all; pack/media source, build matching, dependencies and caching. Regional preferences are not implicitly included. | Install one matching language package and record servicing results; any language-selection behavior needs its own explicit contract. |

## Excluded or deferred decisions

| Item | Decision |
| --- | --- |
| Wallpaper, lock screen, themes, colors and screensavers | Excluded from OSDApps. [PR #89](https://github.com/roryvossepoel/OSDApps/pull/89) closed without merge. Do not replace/delete Windows-owned images as a workaround. Start/taskbar pins remain in scope. |
| Regional settings | Dropped from the current feature scope; leave the normal OOBE/Autopilot choices to that flow. |
| Time zone | Dropped after the test still showed Western Europe instead of the requested Tokyo zone. No working time-zone feature is claimed. |
| Browser first-run experience | Dropped; handled through browser policy. |
| First-sign-in animation and support information | Not requested for this module. |
| Shortcut creation | Not selected. Pin configuration does not create missing shortcuts/apps. |
| Separate OneDrive per-machine integration | No new work selected. Revisit only after an explicit need and current installation behavior are established. |
| Viewer expansion, GitHub Pages and naming | Deferred until feature scope and acceptance are settled; follow the agreed order above. |

## Next acceptance work

1. Recover the prior optional-feature and variables/services results where
   available. Record exact candidate revision, scenario and outcome; a missing
   record is not a reason to repeat all successful features.
2. If evidence is still missing, use one combined fresh-image test for the
   selected optional features, machine variables and services. Choose safe test
   values/services and record expected transitions before running it.
3. In a suitable WLAN-equipped test, cover the parameter-generated profile,
   secret-free reports and deletion of owned credential staging. Do not commit
   real credentials or profile exports. Connectivity is only a success criterion
   if explicitly selected and actually observed.
4. Capture Start/taskbar user editability during normal manual acceptance when
   those features are next exercised. Do not add a post-sign-in cleanup task.
5. Validate [PR #94](https://github.com/roryvossepoel/OSDApps/pull/94) on the
   full-Windows preparation PC with a preserved legacy cache: Sync should obtain
   and validate a replacement without manual cache deletion. This does not need
   another PC1 deployment. Automated staging and standalone PreInstall coverage
   are separate evidence; a Sync-only physical pass does not establish those paths.
6. Decide yes/no/defer for Features on Demand and language packs before building
   either. The accepted PDF/protocol scenario above does not need a repeat test
   solely to fill this register.

For each accepted scenario record: feature, source commit, Windows build/edition
and architecture, input excluding secrets, expected change, observed change,
DeploymentId when available, result/log references and limits. Separate CI,
physical results and operator observations. Keep raw private logs outside the
public repository. Record an accepted limitation explicitly rather than turning
it into an unrequested workaround.

[Back to documentation](README.md)
