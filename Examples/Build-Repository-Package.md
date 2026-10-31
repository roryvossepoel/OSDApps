# From Install.ps1 to a repository package

[Examples](README.md) · [Repository contract](../docs/repository.md)

Run the authoring commands on a **full-Windows preparation machine**, not on a
PC waiting to run SetupComplete. Use your own installer or configuration script;
this guide does not supply a built-in script, sample debloat logic or vendor payload.

## 1. Prepare your source

Create this folder with your real unattended script and any files it needs:

```text
C:\OSDStage\Source\YourPackage\
    Install.ps1
    <supporting files, if needed>
```

`Install.ps1` belongs directly in the source folder. The packaging helper adds
the `Package/` directory inside the ZIP. The runner executes it as SYSTEM with
the extracted `Package` directory as the working directory.

Before packaging, make sure your script waits for child installers and propagates
their exit code. It must not require user input or restart/shut down Windows.
Use machine-context settings; a normal user's HKCU profile is not available.
Test the real logic on a disposable target. Packaging checks do not execute it.

## 2. Build, add metadata and validate

Save and run this block as a single `.ps1` file after preparing the source. Edit
the values at the top. It builds local content; it does not install the app or
upload anything to your hosting.

```powershell
$ErrorActionPreference = 'Stop'

Install-Module OSDStage -Force -SkipPublisherCheck
Import-Module OSDStage -Force

$Id = 'YourPackage'
$Version = '1.0.0'
$Architecture = 'x64'
$PackageType = 'App' # App, Script or Font.
$SourcePath = "C:\OSDStage\Source\$Id"
$OutputPath = "C:\OSDStage\Build\$Id\$Version\$Architecture"
$RepositoryPath = 'C:\OSDStage\Repository'

New-OSDStageRepository -Path $RepositoryPath | Out-Host

$package = New-OSDStagePackage -Id $Id -Version $Version -PackageType $PackageType `
    -SourcePath $SourcePath -OutputPath $OutputPath

$packageCheck = Test-OSDStagePackage -PackagePath $package.PackagePath -PackageType $PackageType
if (-not $packageCheck.Valid) {
    throw 'Package layout validation failed.'
}

Add-OSDStagePackage -Id $Id -DisplayName 'Your package' -Vendor 'Your organization' `
    -Version $Version -Architecture $Architecture -PackageType $PackageType `
    -SuccessCodes @(0) -PackagePath $package.PackagePath `
    -RepositoryPath $RepositoryPath | Out-Host

$checks = @(Test-OSDStageRepository -RepositoryPath $RepositoryPath)
$checks | Format-Table Id, Version, Architecture, HashValid, PackageValid, Orphaned, Valid
if ($checks.Count -eq 0 -or @($checks | Where-Object { -not $_.Valid }).Count -gt 0) {
    throw 'Repository validation failed. Do not publish this content.'
}

Write-Host 'Repository package validated. Ready for publication.'
```

Choose `x64`, `arm64`, or `any` to match the actual payload. A PowerShell script
is not automatically architecture-neutral: use `any` only if its logic and all
supporting files work on both target architectures. Declare only the exit codes
that genuinely mean success for your package. The example accepts only `0`;
add `3010` if your installer uses it for successful completion with a pending
reboot. Accepting that code does not authorize the script to restart Windows.

For a script package, change `$PackageType` to `Script`. It still enters through
`Install.ps1` and uses the normal repository runtime.

For a font package, use `$PackageType = 'Font'`. The source folder does not need
`Install.ps1`; place one or more `.ttf`/`.otf` files in it. Publish with
`-Architecture any` when the font files are architecture-neutral, then stage in
WinPE with `Add-OSDStageFont -Id <Id>`. OSDStage owns the machine-wide font
installation and ignores unsupported files in the archive.

The resulting files are:

```text
Repository/
    catalog.json
    Packages/YourPackage/1.0.0/x64/
        manifest.json
        Package.zip
```

Use a new version when changing package content. Reusing an output path replaces
its existing archive, and adding the same Id/version/architecture replaces that
local package variant. Keep your source separately and validate before publishing.

For updates, work on a separate local copy of the repository. The validator
reports old version folders no longer referenced by `catalog.json` as `Orphaned`
and invalid. Review and archive those superseded folders outside the candidate
repository, then rerun validation. This guide does not automatically delete old
packages or prune the USB cache. Keep older hosted versions available for clients
that may still be using the previous catalog during publication.

## 3. Publish static files

Upload the version directory, including `manifest.json` and `Package.zip`, to
your own HTTP/HTTPS hosting while preserving the relative paths. Verify both
files are accessible, then publish the updated root `catalog.json` **last**, so
clients do not discover the new version before its files are available.

The existing root catalog may reference other packages: publish its complete
updated contents, not a replacement catalog containing only the new package.
`Add-OSDStagePackage` updates the local repository; it is not a cloud upload command.

## 4. Stage on a deployment PC

In WinPE after OSDCloud has applied Windows, load OSDStage and use the actual URL
and ID from your repository:

```powershell
Install-Module OSDStage -Force -SkipPublisherCheck
Import-Module OSDStage -Force

Set-OSDStageConfiguration -CatalogUri 'https://packages.example.com/osdstage/catalog.json'
Add-OSDStage -Name 'YourPackage'
Test-OSDStageDeployment -ThrowOnFailure
```

Replace the placeholder URL. Repository packages are acquired, hash-checked and
staged in WinPE. After the normal reboot, SetupComplete runs the selected local
package. Check the [recorded results](../docs/getting-started.md#5-check-the-outcome)
for its outcome; a valid archive does not establish that the installer works.
