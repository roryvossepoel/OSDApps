# Broad delivery-report acceptance test

Use a disposable x64 test PC, a volume labeled `OSDCloud`, network access and the
pinned delivery-report development module. RC3 alone does not contain the report.
This is a broad test of component types, not every available app or parameter.

Prepare a new test module with `tools/Prepare-OSDStageCombinedTest.ps1 -Revision <commit>`
on full Windows. It creates an isolated module directory on the USB; it does not
format the USB or modify the published repository. Keep the returned TestModules
path. After applying fresh Windows with OSDCloud, remain in WinPE and run
`tools/Invoke-OSDStageDeliveryReportTest.ps1` from that module directory. It rejects
existing staging and never requests a restart. Optional `-WindowsPath` identifies
the Windows installation explicitly when automatic detection is ambiguous.

The profile synchronizes the selected packages from the configured repository and
validates their cached hashes before staging. Existing valid payloads can be reused;
this does not rebuild or republish repository archives. The default catalog is
`https://msintune.blob.core.windows.net/osdstage/catalog.json`.

## Selections

- Built-in apps: 7-Zip, Microsoft 365 Apps (Monthly Enterprise, x64, Dutch), Adobe
  Acrobat Unified and Chrome. Chrome is used to test default browser associations.
- Repository: OmnissaHorizonClient, RepoTestFonts, RepoTestRootCA,
  RepoTestRealtekUSB and RepoTestWiFiProfile.
- Registry (both views), environment variables, services, Windows features and
  capabilities, Start/taskbar pins, inbox cleanup, default associations, files.
- Windows Update last, with all driver classes including firmware, a 60-minute
  timeout and no automatic restart. Updates are acquired through the configured
  Windows Update source and are not added to the OSDStage USB cache.

These are 19 manifest entries. The test changes WSearch to Manual/Stopped, keeps
Spooler Automatic/Running, enables Telnet Client, disables Work Folders Client,
adds XPS Viewer and removes OpenSSH Client. It removes Solitaire, Weather and News,
and sets initial PDF/browser associations. Use a test device. The certificate is
imported into LocalMachine Root. The Wi-Fi repository script applies the profile
already packaged by the repository owner; it remains a generic script result and
has no native per-profile delivery-report details. Do not publish its XML/ZIP or
share its credentials. Repository driver import alone does not prove device binding.

After the green READY line, manually restart into Windows. Keep power, USB and
network connected during SetupComplete. The module uses `CleanupMode Never` for
this test so staging and evidence remain available for investigation.

## After SetupComplete

From elevated PowerShell in OOBE or on the desktop, run
`tools/Test-OSDStageDeliveryReportResult.ps1` from the same USB module directory.
It compares the staging selection, runner result, JSON/HTML report identities,
evidence checks and Windows Update execution. It is read-only and never restarts.

Open `%ProgramData%\OSDStage\Results\DeliveryReport.html`. Confirm one Apps card
contains both Built-in apps and Repository apps, and configurations have separate
cards. Expand fonts/certificates/files and compare individual operations with the
original component JSON. Check font registration, the certificate thumbprint in
LocalMachine Root, installed apps, and the marker file on the actual PC. After
first sign-in check rendered pins, default associations and Wi-Fi connectivity.

`Attention` can be correct when a restart or follow-up scan is recorded. Restart
manually if required; a subsequent scan can find newly applicable updates. Do not
interpret one SetupComplete pass as proof that every future update is installed.
Retain DeliveryReport.json, DeliveryReport.html, Latest.json and the component
results/logs together. Review identifying data before sharing; do not upload the
entire retained staging directory, which can contain the Wi-Fi payload.
