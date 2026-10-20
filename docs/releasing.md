# Releasing OSDApps

OSDApps uses GitHub Actions for validation and PowerShell Gallery publishing.

## Public descriptions

The module description and Gallery tags live in `OSDApps.psd1`. Align their wording with the README when preparing the next module release. Updates reach the Gallery with that new version; an existing release is not republished in place. Do not edit the manifest just to publish documentation: a manifest change on `main` triggers the release workflow.

Use this concise description for the GitHub repository's **About** field:

> Your apps. Ready before OOBE. Stage apps and PowerShell scripts in WinPE after OSDCloud applies Windows, using built-in integrations or your own repository and optional USB flash drive caching.

Keep the README focused on the first successful deployment. Use version-independent installation commands there; retain exact versions in release notes and test evidence. The Downloads badge uses Shields.io to sum Gallery-reported per-version downloads directly, without a workflow or separate branch. It shows `unavailable` rather than an incomplete total when the feed is paginated. See [badge maintenance](../CONTRIBUTING.md#gallery-download-badge).

## Continuous integration

Every push to `main`, pull request, or manually started CI run validates:

- Module manifest, PSScriptAnalyzer and the complete Pester suite.
- Documentation syntax, local links and public command/parameter names.
- Distributable module build and packaged `Get-Help` in a fresh process.
- Example catalog metadata.

Both Windows PowerShell 5.1 and PowerShell 7 run independently. Their module artifacts are named `OSDApps-Windows-PowerShell-5.1` and `OSDApps-PowerShell-7`; validation reports are uploaded separately. These jobs do not run physical WinPE deployments.

## Required GitHub secret

PowerShell Gallery publishing uses the repository secret:

```text
PSGALLERY_API_KEY
```

The value must be a valid PowerShell Gallery API key with permission to publish the `OSDApps` package.

## Release process

The version in `OSDApps.psd1` and the corresponding top-level section in `CHANGELOG.md` are prepared in a pull request. The release workflow reads the changelog section and uses it for the GitHub Release notes.

1. Update `ModuleVersion` and its `ReleaseNotes` field together with `CHANGELOG.md`.
2. Run and review CI on the pull request.
3. Merge into `main`. A change to `OSDApps.psd1` automatically starts **Create GitHub Release**.
4. The release workflow validates the current main commit, re-runs the test suite, and creates the immutable `v<version>` tag with version-specific release notes.
5. After successful release creation, the workflow automatically dispatches **Publish PowerShell Gallery**.
6. The publish workflow builds from the immutable tag, runs tests, publishes, downloads the Gallery package, and compares SHA256 hashes against all packaged release files.

Both workflows can also be dispatched manually when appropriate. A manually dispatched publish requires an already existing matching release tag. A Gallery version is immutable: never attempt to overwrite a published version. Pre-existing versions are treated as explicit conflicts, while a post-push 409 is reconciled only when the published files match the release.

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

A normal `main` push without an `OSDApps.psd1` change does not trigger a new release. Documentation-only or unreleased fixes remain pending until a later version bump.

## Release documentation checklist

- Update version, changelog, and manifest release notes before tagging
- Confirm release notes describe behavior changes and compatibility restrictions
- Confirm Pester and GitHub CI pass
- Verify GitHub Release notes and PowerShell Gallery publication
- Keep examples and public metadata aligned with the exported parameters
- Verify the public `metadata/builtins.json` (`SchemaVersion: 1`) has entries for new apps with correct exported commands, cache paths and public icons
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
dist/OSDApps
```

That directory is the exact module directory supplied to `Publish-Module`.

## Safety

The CI workflow never publishes a package.

The PowerShell Gallery API key is only exposed to the publish job through the GitHub Actions secret. Normal CI never has access to the Gallery publishing step.
