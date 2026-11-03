# Releasing OSDStage

[Documentation](README.md) · [Getting started](getting-started.md) · [Release availability](release-status.md)

OSDStage uses GitHub Actions for validation and PowerShell Gallery publishing.

## Public descriptions

The module description and Gallery tags live in `OSDStage.psd1`. Align their wording with the README when preparing the next module release. Updates reach the Gallery with that new version; an existing release is not republished in place. Documentation can be merged without publishing. The release workflow is manual-only; changing the manifest or merging a PR does not start a release.

Use this concise description for the GitHub repository's **About** field:

> Stage software and device configuration before OOBE, with built-in integrations, repository packages and optional OSDCloud USB caching.

Keep the README focused on the first successful deployment. Use version-independent installation commands there; retain exact versions in release notes and test evidence. The Downloads badge uses Shields.io to sum Gallery-reported per-version downloads directly, without a workflow or separate branch. It shows `unavailable` rather than an incomplete total when the feed is paginated. See [badge maintenance](../CONTRIBUTING.md#gallery-download-badge).

## Continuous integration

CI runs on pushes to `main`, pull requests and manual dispatch. Additions/modifications confined to `metadata/icons/*.svg` validate the icons and skip the two PowerShell suites. Mixed changes, deletions, renames and manual runs take the full validation path. Full validation covers:

- Module manifest, PSScriptAnalyzer and the complete Pester suite.
- Documentation syntax, local links and public command/parameter names.
- Distributable module build and packaged `Get-Help` in a fresh process.
- Example catalog metadata.

Both Windows PowerShell 5.1 and PowerShell 7 run independently. Their module artifacts are named `OSDStage-Windows-PowerShell-5.1` and `OSDStage-PowerShell-7`; validation reports are uploaded separately. These jobs do not run physical WinPE deployments.

## Required GitHub secret

PowerShell Gallery publishing uses the repository secret:

```text
PSGALLERY_API_KEY
```

The value must be a valid PowerShell Gallery API key with permission to publish the `OSDStage` package.

## Release process

The version in `OSDStage.psd1` and the corresponding top-level section in `CHANGELOG.md` are prepared in a pull request. The release workflow reads the changelog section and uses it for the GitHub Release notes.

1. Update `ModuleVersion`, optional `PrivateData.PSData.Prerelease`, `ReleaseNotes` and `CHANGELOG.md` together.
2. Run and review CI on the pull request.
3. Merge into `main` and verify its CI. This does not publish anything.
4. When publication is intended, manually dispatch **Create GitHub Release** from `main`, with `expected_version` matching the complete reviewed version, such as `1.0.0-rc1`.
5. The release workflow validates the current main commit, re-runs the test suite, and creates the immutable `v<version>` tag with version-specific release notes.
6. After successful release creation, the workflow automatically dispatches **Publish PowerShell Gallery**.
7. The publish workflow builds from the immutable tag, runs tests, publishes, downloads the Gallery package, and compares SHA256 hashes against all packaged release files.

Both workflows expose manual dispatch. Starting the release workflow can automatically dispatch Gallery publication after it creates a new release; it is not just a build-only check. A manually dispatched publish requires an already existing matching release tag. A Gallery version is immutable: never attempt to overwrite a published version. Pre-existing versions are treated as explicit conflicts, while a post-push 409 is reconciled only when the published files match the release.

### Preview and GA versions

For the first public candidate, the manifest contains `ModuleVersion = '1.0.0'`
and `PrivateData.PSData.Prerelease = 'rc1'`. The shared release-version resolver
produces `1.0.0-rc1` for the changelog section, `expected_version`, Gallery and
immutable tag `v1.0.0-rc1`. GitHub releases with a suffix are marked prerelease
and are not promoted to latest. Both release workflows remain manual-only.

Gallery discovery and download verification use `-AllowPrerelease` for a
candidate. PowerShellGet saves its module under the numeric `OSDStage/1.0.0`
folder; the verification compares every built file, including its manifest,
against that downloaded package. This checks the prerelease label as well as
the payload bytes. The read-only maintenance tool's Release mode currently
checks stable releases only; use the publish workflow's verification for RCs.

After a verified RC publication, test installation from Gallery in WinPE and
complete the normal deployment once. The [RC4 Gallery acceptance record](rc4-gallery-acceptance.md)
documents that path on two x64 devices and separates the maintainer's successful
OOBE/sign-in confirmation from the machine-readable execution evidence. Monthly
cumulative Windows/.NET servicing was not offered in those runs and remains an
explicit field-coverage item; record the decision on outstanding coverage before
preparing GA.

For GA, remove the `Prerelease` field,
prepare a `1.0.0` changelog section and release notes, then review and run the
same release procedure with `expected_version=1.0.0`. Do not move the RC tag or
republish it. Removing the suffix creates a separate stable Gallery version.

Publication is not triggered by merging this preparation. Before dispatch,
confirm main CI is green, the exact version/tag is unused and the repository's
`PSGALLERY_API_KEY` can publish OSDStage. Never put the key in code or logs.

### Gallery verification delays

After a push, Gallery search can expose the version before `Save-Module` can
retrieve it. The publish workflow therefore uses the exact-version download as
the readiness check. It tries up to 12 downloads, waits 10 seconds between
failed attempts, and starts each attempt in an empty verification directory.
The total duration also includes the individual Gallery request durations.

Only retrieval is retried; `Publish-Module` is called once. A downloaded package
with a missing file or a different SHA256 hash fails immediately. Exhausting the
download attempts leaves the workflow failed and explicitly unverified, even if
the push succeeded. No content mismatch is accepted as a propagation delay.

A failed verification does not prove that publication failed. Check whether the
exact version is available and compare it to the tagged build before taking
further action. Do not republish or retag an existing version; the pre-existing
version guard still rejects that operation. This workflow-only change does not
publish a new module version or alter an already completed workflow run.

No `main` push triggers release creation, including a manifest version change. Changes remain unpublished until the explicit release workflow is started. Before the first OSDStage release, check for an existing `v<version>` tag inherited from earlier development; tags must not be overwritten or moved.

## Release documentation checklist

- Update version, changelog, and manifest release notes before tagging
- Confirm release notes describe behavior changes and compatibility restrictions
- Confirm Pester and GitHub CI pass
- Verify GitHub Release notes and PowerShell Gallery publication
- Record published-package WinPE/SetupComplete acceptance, subsequent operator checks and remaining field-coverage limits
- Keep examples and public metadata aligned with the exported parameters
- Verify the public `metadata/builtins.json` (`SchemaVersion: 2`) has entries for new apps with correct exported commands, cache paths and public icons
- When a viewer reads the JSON from `main`, verify both JSON and icon assets after merge; do not break the schema without updating consumers
- Distinguish supported architectures from field-validated architectures

For a reusable read-only check of an existing release, use the [maintenance tool](maintenance.md#check-a-published-release). It reports workflow status and exact Gallery visibility without publishing or downloading packages.

## Local validation

The same validation used by CI can be run locally:

```powershell
./build/Test-Module.ps1
```

Requirements:

```powershell
Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

Build the distributable module without publishing it:

```powershell
./build/Build-Module.ps1
```

The default output is:

```text
dist/OSDStage
```

That directory is the exact module directory supplied to `Publish-Module`.

## Safety

The CI workflow never publishes a package.

The PowerShell Gallery API key is only exposed to the publish job through the GitHub Actions secret. Normal CI never has access to the Gallery publishing step.
