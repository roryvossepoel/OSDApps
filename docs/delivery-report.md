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
- Evidence checks for matching deployment identity, complete package results and matching Windows Update details.

The report uses an explicit field allowlist. Configuration values, installer command lines, raw diagnostic errors and source URLs are omitted. It retains `ErrorPresent` and failure codes; consult local runtime logs for detailed errors. Device and package names remain identifying information: review files before sharing them.

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
4. Open the HTML without network connectivity and inspect the summary, package table and expandable update details.
5. Keep the report together with the existing logs for review. A controlled failing package should produce a failed report; a report-generation failure must preserve the original runtime exit code.

Automated tests cover missing/duplicate results, stale update evidence, PreInstall failures, HTML escaping and output failures. Physical SetupComplete acceptance of the report remains separate from the RC3 Windows Update acceptance.

## Recorded acceptance: 3 November 2026

The first physical report test on a Surface Laptop Go 2 used commit `6367e048a1e1e3181d783295060daf14c879a536`. All three packages (7-Zip, FileSystem and Windows Update) succeeded. 7-Zip reused validated cache content; both file operations succeeded. Windows Update installed four of four offers (three software updates and one audio component driver), requested no restart and left the Windows release unchanged. Runner duration was 227.3 seconds; the Windows Update pass took 217.4 seconds.

The uploaded JSON, HTML and component results matched: all seven report checks passed, package/update fields agreed with their source reports, and HTML report/deployment identities matched JSON. No warnings or errors were recorded in the supplied runtime/update logs. `Attention` was caused solely by `FurtherScanRequired=True`, with no demonstrated remaining offers. The summary now names the actual follow-up reason instead of suggesting that evidence or a restart is necessarily missing.

The user confirmed that the initial HTML rendered well and requested closer alignment with the website. The revised presentation uses the website's inline mark, green gradient, typography, status card and full-width header/footer; it remains standalone and offline. The updated presentation still needs user visual review. Failed-run and reporting-failure cases remain covered by automated tests rather than this physical success run.
