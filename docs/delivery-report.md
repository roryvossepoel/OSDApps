# Delivery report

> Included in release candidate 1.0.0-rc4. See [release availability](release-status.md) for installation and publication links.

OSDStage writes `DeliveryReport.json` and `DeliveryReport.html` beside the configured runtime result file when execution finishes. The default folder is `%ProgramData%\OSDStage\Results`. `Latest.json` and the existing per-component reports remain unchanged.

Open `DeliveryReport.html` locally in a browser. It is a standalone, offline document: no scripts, remote fonts, analytics or external assets. Its Gallery, GitHub and documentation links only connect when you follow them. JSON is the structured source of the HTML, with the same `ReportId` in both files.

```powershell
$results = Join-Path $env:ProgramData 'OSDStage\Results'
Start-Process (Join-Path $results 'DeliveryReport.html')
$report = Get-Content (Join-Path $results 'DeliveryReport.json') -Raw | ConvertFrom-Json
$report | Format-List DeploymentId, Status, ExecutionStatus, RebootRequired
$report.Checks | Format-Table Name, Passed, Detail -Wrap
```

## What it records

- Deployment identity, execution phase, UTC timestamps and runner duration.
- HTML durations use minutes and seconds, rounded to the nearest whole second (for example, 2460.5 seconds becomes `41 min 01 sec`). JSON retains the numeric `DurationSeconds` values for analysis.
- Staging module version, device name, manufacturer, model and Windows version/build when available.
- App and configuration results, versions, exit codes, durations and recorded acquisition/cache outcomes.
- Correlated Windows Update totals, individual selections and outcomes, restart requirements and follow-up scan indication.
- Evidence checks for matching deployment identity, complete package results and matching component/Windows Update details.
- Expandable component operations from the runtime reports, stored under `Packages[].Details` in JSON schema 1.1.

The report uses an explicit field allowlist. Registry and environment values, file contents, Wi-Fi credentials, installer command lines, raw diagnostic errors and source URLs are omitted. It retains `ErrorPresent` and failure codes; consult local runtime logs for detailed errors. Device/component names, certificate subjects and thumbprints, association identifiers and target paths remain identifying information: review files before sharing them.

## Component details

All apps are grouped in one **Apps** card, with separate **Built-in apps** and **Repository apps** sections based on the recorded `Source`. Empty sections are omitted; missing or unrecognized sources appear under **Apps with unknown source**. JSON retains the original `Source` value. Each configuration component has its own card with its execution result. Expand **Recorded component details** inside that card to see individual operations. Windows Update has its own card with expandable update details:

| Component | Recorded details |
| --- | --- |
| Fonts | Font file/registration name, installed, already present or failed outcome. |
| Certificates | Subject, thumbprint, LocalMachine store and import outcome. |
| Services | Requested startup/state settings and observed values before and after. |
| Files and directories | Target path, operation and result; no file contents or source credentials. |
| Registry | Key/value name, action, registry view and result; no value data. |
| Environment variables | Variable name, action, change outcome and appended entry count; no values. |
| Windows features/capabilities | Component, action, before/after state, outcome and restart indication. |
| Start/taskbar pins | Preparation outcome and pin count; not proof of the rendered user layout. |
| Default associations | Extension/protocol, ProgId and app with the recorded import outcome; current user defaults are not verified. |
| Wi-Fi profiles | Profile name and import outcome; connectivity is not verified. |
| Repository drivers | INF, Driver Store result and device-install outcome; import alone does not confirm active binding. |

Ordinary apps and custom script packages keep their package-level result unless OSDStage has a supported structured component report. The report never infers successful individual actions from requested configuration or an installer exit code alone.

Component details are read only from known sibling filenames. Deployment identity, package identity where available, schema, row count and package outcome must agree. The file must have been written between the runner's start and completion, which excludes older reports even when the deployment ID is reused. If evidence is missing, malformed, stale or inconsistent, the package result is preserved, its detail section says it is unavailable and the report requires attention. Skipped packages and terminal PreInstall failures do not import previous component details. Many existing component files do not have per-operation timestamps; correlation is execution-level, not a cryptographic audit trail.

## Reading the outcome

| Report status | Meaning |
| --- | --- |
| `Succeeded` | Recorded execution succeeded and the report's evidence checks passed, without a recorded restart or Windows Update follow-up requirement. |
| `Attention` | Review pending restart, skipped/missing results, unavailable metadata or follow-up update requirements. Execution can still have succeeded. |
| `Failed` | Deployment or a package reported a failure. |

`ExecutionStatus` preserves the runtime result. The report never changes package outcomes, the deployment exit code or cleanup policy. A reporting failure produces a warning; it does not fail an otherwise successful deployment. Report files are best effort if the result folder is not writable. A terminal PreInstall failure produces a failure report with installation entries marked `NotRun`, rather than presenting successful downloads as successful installations.

Missing values are `null` in JSON and shown as **Unknown** in HTML. Old Windows Update details are excluded unless deployment identity, phase, execution timestamps and package outcome match. The fixed sibling `WindowsUpdate-Result.json` is used; paths supplied by package content are not followed.

Each completed execution replaces the current report pair; these files are not a history archive. Copy both files elsewhere if you need to retain a run. Generation removes the previous pair first so a rendering failure cannot silently leave an older green report as the current output. A terminated process may not reach report generation: always check the deployment ID and timestamps against `Latest.json`.

## Limits and follow-up

This is an execution report, not a certification that the PC is fully patched, hardware is healthy or Autopilot enrollment succeeded. No extra Windows Update scan, installation, reboot or retry task is introduced. Windows Update runs once at the end of SetupComplete; later scans can reveal additional updates after drivers or Windows components become active. Update content is downloaded through the configured Windows Update infrastructure, not cached by OSDStage on USB.

Device collection is best effort. The first version does not inventory all installed drivers, validate firmware activation, run hardware health tests, or export CSV.

## Acceptance test

Use a test deployment containing an app, configuration and Windows Update. After SetupComplete:

1. Confirm both report files exist and share a report ID; compare their deployment ID with `Latest.json`.
2. Verify app/configuration results and Windows Update totals match the existing JSON files.
3. Confirm a successful run with `RebootRequired=True` displays **Attention**, while execution remains **Succeeded**.
4. Open the HTML without network connectivity and inspect the summary, individual package cards and expandable update details.
5. Include your test font/certificate packages and a service or file operation. Expand each component and compare the individual results with its original `*-Result.json`. Check the observed service state, font registration and certificate store on the PC. A package already present should retain that outcome.
6. Confirm `Packages[].Details.Evidence` is `Matched` for supported executed components; investigate any `ComponentEvidence:*` check that is false.
7. Keep the report together with the existing logs for review. A controlled failing package should produce a failed report; a report-generation failure must preserve the original runtime exit code.

Automated tests cover missing/duplicate results, stale update evidence, PreInstall failures, HTML escaping and output failures. Physical SetupComplete acceptance of the report remains separate from the RC3 Windows Update acceptance.

## Recorded acceptance: 3 November 2026

The first physical report test on a Surface Laptop Go 2 used commit `6367e048a1e1e3181d783295060daf14c879a536`. All three packages (7-Zip, FileSystem and Windows Update) succeeded. 7-Zip reused validated cache content; both file operations succeeded. Windows Update installed four of four offers (three software updates and one audio component driver), requested no restart and left the Windows release unchanged. Runner duration was 227.3 seconds; the Windows Update pass took 217.4 seconds.

The uploaded JSON, HTML and component results matched: all seven report checks passed, package/update fields agreed with their source reports, and HTML report/deployment identities matched JSON. No warnings or errors were recorded in the supplied runtime/update logs. `Attention` was caused solely by `FurtherScanRequired=True`, with no demonstrated remaining offers. The summary now names the actual follow-up reason instead of suggesting that evidence or a restart is necessarily missing.

The user confirmed that the initial HTML rendered well and requested closer alignment with the website. The revised presentation uses the website's inline mark, green gradient, typography, status card and full-width header/footer; it remains standalone and offline. The user approved the revised presentation. The later broad deployment below covers component-detail acceptance. Failed-run and reporting-failure cases remain covered by automated tests rather than this physical success run.

## Broad component acceptance: 3 November 2026

The accepted source was `1f927fa7d868179ba64ba66553e8b618eae8b460` (merged through [PR #121](https://github.com/roryvossepoel/OSDStage/pull/121)). A Dell Pro Micro QCM1250 running Windows 11 26H2 build 26300.9711 completed the [19-package test](delivery-report-full-test.md) during SetupComplete:

- All 19 packages succeeded, with no failed or skipped packages. Runner duration was 1082.5 seconds, displayed as **18 min 03 sec**.
- All 18 report checks passed. JSON/HTML identities and package/update fields matched the original runtime reports; all 11 supported component evidence groups were `Matched`.
- All four built-in apps reused validated cache content. The Apps card correctly separated those apps from the repository app.
- Fonts, certificates, repository INF drivers, registry, environment, services, features, capabilities, desktop settings, associations and file operations supplied matching component evidence. XPS Viewer installed and OpenSSH Client was removed successfully on this device.
- Windows Update ran last: 36/36 offers installed (3 software updates and 33 drivers/firmware), each with result code 2 and HRESULT 0. It required a later restart, requested none, was not blocked by a reboot prerequisite and left the Windows release unchanged. `Attention` correctly reflected restart/follow-up requirements.
- The user confirmed manual checks after restart and sign-in. No warnings or errors appeared in the supplied runtime/update logs. Raw device reports and configuration payloads are not committed to the repository.

[CI on the accepted source](https://github.com/roryvossepoel/OSDStage/actions/runs/41658686621) passed on Windows PowerShell 5.1 and PowerShell 7, including continuation to Windows Update after a failed or skipped package. Failed-run and reporting-failure paths remain automated coverage rather than a claim about this successful physical run.

An earlier Surface Laptop Go 2 run failed while servicing XPS Viewer with `0x800f0831`; a later manual OOBE installation succeeded. That observation does not establish that XPS Viewer is unavailable on 26H2, nor does this Dell success resolve the earlier servicing failure. RC4 does not add a speculative retry or exclude XPS Viewer by release. Monthly cumulative Windows/.NET updates were not offered. The later published-package acceptance is recorded below.

## Published Gallery RC4 acceptance: 3 November 2026

The [RC4 Gallery acceptance record](rc4-gallery-acceptance.md) adds two physical
three-entry deployments on Dell Pro Micro QCM1250 and Surface Laptop Go 2. Both
completed 7-Zip, XPS Viewer and Windows Update successfully; all eight report
checks passed on each device, and the JSON/HTML identities and results matched
the underlying execution evidence. XPS changed from `NotPresent` to `Installed`
on both; the earlier Surface failure did not recur in this run.

Both reports correctly display `Attention` with `ExecutionStatus=Succeeded`.
The Dell requires a restart and follow-up scan; the Surface recommends a
follow-up scan without a recorded restart requirement. The maintainer separately
confirmed normal OOBE and first sign-in on both devices, with Autopilot/Intune
proceeding normally where applicable. This confirmation does not extend the
report's scope into an enrollment audit or a guarantee of complete patch coverage.
