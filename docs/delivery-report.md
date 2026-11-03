# Delivery report

> Development feature: available in the delivery-report branch, not in the published RC3 package.

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
- Staging module version, device name, manufacturer, model and Windows version/build when available.
- App and configuration results, versions, exit codes, durations and recorded acquisition/cache outcomes.
- Correlated Windows Update totals, individual selections and outcomes, restart requirements and follow-up scan indication.
- Evidence checks for matching deployment identity, complete package results and matching component/Windows Update details.
- Expandable component operations from the runtime reports, stored under `Packages[].Details` in JSON schema 1.1.

The report uses an explicit field allowlist. Registry and environment values, file contents, Wi-Fi credentials, installer command lines, raw diagnostic errors and source URLs are omitted. It retains `ErrorPresent` and failure codes; consult local runtime logs for detailed errors. Device/component names, certificate subjects and thumbprints, association identifiers and target paths remain identifying information: review files before sharing them.

## Component details

All applications are grouped in one **Apps** card. Each configuration component has its own card with its execution result. Expand **Recorded component details** inside that card to see individual operations. Windows Update has its own card with expandable update details:

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
| Default associations | Extension/protocol, ProgId and application with the recorded import outcome; current user defaults are not verified. |
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

The user confirmed that the initial HTML rendered well and requested closer alignment with the website. The revised presentation uses the website's inline mark, green gradient, typography, status card and full-width header/footer; it remains standalone and offline. The user approved the revised presentation. Component-detail acceptance on a physical deployment remains pending. Failed-run and reporting-failure cases remain covered by automated tests rather than this physical success run.
