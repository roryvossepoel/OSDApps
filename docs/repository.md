# Repository applications

![Self-maintained repository contract](images/repository-contract.svg)


OSD Apps repositories are static content. A separate repository service or PowerShell module is not required.

OSDApps defines the repository contract, provides examples, and includes optional authoring helpers to create and validate the required folders and JSON.

Application names used in examples, such as `OmnissaHorizonClient` and `NotepadPlusPlus`, represent packages from an organization's own repository. They are not built-in OSDApps applications and are not distributed or maintained by this project.

Repository synchronization is a **WinPE operation**. OSDApps resolves the requested repository package, refreshes or reuses the optional OSDCloud USB cache, validates the package, and stages it into the offline Windows installation before the first boot. SetupComplete then installs the staged local package; repository content is not refreshed again in full Windows.

## Repository layout

```text
Repository/
├── catalog.json
└── Apps/
    └── <AppId>/
        └── <Version>/
            └── <Architecture>/
                ├── manifest.json
                └── Package.zip
```

Supported repository architectures:

```text
x64
arm64
any
```

## Root catalog

`catalog.json` is an index. It points to the current package manifest for each application and architecture.

Example:

```json
{
  "SchemaVersion": 1,
  "GeneratedAt": "2026-10-06T00:00:00Z",
  "Applications": [
    {
      "Id": "ExampleApp",
      "Packages": [
        {
          "Architecture": "x64",
          "Manifest": "Apps/ExampleApp/1.0.0/x64/manifest.json"
        }
      ]
    }
  ]
}
```

## Package manifest

Each deployable package keeps its metadata directly beside `Package.zip`.

```json
{
  "SchemaVersion": 1,
  "Id": "ExampleApp",
  "DisplayName": "Example App",
  "Vendor": "Example Software",
  "Version": "1.0.0",
  "Architecture": "x64",
  "SuccessCodes": [
    0,
    3010
  ],
  "Archive": {
    "FileName": "Package.zip",
    "Sha256": "<SHA256>"
  }
}
```

The `Vendor` property is optional descriptive package metadata. It is set in
each application's `manifest.json`, alongside `DisplayName`. If omitted,
existing repositories remain fully compatible and the GUI shows a dash for an
unknown vendor. The value is carried into USB `CacheCatalog.json` and the
staged `DeviceManifest.json`; the GUI remains read-only.

You can add or correct `Vendor` in an existing published package manifest
without repackaging `Package.zip` or changing its SHA-256 hash. Publish the
updated manifest and run `Sync-OSDAppRepository -Name <Id>` on the Windows
development machine (or normal WinPE repository sync) to refresh its cached
metadata. The existing cache archive is reused when its SHA-256 still matches.
Previously staged `DeviceManifest.json` files are not silently rewritten.

The package URL is derived from the manifest location. A separate `SourcePath` property is not used.

## Package archive contract

Authoring source:

```text
ExampleApp/
├── Install.ps1
└── <payload>
```

Published archive:

```text
Package.zip
└── Package/
    ├── Install.ps1
    └── <payload>
```

`Install.ps1` must be unattended and suitable for execution during SetupComplete. The runner starts it with the extracted `Package` directory as its working directory.

## Deployment lifecycle

```text
WinPE
→ resolve catalog.json
→ resolve requested app manifest
→ synchronize/reuse OSDCloud USB cache
→ validate SHA-256
→ stage Package.zip to offline Windows

First boot / SetupComplete
→ validate staged package again
→ extract Package.zip
→ run Package/Install.ps1
```

This makes repository applications deterministic at first boot: the package that was selected and cached in WinPE is the package that SetupComplete installs.

## Creating a repository

The complete structure may be created manually. OSDApps also includes convenience helpers.

Create an empty repository:

```powershell
New-OSDAppRepository -Path C:\OSDApps\Repository
```

Build a package:

```powershell
New-OSDAppPackage `
    -Id ExampleApp `
    -Version 1.0.0 `
    -SourcePath C:\OSDApps\Packages\ExampleApp `
    -OutputPath C:\OSDApps\Build\ExampleApp
```

Publish it into the repository:

```powershell
Add-OSDAppPackage `
    -Id ExampleApp `
    -DisplayName 'Example App' `
    -Vendor 'Example Software' `
    -Version 1.0.0 `
    -Architecture x64 `
    -PackagePath C:\OSDApps\Build\ExampleApp\Package.zip `
    -RepositoryPath C:\OSDApps\Repository
```

The helper:

1. validates the fixed `Package/Install.ps1` archive layout;
2. creates `Apps/<Id>/<Version>/<Architecture>`;
3. copies `Package.zip`;
4. calculates SHA-256;
5. writes `manifest.json`;
6. adds or replaces the architecture reference in `catalog.json`.

## Validation

Validate an individual archive:

```powershell
Test-OSDAppPackage C:\OSDApps\Build\ExampleApp\Package.zip
```

Validate the complete repository:

```powershell
Test-OSDAppRepository C:\OSDApps\Repository
```

Repository validation checks:

- referenced package manifest exists;
- `Package.zip` exists;
- SHA-256 matches;
- archive contains `Package/Install.ps1`;
- architecture is `x64`, `arm64`, or `any`;
- package manifest Id matches the catalog application Id;
- success codes are present and numeric;
- the archive definition uses `Package.zip` and contains a valid SHA-256;
- duplicate application/architecture references are detected;
- orphaned package manifests that are not referenced by `catalog.json` are reported;
- package size and repository free space are included in the validation output.

## Built-in or repository?

Repository applications are not limited to niche or custom software. They can also be used for applications that OSDApps supports as built-ins when an organization prefers to own the package lifecycle itself.

For example, Microsoft 365 Apps can be deployed either way:

```text
Built-in Office
→ Office Deployment Tool checks/synchronizes Office in full Windows
→ cache can update automatically from Microsoft
→ install current synchronized content
```

or:

```text
Repository Office
→ organization packages and versions Office
→ repository sync happens in WinPE
→ staged package is installed in full Windows
→ no built-in Office freshness step
```

This gives organizations a simple performance/control choice:

- use a **built-in** when vendor-native evergreen maintenance is preferred;
- use the **repository** when package/version ownership and a more deterministic full-Windows phase are preferred.

The repository is therefore not a fallback path. It is a first-class deployment model with different ownership and synchronization semantics.

## Publishing

The resulting repository is ordinary static content. Publish the contents of `Repository` to an HTTP/HTTPS location while preserving paths.

For example:

```text
https://example.blob.core.windows.net/osdapps/catalog.json
https://example.blob.core.windows.net/osdapps/Apps/ExampleApp/1.0.0/x64/manifest.json
https://example.blob.core.windows.net/osdapps/Apps/ExampleApp/1.0.0/x64/Package.zip
```

Configure a deployment session with:

```powershell
Set-OSDAppConfiguration -CatalogUri 'https://example.blob.core.windows.net/osdapps/catalog.json'
```

## Examples

A starter repository and package source template are included under [Examples](../Examples/README.md).

The examples are intentionally simple: the repository contract is designed to remain understandable and maintainable without proprietary tooling.
