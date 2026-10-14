# Examples

[Project](../README.md) · [Getting started](../docs/getting-started.md) · [Documentation](../docs/README.md)

Choose an example for the environment you are using. These are reference workflows, not additional recorded hardware test results; the actual test evidence is in the [validation matrix](../docs/testing.md).

| Example | Run on | Changes made |
| --- | --- | --- |
| [Prepare a USB cache](Prepare-UsbCache.md) | Full Windows preparation machine | Saves module files, optionally downloads/refreshes content, and shows explicit repository health/prune preview; does not stage apps against Windows. |
| [Online WinPE deployment](WinPE-Online.md) | WinPE after OSDCloud has applied Windows | Stages app intent/content and SetupComplete on the discovered offline target; optional repository sync downloads packages. |
| [Offline WinPE deployment](WinPE-Offline.md) | WinPE with complete matching cache and networking disconnected | Stages cached content and SetupComplete without repository refresh. |
| [Build a repository package](#build-a-repository-package) | Full Windows authoring machine | Creates a package archive and local repository metadata. |

The deployment examples use x64 Teams and Firefox Rapid/en-US so preparation and staging select the same variants. They pin OSDApps 0.38.0, discover the USB by label rather than assuming a drive letter, and do not format disks or reboot automatically. Repository pruning appears only as a separate preview-and-confirm maintenance step.

Add other apps only after selecting their intended configuration. For example, match Office architecture, channel, language and products between cache preparation and staging. See [Built-in applications](../docs/built-in-apps.md).

## Build a repository package

**Environment: full Windows, from the repository checkout root, with OSDApps loaded.** This example writes under `C:\OSDApps`; use a different authoring/output location as needed. It does not deploy an app to the machine.

`PackageSource/ExampleApp/Install.ps1` is a layout placeholder that prints a message and exits 0. Replace it with the application's unattended installer logic and include the required payload before treating the package as a real deployment.

```text
PackageSource/ExampleApp/
    Install.ps1
    <installer payload>
```

Build the archive and publish it to a local repository directory:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module OSDApps -RequiredVersion 0.38.0 -Force

New-OSDAppPackage `
    -Id ExampleApp `
    -Version 1.0.0 `
    -SourcePath .\Examples\PackageSource\ExampleApp `
    -OutputPath C:\OSDApps\Build\ExampleApp

Add-OSDAppPackage `
    -Id ExampleApp `
    -DisplayName 'Example App' `
    -Vendor 'Example Software' `
    -Version 1.0.0 `
    -Architecture x64 `
    -PackageType Application `
    -PackagePath C:\OSDApps\Build\ExampleApp\Package.zip `
    -RepositoryPath C:\OSDApps\Repository

Test-OSDAppRepository -RepositoryPath C:\OSDApps\Repository
```

`Vendor` is optional descriptive metadata, not an installer argument or trust assertion. Existing repository apps without it remain compatible. Publishing this local directory to your own hosting is a separate step; `Add-OSDAppPackage` is not an Azure upload command.

For a configuration or debloat package, keep the same archive layout and use
`-PackageType Script`. This is classification only: the script receives the
same SHA-256 enforcement, staging, SYSTEM execution context and one-shot
failure handling as an application package.

The required archive layout is:

```text
Package.zip
    Package/
        Install.ps1
        <installer payload>
```

## Repository template

`Repository/catalog.json` is an empty valid catalog template. It deliberately contains no real vendor installers or deployable sample applications. To start a new local repository without copying the template:

```powershell
New-OSDAppRepository -Path C:\OSDApps\Repository
```

See [Repository applications](../docs/repository.md) for per-app manifests, archive hashes, publishing and deployment. No tenant-specific URL, credential or organization deployment profile is supplied by these examples.
