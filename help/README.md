# Maintaining command help

[Contributing](../CONTRIBUTING.md) · [User documentation](../docs/README.md)

`CommandHelp.psd1` contains reviewed text for every exported OSDApps function. It is build-time input, not an alternative command implementation. Examples are literal strings and are never executed to generate help.

## What to document

Every command needs a synopsis, description, execution environment, result explanation, at least one example with remarks, and a repository documentation link. Parameters can use a common description or a command-specific override. Explain whether a command reads, downloads, stages, deletes or installs; do not conflate file presence, SHA-256 integrity, publisher trust and installation success.

The generator obtains parameter sets, names, types, declared defaults and ValidateSet values from the real module. An undocumented or stale parameter fails the build. Use single-quoted strings in the data file so example variables such as `$false` and `$_` stay literal. Examples must use exact public parameter names rather than abbreviations.

## Build and inspect

Run from a repository checkout on a Windows development machine. This builds a package under `dist/OSDApps`; it does not stage or install applications.

```powershell
./build/Build-Module.ps1
```

`New-CommandHelp.ps1` generates `dist/OSDApps/OSDApps-help.xml`. Functions that already contain local comment-based help receive an `.EXTERNALHELP` comment **only in the built copies**. The connector verifies their non-comment PowerShell tokens have not changed. Repository files under `Public`, `Private` and `Runtime` are not rewritten.

Start a fresh PowerShell session to avoid cached help from a previous module import, then run:

```powershell
Import-Module ./dist/OSDApps/OSDApps.psd1 -Force
Get-Help Show-OSDAppUI -Full
Get-Help Add-OSDApp -Examples
Get-Help Clear-OSDAppCache -Parameter All
```

The generated file supports offline Get-Help; no Update-Help or network download is needed to read it. A direct import of the **raw source** manifest does not generate the external help. Test the built package, not a previously installed Gallery version or raw checkout. `Get-Help -Online` deliberately opens the related online documentation instead.

## Automated checks

```powershell
./build/Test-Module.ps1 -ResultsPath ./TestResults
./build/Test-Documentation.ps1
```

In a new PowerShell process after the build:

```powershell
./build/Test-PackagedHelp.ps1 -ModulePath ./dist/OSDApps
```

The packaged check uses real `Get-Help -Full` for every export, checking synopsis, execution-environment text, parameter sets, parameter names and example count. CI runs this separately on Windows PowerShell 5.1 and PowerShell 7. The help-source tests additionally parse example PowerShell and validate public OSDApps command/parameter names **without executing examples**.

Markdown validation checks the repository's inline local links, section anchors and fenced PowerShell syntax. It is not an external website crawler, complete Markdown implementation, hardware deployment test or validation of vendor installer behavior. Historical release-evidence pages keep their historical command names.

## Publishing boundary

Changing help/build/tests alone does not change `ModuleVersion` or republish the existing immutable Gallery release. The generated help reaches Gallery users only through a separately approved new version and its normal release workflow. CI artifacts let reviewers inspect it before that release.
