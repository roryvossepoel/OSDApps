# All-app cold deployment validation

**Historical procedure for OSDStage 0.45.0.** This is not a current-release regression test or a required step after every update. Its [recorded successful cold run](testing.md#nine-app-cold-deployment--19-october-2026) is separate from the procedure. For current deployment instructions, use the [online WinPE example](../Examples/WinPE-Online.md); for inspections, use [Choose the right check](maintenance.md#choose-the-right-check).

This operator test uses the published OSDStage **0.45.0** module from PowerShell
Gallery. Download
[`Test-OSDStageAllApps.ps1`](../tools/Test-OSDStageAllApps.ps1) to the USB flash drive.
It does not use the source module alongside the test script.

## Scope and preparation

Use a fresh x64 Windows deployment after OSDCloud, while still in x64 WinPE.
Do not stage other apps beforehand or run another cache operation concurrently.
One attached volume must have label `OSDCloud`, with at least 15 GB free; the
Windows volume must have at least 25 GB free before staging. These conservative
test thresholds are not a guarantee of capacity for future package versions.

The test first loads the exact Gallery version and checks repository availability.
It then renames the existing `OSDStage` directory to a unique
`OSDStage-Backup-<timestamp>-<guid>` sibling directory and creates an empty cache.
The old cache is not deleted or automatically restored. A failure preserves the
backup and diagnostic staging; do not rerun the entire staging script on that
partially prepared deployment.

| Source | Apps / configuration |
| --- | --- |
| Built-in | Microsoft 365 Apps: MonthlyEnterprise, nl-nl, x64, default O365ProPlusRetail product |
| Built-in | Microsoft Teams, Google Chrome Enterprise, Cisco Webex, Adobe Acrobat Unified: x64 defaults |
| Built-in | Mozilla Firefox Enterprise: Rapid, en-US, x64 |
| Built-in | Zoom Workplace: x64, no desktop shortcut, DisableZoomOnboarding enabled |
| Repository | NotepadPlusPlus and OmnissaHorizonClient; supply a catalog with compatible x64 or any packages |

Repository packages are downloaded during WinPE staging. The seven built-ins
are acquired in Windows before their installers run. App-specific
production configuration and a script package are outside this test.

## Stage and reboot

In WinPE PowerShell, use your actual repository URL:

```powershell
.\Test-OSDStageAllApps.ps1 -Phase Stage -CatalogUri 'https://example.org/osdstage/catalog.json'
```

Only after `ALL APPS COLD STAGING PASSED - READY FOR REBOOT!`, run:

```powershell
wpeutil reboot
```

Keep the USB flash drive connected and networking available until OOBE appears.
The test copies itself and a deployment-ID record to the Windows disk before
reboot. The USB module directories are not updated by this test.

## Validate at OOBE

Open a command prompt with Shift+F10:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\OSDStage\Tests\Test-OSDStageAllApps.ps1 -Phase Validate
```

The read-only checker prints acquisition and installer results, then requires
matching deployment IDs, exactly seven successful built-in preparations with
`Downloaded` and no refresh errors, exactly nine successful runner entries, no
failed/skipped apps, and completed staging/helper cleanup. Cached
fallback may permit an installation to succeed, but cannot pass this cold test.

This checks the module's recorded installation results and cleanup. It does not
launch all nine apps, prove first-user behavior, compare every installed
version with its source, or perform a complete post-installation USB cache health
check. Preserve the old cache until the new cache has also been reviewed. Share
the two result tables and final summary; never rerun SetupComplete manually.
