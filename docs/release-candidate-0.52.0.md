# Candidate review and release handoff

## Status and scope

Review date: 25 October 2026. Proposed next version: **0.52.0**.
This document prepares release notes; it does **not** change ModuleVersion,
create a release tag, merge a PR or publish to the PowerShell Gallery.
The current candidate manifests still identify themselves as 0.51.0, so USB
test builds must be identified by their source commit and module directory.

The candidate consists of PR #72 (App/Apps and native vendor filenames) and
PR #73 (registry staging), with #73 based on #72. The verified implementation
heads are `e5641c5` and `3194fcc`, respectively. The latter already contains the
former. Documentation-only follow-up commits do not replace physical evidence
with a new claim that their exact build has been deployed.

## Prepared release notes

### Breaking contract

- Use App and Apps consistently for OSDApps-owned terminology and JSON fields.
  The catalog and deployment collection is `Apps`; PackageType is `App` or
  `Script`. Update external catalog producers, consumers and launcher checks
  to the new contract. Resetting a USB cache does not update an online catalog.
- Retain original vendor payload filenames through download, cache metadata,
  WinPE staging and SetupComplete execution. Record and validate the exact
  payload filename and hash; do not infer the installer by scanning extensions.
- Do not migrate or read obsolete generic-name vendor caches. Prepare a new
  cache with the new module. Caches already rebuilt and validated for this
  candidate do not need another reset.
- `Package.zip` remains the OSDApps-owned archive format for custom apps and
  scripts, including the generated RegistrySettings script. It is not a
  renamed vendor installer.

### Added

- `Add-OSDAppRegistryKey` stages a key-only operation without clearing values.
- `Add-OSDAppRegistryValue` stages a typed value and creates missing parent
  keys during execution. Supported types: String, ExpandString, MultiString,
  Binary, DWord and QWord.
- Optional mutually exclusive `-Registry32` and `-Registry64` select a view;
  neither switch uses the executing Windows process default. Record requested
  and resolved views and process bitness, and read back type and content.
- HKLM is supported; HKCR maps explicitly to machine HKLM\SOFTWARE\Classes;
  HKU requires a specified already-loaded hive. HKCU, HKCC, explicit
  WOW6432Node paths, ACL takeover, automatic profile loading and deletion
  operations are outside this feature.
- Reuse one local SHA-256-verified Script package and the existing runner.
  Registry staging needs no catalog, app-cache download or separate service.

### Fixed and validated

- Load prerequisite definitions before the standalone runner validates VC++
  and .NET payloads. Add regression tests in clean child processes so imported
  helpers cannot conceal missing startup dependencies.
- Validate original filenames, strict fresh-cache behavior and App/Script
  naming in the automated acceptance checks.

## Evidence and limits

| Evidence | Recorded result | Boundary |
| --- | --- | --- |
| CI #527, PR #72, `e5641c5` | Windows PowerShell 5.1 and PowerShell 7 jobs succeeded | Automated validation, not a new physical deployment |
| CI #528, PR #73, `3194fcc` | 569/569 tests per host; zero failures and zero skipped | Includes fresh 32-bit and 64-bit registry processes and real runner integration |
| Physical app deployment, 25 October | 14/14 succeeded; zero failed or skipped; VC++ x64 and .NET Desktop 10.0 x64 exit 0 | Cached content with network available; CleanupMode Never |
| Physical registry deployment, 25 October | One Script succeeded; nine of nine operations Created; independent read-back passed | Deep HKLM paths, Registry32, Registry64 and Default on x64 Windows |

The app deployment used the original PR #72 USB test candidate plus the verified
one-line prerequisite repair. The registry deployment used the `3194fcc` test
package. The two runs are separate: there is no physical 15-entry combined-run
claim. Native 32-bit Windows, ARM deployments, physically disconnected deployment
and every supported root are not established by these two acceptance runs.
CleanupMode Never intentionally retained staging; these runs do not establish
new evidence for OnSuccess cleanup or post-sign-in behavior for every app.

The registry feature's detailed evidence and usage are in
[registry staging](registry-staging.md).

## Known limitations retained for review

**Release blocker: issue #74.** Do not publish 0.52.0 until the current-deployment
reporting fix is validated on Windows PowerShell 5.1 and PowerShell 7 and merged.
The candidate fix records `PackageUpdated` in the current PreInstall phase and
copies flags only from the matching deployment and unique app record. It does
not use a previous cache-sync flag. Unknown/failed/non-applicable acquisition
remains null; a separate Teams bootstrapper download is not a primary MSIX update.
`CacheUsed` describes USB cache-root selection, not confirmed reuse. The original
14/14 and registry acceptance logs are historical evidence, not proof of this
reporting fix. See [runtime reporting](runtime.md#machine-readable-deployment-result)
for the precise field meanings. No new physical run is claimed here.

**Signature coverage:** successful cache/installer status is not proof that every
file was checked for a digital signature. The observed preparation run had ten
Valid signature entries and three Not assessed entries (7Zip, Adobe and Company
Portal). 7Zip uses upstream release SHA-256 validation; the outer Adobe ZIP and
the Company Portal bundle/dependency set are not fully assessed by that signature
inspector. Company Portal has file-hash checks. Office signature inspection covers
setup.exe, and Teams inspection covers teamsbootstrapper.exe rather than every
nested payload. Retain these distinctions; do not relabel Not assessed as Valid.
Teams may reuse its MSIX while downloading its bootstrapper separately.

See [runtime reporting](runtime.md) and the existing publisher policy in
[built-in apps](built-in-apps.md). Extending signature inspection is separate
work, not silently included in this release preparation.

## Merge and publication sequence

1. Review PR #73 and its final CI, then merge **#73 into the #72 feature branch**.
   Do not retarget #73 to main first. This consolidates the tested feature with
   its prerequisite changes without publishing a module.
2. Review the combined PR #72 CI, then merge **#72 into main**, still at 0.51.0.
   The release workflow checks for a version increase and skips publication
   when ModuleVersion has not increased, even if the manifest changed.
3. Prepare a separate reviewed release change that updates ModuleVersion,
   manifest ReleaseNotes and the matching top-level CHANGELOG section to the
   agreed next version. The prepared notes above are the starting point.
4. Only after explicit release approval merge the version-increase change.
   That main push triggers GitHub release creation and verified Gallery
   publication. Confirm the exact published package before enabling Gallery
   loading in the production launcher.

Steps above are a plan, not a record of merges or publication. Do not dispatch
release or publish workflows against a test branch. Do not overwrite immutable
release tags or existing Gallery packages. See [releasing](releasing.md).

## Maintainer action during review

Keep the successful USB module directories and existing app cache unchanged.
No repeat Windows installation, replacement test module or cache reset is
required for this documentation review. Do not enable Gallery loading expecting
these branch changes until the final published version has been verified.
