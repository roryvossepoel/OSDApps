# Contributing

Contributions, issue reports, and built-in app requests are welcome.

## Development and validation

Use a Windows development machine, not a device waiting to run SetupComplete. Clone the repository, use a separate branch and keep unrelated behavior changes in separate pull requests. Never commit private device logs, credentials, repository tokens or vendor installers.

The CI suite runs independently in **Windows PowerShell 5.1** and **PowerShell 7**. Both hosts run the complete Pester suite, analyzer, distribution build and a fresh-process check of actual packaged `Get-Help`. These Windows CI hosts are not WinPE; physical WinPE and installation regressions remain separate evidence.

Install the current CI test-framework version and analyzer in the host you intend to use:

```powershell
Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

From the repository root:

```powershell
./build/Test-Module.ps1 -ResultsPath ./TestResults
```

The build fails on analyzer errors, failed/discovery-failed/empty/incomplete Pester runs and missing or stale help metadata. Warnings are retained, not silently suppressed. `TestResults` includes NUnit-format Pester results, a complete analyzer JSON report and the exact tool versions. CI uploads reports even when a later check fails, and uploads module artifacts only after successful validation.

Run local documentation checks separately when editing Markdown:

```powershell
./build/Test-Documentation.ps1
```

This checks local inline-link targets and section anchors, parses fenced PowerShell and validates literal public OSDStage command/parameter names. It does not run examples or crawl external websites. A passing parser test does not establish that an example deployed software successfully.

## Command help

Edit reviewed descriptions and examples in `help/CommandHelp.psd1`. Build-generated MAML uses actual exported command parameter sets, types, defaults and validation choices. Do not execute commands to discover sample output.

Build and then open a fresh PowerShell session to inspect the **built** package:

```powershell
./build/Build-Module.ps1
```

In the new session, from the repository root:

```powershell
Import-Module ./dist/OSDStage/OSDStage.psd1 -Force
Get-Help Show-OSDStageUI -Full
Get-Help Add-OSDStage -Examples
./build/Test-PackagedHelp.ps1 -ModulePath ./dist/OSDStage
```

A raw source import does not generate the external help. Existing comment-based help is connected to MAML only in distribution copies, with executable-token equivalence checked. See [Maintaining command help](help/README.md) for the authoring contract and packaging boundary.

## Review boundaries

Describe behavior changes, execution environment, destructive effects and validation limits in every PR. Keep public parameter contracts, metadata consumers and standalone runtime requirements in mind. Do not call code safe merely because the analyzer is green; retain focused tests for failure paths. Do not fix a warning by weakening a security check or changing deployment defaults as a side effect of documentation work.

Normal CI never publishes to the Gallery. Version bumps and immutable release publication follow [Releasing](docs/releasing.md). Help and build improvements require a later approved module release before Gallery consumers receive them; merging the tooling PR alone does not replace a published package.

## Built-in app requests

Built-in apps are product-specific integrations maintained inside OSDStage. They are intentionally reserved for broadly used software with a stable, vendor-supported acquisition and unattended installation path. Built-in payloads must always be acquired directly from the software vendor; installers may never be bundled with, mirrored by, or redistributed through OSDStage.

Before requesting a built-in, review the [Built-in app request policy](docs/built-in-apps.md#requesting-a-new-built-in-app).

The installer source must be the vendor itself. Third-party mirrors, community package feeds, repackaged binaries, and module-hosted installer payloads are not accepted for built-ins.

A strong request includes:

```text
Product:
Vendor:
Vendor documentation:
Direct installer URL(s):
Architectures:
Silent install command:
Update/freshness mechanism:
Why this should be a generic built-in:
```

Do not request a built-in when acquiring the installer requires scraping, browser automation, traffic sniffing, temporary signed URLs, session cookies/tokens, or bypassing CDN/anti-bot controls.

For niche, customer-specific, internal, authenticated, or otherwise non-generic software, use the repository model instead.

## Gallery download badge

The README uses a standard Shields.io dynamic XML badge. It reads the public
PowerShell Gallery feed and sums `VersionDownloadCount` across the returned
OSDStage versions. The ordinary `/powershellgallery/dt/OSDStage` badge reads the
Gallery's aggregate `DownloadCount`, which currently reports zero incorrectly.

No GitHub Action, generated SVG or dedicated branch is required. Shields.io and
GitHub cache the image, so updates are not immediate. These are Gallery-reported
downloads, not unique users.

The badge shows `unavailable` if the feed has no version counters or contains a
pagination link, rather than presenting an incomplete total. Shields.io does not
follow Gallery pagination. If that limit is reached, review the badge source;
do not remove the guard and label a partial count as the total.
