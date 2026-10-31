# Feature scope and validation register

Decision snapshot: 31 October 2026. Implementation baseline: main at
`f2073b2665ca2d8b2f19c83cc5e347cabdc895a1` (includes merged PRs #94 and #95).

This register separates implemented behavior, practical evidence and decisions
still to be made. It is not a release announcement or approval to build every
candidate. The module manifest at this baseline is 0.51.0; merged features are
not automatically available in the published Gallery package. Identify test
modules by commit, not by the manifest version alone.

## Agreed order

1. Establish technical module stability, run the selected combined acceptance
   profile and record contracts, limits and results. Viewer, Pages and renaming
   must wait for technical acceptance.
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
| Cache, source acquisition and offline readiness | Built. Version selection, integrity, reusable USB content, preflight and per-deployment reporting. Recorded online/offline and cold/warm scenarios in [testing](testing.md). | Legacy metadata recovery was merged in [PR #94](https://github.com/roryvossepoel/OSDApps/pull/94), tracked by [issue #92](https://github.com/roryvossepoel/OSDApps/issues/92). Both Windows CI hosts passed on `71ae31f49cfb6f16e93f8ec61454a57120cca5f2`. **Operator-confirmed, 30 October:** the production Sync helper refreshed an isolated Chrome cache with the three legacy metadata fields removed; hash/size validation and Google signature validation passed, and original cache hashes remained unchanged. This is a full-Windows helper test, not a physical public-wrapper, WinPE or PreInstall run. The fix is included in this baseline; the physical acceptance limits remain unchanged. Offline readiness still requires verified content. |
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
| Optional features: `Add-OSDAppWindowsFeature` | Enable/disable Windows feature names once with NoRestart. No source-media management. [PR #81](https://github.com/roryvossepoel/OSDApps/pull/81), [runtime](../Runtime/Invoke-OSDAppWindowsFeatures.ps1). | **Operator-confirmed workflow:** on 31 October the maintainer confirmed the earlier practical tests had already been completed. TelnetClient enable and WorkFolders-Client disable were the selected pair; the new combined run now records actual Disabled-to-Enabled and Enabled-to-Disabled transitions respectively. See the 31 October acceptance update below. FOD capabilities use the separate command below. |
| Fonts: `Add-OSDAppFont -Id` | Repository Font package, machine-wide TTF/OTF; no TTC. No overwrite on conflicting font content. | **Recorded pass:** seven fonts installed/registered and natively loaded in [PR #82](https://github.com/roryvossepoel/OSDApps/pull/82). Separate ARM64, repeat/conflict and user-app rendering tests are not established. |
| Certificates: `Add-OSDAppCertificate` | Repository Id or local file; public CA certificates into LocalMachine Root or CA only. No private keys/PFX/user stores. [Contract](certificate-staging.md). | **Recorded pass:** local-file and repository-package Root import in [PR #85](https://github.com/roryvossepoel/OSDApps/pull/85). Native automated CA-store coverage exists; separate physical intermediate-CA scenario remains unrecorded. |
| Drivers: `Add-OSDAppDriver -Id` | Repository Driver package; full vendor tree; SetupComplete adds INFs to the Driver Store and requests matching-device installation. No boot-driver injection. [Contract](driver-packages.md). | **Operator-confirmed:** Realtek drivers were present in the Driver Store; maintainer accepted that outcome. Actual selection/binding and device function are not claimed. Implementation and CI: [PR #86](https://github.com/roryvossepoel/OSDApps/pull/86). |
| Wi-Fi: `Add-OSDAppWiFiProfile` | WLAN XML or parameters; WPA2-Personal, WPA3-Personal and Open. No EAP/Enterprise. All-user profile import, no explicit connect. [Contract](wifi-staging.md). | **Recorded pass:** XML input accepted on one adapter in [PR #84](https://github.com/roryvossepoel/OSDApps/pull/84). Parameter-generated input has automated coverage but no separate physical pass recorded there. Neither import nor merge proves connectivity. |
| Machine variables: `Add-OSDAppEnvironmentVariable` | Set/remove literal or expandable machine values; append PATH without new lexical duplicates. Existing processes are not refreshed. [Contract](environment-variables.md). | **Operator-confirmed workflow:** maintainer reconfirmed completion of earlier practical tests on 31 October. The new combined run records four actual changes: literal and expandable values, one PATH append and removal of the seeded variable. Earlier confirmation remains valid; see the acceptance update below. |
| Services: `Add-OSDAppService` | Exact existing service name; startup mode and running/stopped state; bounded wait in the same run. No credentials, dependency edits or recurring enforcement. [Contract](services.md). | **Operator-confirmed workflow:** same combined run as variables, reconfirmed by the maintainer on 31 October. The new combined run records WSearch changing from Running/AutomaticDelayedStart to Stopped/Manual; Spooler was already Running/Automatic. Native automated disposable-service coverage remains separate evidence. |
| Inbox app removal: `Add-OSDAppWindowsInboxCleanup` | Explicit selection or Tested13 preset, optional diagnosis. [Built-in guide](built-in-apps.md). | **Recorded pass:** 13 selected packages removed and reported absent after Autopilot; separate three-package run also recorded in [testing](testing.md). No blanket claim for every inbox package/build. |
| Windows capabilities: `Add-OSDAppWindowsCapability` | Explicit Add/Remove by full capability identity; Windows 11 client 25H2+ at runtime; online servicing sources under existing policy. No custom source/repository integration, reboot or follow-up correction. [Contract](windows-capabilities.md). | **Log-backed, 30 October:** actual XPS `NotPresent` to `Installed` and OpenSSH Client `Installed` to `NotPresent`; both exit 0, no restart required/requested. One successful SetupComplete Script, zero failures, 328.2 seconds; independent OOBE query confirms final states. DISM target is build **26300.9711 x64**, not a separate build-26200/25H2 test. [Evidence and limits](windows-capabilities.md#physical-acceptance-on-30-october-2026). ARM64 and other capabilities remain unvalidated in practice. |
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
[PR #97](https://github.com/roryvossepoel/OSDApps/pull/97), in
`docs/combined-acceptance.md` under "Recorded acceptance on 31 October 2026".
The maintainer supplied the matching runtime/feature results and confirmed that
`C:\Windows\Temp\OSDApps` was absent after each run. Raw private logs and Wi-Fi
inputs are not committed to the repository.

| Scenario | Correlated evidence and result |
| --- | --- |
| Combined retained features | DeploymentId `ac04a216-0a5f-4cf7-b88d-c4ba93528f07`; selected module commit `9ad02052b4f721bd7ca8e70c8f422bd67b5fb1ee`; build 26300.9711 x64. All 16 entries succeeded, zero failures/skips, 553.6 seconds. Covers apps, Script, fonts, Root certificate, six driver INFs, registry, variables, services, optional features, capabilities, Wi-Fi XML import, pin preparation, inbox removal and initial association import. Acrobat returned successful code 3010; no claim that every installer needed no restart. |
| HTTP catalog to cache to SetupComplete | DeploymentId `41654f0d-451c-4444-8012-f6b2613f49ca`; same base test module with manifest-reader fix `c6f007436a2f20fe95bdf6b266931ea43637247d`. Four fresh repository IDs synchronized with Valid=True, all four staged ZIP hashes verified before execution, all four entries exited 0 in 16.3 seconds. Seven fonts installed, Root certificate imported, six INFs ready in Driver Store and one Wi-Fi profile imported through a Script package. |
| Runtime cleanup | CleanupMode OnSuccess for both runs. Logs show cleanup scheduling; the maintainer separately confirmed Test-Path returned False after each. Results remain available outside staging. |

The BOM-prefixed manifest defect discovered during the HTTP synchronization test
is addressed by [PR #98](https://github.com/roryvossepoel/OSDApps/pull/98). The
maintainer's successful four-package Sync and deployment validate that fix in
the tested path; CI remains a separate requirement before merging.

Repository Wi-Fi in this test is a generic Script package, not a new native
package type or a repository-Id parameter on Add-OSDAppWiFiProfile. The selected
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
| Language packs and multilingual OOBE preparation | Excluded on 31 October 2026. The standalone Dutch-image/English-language experiment passed after the update step was included, but language-media, build matching and cumulative/checkpoint update management are outside OSDApps. Select the base language in OSDCloud; prepare a multilingual WIM separately when needed, or add languages later in Windows. No language-installation cmdlet is introduced. [Evidence and limits](language-evaluation.md). |
| Wallpaper, lock screen, themes, colors and screensavers | Excluded from OSDApps. [PR #89](https://github.com/roryvossepoel/OSDApps/pull/89) closed without merge. Do not replace/delete Windows-owned images as a workaround. Start/taskbar pins remain in scope. |
| Regional settings | Dropped from the current feature scope; leave the normal OOBE/Autopilot choices to that flow. |
| Time zone | Dropped after the test still showed Western Europe instead of the requested Tokyo zone. No working time-zone feature is claimed. |
| Browser first-run experience | Dropped; handled through browser policy. |
| First-sign-in animation and support information | Not requested for this module. |
| Shortcut creation | Not selected. Pin configuration does not create missing shortcuts/apps. |
| Separate OneDrive per-machine integration | No new work selected. Revisit only after an explicit need and current installation behavior are established. |
| Viewer expansion, GitHub Pages and naming | Deferred until feature scope and acceptance are settled; follow the agreed order above. |

## Next closeout work

1. Preserve both accepted execution runs and the earlier operator confirmations.
   No additional installation is required for the two completed scenarios.
2. Complete review and CI of the manifest-reader fix, combined acceptance tooling
   and this scope register. The combined test used the original Stage/runtime
   path; the later Prepare-phase change for valid cached-only packages has
   automated coverage and is not misrepresented as part of that physical run.
3. Keep parameter-generated Wi-Fi and Start/taskbar editability marked as
   unconfirmed in practice. If separately selected, collect only the relevant
   observation; do not introduce a follow-up task or force a reboot.
4. The accepted legacy-cache helper test remains limited to the tested isolated
   full-Windows refresh. The new runs used valid cache generations and do not
   broaden legacy-cache recovery evidence to new failure scenarios.
5. After technical review/CI closeout, decide naming, then finish Viewer and public
   Pages documentation. Language packs, branding, regional settings and time zone
   remain outside scope.

For each accepted scenario record: feature, source commit, Windows build/edition
and architecture, input excluding secrets, expected change, observed change,
DeploymentId when available, result/log references and limits. Separate CI,
physical results and operator observations. Keep raw private logs outside the
public repository. Record an accepted limitation explicitly rather than turning
it into an unrequested workaround.

[Back to documentation](README.md)
