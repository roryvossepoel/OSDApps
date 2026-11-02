# Files and directories

[Documentation](README.md) · [Getting started](getting-started.md) · [Release availability](release-status.md)

**Available from Gallery version 1.0.0-rc2.** Not included in RC1.

Use `Add-OSDStageDirectory` and `Add-OSDStageFile` in WinPE after OSDCloud
has applied Windows. They stage intent; SetupComplete performs the changes
once as SYSTEM. Later user changes are not reverted.

```powershell
# Run in WinPE after OSDCloud; use the module build containing these commands.
Add-OSDStageDirectory -Path '%ProgramData%\Contoso\Tools'
Add-OSDStageFile -Path '%ProgramData%\Contoso\settings.json' `
    -Content '{"ring":"Pilot"}' -Force

# Use the actual source path available in this WinPE session.
Add-OSDStageFile -SourcePath 'E:\Input\config.ini' `
    -DestinationPath '%ProgramData%\Contoso\config.ini' -Force

Add-OSDStageFile -Path '%ProgramData%\Contoso\old.ini' -Remove -Force
Add-OSDStageDirectory -Path '%ProgramData%\Contoso\Old' -Remove -Recurse -Force
```

Every call appends to **one FileSystem queue entry**, in call order. Create,
replace and remove operations for the same path are preserved in that order;
there is no last-operation deduplication. The queue entry keeps its position
relative to other packages. If a file operation needs an installed app, stage
that app before the first file/directory call.

## Behavior

| Request | Result |
| --- | --- |
| Create a missing directory or file | Create missing parent directories automatically |
| Create an existing directory | Succeed unchanged |
| Write identical file bytes | Succeed unchanged, without requiring Force |
| Write different bytes to an existing file | Fail unless `-Force` was specified |
| Remove an absent path | Succeed as `AlreadyAbsent` |
| Remove a nonempty directory | Require `-Remove -Recurse`; `-Force` alone is insufficient |
| Remove a read-only item | Require `-Force`; still respect ACLs |
| File/directory type conflict | Fail, including with `-Force` |

`-Path` on the directory command accepts multiple paths. File operations target
one literal file at a time. `-WhatIf` validates input and previews staging without
adding an operation. `-Force` is a content/attribute option, not an approval bypass.

Text uses UTF-8 without BOM by default. `-Encoding UTF8BOM`, `Unicode`
(UTF-16 LE with BOM) and `ASCII` are also available. ASCII rejects non-ASCII text.
No newline is added. Omit `-Content` to create a zero-byte file. Copying with
`-SourcePath` preserves bytes and captures them during staging, so the source
drive is not needed during SetupComplete.

## Paths and limits

Use single-quoted `%ProgramData%\Contoso\...` paths to resolve the installed
Windows location at execution time. Supported prefixes are `%SystemDrive%`,
`%SystemRoot%`, `%windir%`, `%ProgramData%`, `%ProgramFiles%` and
`%ProgramFiles(x86)%`. An absolute `C:\...` path means that drive in full Windows;
it is not automatically remapped from WinPE. Do not expand `$env:windir` in
WinPE to build the destination, since that can point at `X:\Windows`.

Only literal local paths are supported. No wildcards, UNC/device paths,
relative components, alternate data streams, junctions or symbolic links.
Drive roots, the Windows/ProgramData/ProgramFiles/Users roots and OSDStage's
staging, result and SetupComplete locations are protected. These checks are
guardrails, not an exhaustive list of Windows-owned files: choose paths carefully.
Recursive removal preflights the tree for links and read-only items before
deleting it. It is not transactional; an I/O failure during deletion can leave
a partially removed tree. No ownership takeover or ACL changes are performed.

File content is limited to **16 MiB per operation**. Larger payloads and directory
trees belong in a repository Script package. There is no USB cache acquisition
step for this built-in; content is already in staging. `Test-OSDStageDeployment`
validates the staged script/configuration hashes and offline readiness.

Content is Base64-encoded in the staging configuration, **not encrypted**.
Do not use this feature for passwords or secrets. File bytes are omitted from
runtime logs and results. Original source files are never deleted by OSDStage;
staging cleanup follows the configured cleanup policy.

## Results and testing

`%ProgramData%\OSDStage\Results\FileSystem-Result.json` (or the configured result
directory) contains per-operation status/outcome, failure reason and the deployment
ID. A failed operation marks the package failed; later operations are still
attempted. No reboot, recurring task or post-login repair is added.

Use [the disposable test example](../Examples/Stage-OSDStageFileSystemTest.ps1)
for physical acceptance. It only touches a unique test directory. Automated
tests cover staging integrity, encodings, idempotence, replacement, recursive
removal, read-only items, links and the Windows runner.

Physical acceptance passed on **1 November 2026**: WinPE staging was valid and
offline-ready, then all nine SetupComplete operations succeeded. Independent
checks confirmed the replacement text (`after`), a zero-byte file, exact binary
copy (`00-FF-0A-0D-80`), recursive directory removal and individual file removal.
The test added an individual file create/remove pair to the seven-operation
example. Read-only and link rejection remain automated-test evidence.
Deployment ID: `82664f3f-ade5-426d-a523-21dd632c7a1c`.
These commands are included in `1.0.0-rc2`; the earlier `1.0.0-rc1` module is unchanged.

[Back to documentation](README.md)
