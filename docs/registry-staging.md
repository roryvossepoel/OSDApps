# Registry staging

`Add-OSDStageRegistryKey` stages a key without adding or deleting values.
`Add-OSDStageRegistryValue` stages a value and creates all missing parent keys when
SetupComplete executes it. Neither cmdlet writes to the WinPE registry.

Use these commands in WinPE after Windows has been applied. The normal module
configuration and SetupComplete integration are reused. Nothing is downloaded.

## Registry selection

- `-Registry32`: explicit 32-bit view.
- `-Registry64`: explicit 64-bit view; fails on 32-bit Windows.
- Neither switch: the executing Windows host's default view, resolved at runtime.
- Both switches: rejected before staging.

HKLM, HKCR and HKU accept their full root names and Registry provider prefixes.
HKCR is explicitly mapped to machine `HKLM\SOFTWARE\Classes`, not the merged user
view. HKU requires an already loaded, explicit user hive; no profiles are loaded
or created. HKCU and HKCC are unsupported. Explicit WOW6432Node path segments
are rejected. Shared keys remain shared according to Windows semantics.

## Examples

```powershell
$key = 'HKLM:\SOFTWARE\OSDStage\Tests\RegistryStaging\Level1\Level2\Level3'
Add-OSDStageRegistryKey -Path "$key\EmptyKey" -Registry64
Add-OSDStageRegistryKey -Path "$key\EmptyKey" -Registry32
Add-OSDStageRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn64BitView' -Registry64
Add-OSDStageRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn32BitView' -Registry32
Add-OSDStageRegistryValue -Path "$key\Default" -Name Marker -Type String -Value 'HostDefault'
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

Supported types are String, ExpandString, MultiString, Binary, DWord and QWord.
Empty `-Name ''` means the unnamed value. Binary accepts a byte array and
MultiString accepts a string array. Numeric data is serialized as decimal text,
so the complete DWORD/QWORD bit range survives JSON. Text is never evaluated as
PowerShell. Existing unrelated values and subkeys remain unchanged. No ACL,
ownership, key deletion or user-profile operations are performed by this feature.

## One queue entry, multiple operations

The commands build one local, SHA-256-verified `RegistrySettings` Script package
using the existing `RepositoryPackage` execution contract. It is generated
locally; no repository URL or cache is involved. Thus it appears as
`Source=Repository`, `PackageType=Script`, `Id=RegistrySettings` in the existing
runner and Viewer. The internal Package.zip is an OSDStage-owned script archive,
not a renamed vendor download. It contains only code and registry configuration.
The existing app installer runtime is unchanged by this feature.

Repeated calls replace the same action/path/value-name/view intent. Different
views remain distinct. Calls that overlap a Default and explicit view are
executed in recorded order; the final write wins where Windows resolves them to
the same location. A key-only request never clears existing values.

`PackageCount` increases by one, not by the number of registry operations. The
separate `%ProgramData%\OSDStage\Results\Registry-Result.json` reports each
operation, effective view, process bitness and Created/Updated/Unchanged outcome.
The normal `Latest.json` records the Script exit code. Configuration is validated
before any write. Individual runtime failures are reported and the Script exits
with failure; successful earlier writes are not rolled back.

## Validation boundaries

Automated tests cover staging without registry mutation, both host bitnesses,
both explicit views, Default resolution, empty keys, read-back, repeated runs,
updates, type conversion and invalid input. Real registry tests use only unique
GUID-named subtrees under HKLM\SOFTWARE\OSDStage\Tests and remove those subtrees.
CI #528 passed 569 tests on each of Windows PowerShell 5.1 and PowerShell 7 for
commit `3194fcca69d894df009d6c4c8d1b8bf72bbc4d9f`, with no failures or skipped tests.

### Physical x64 acceptance - 25 October 2026

The maintainer completed the registry-only WinPE -> SetupComplete -> OOBE test
using the USB module built from `3194fcc` and the normal launcher. The final
runner result and registry result share deployment ID
`88e3a849-2e4d-4ff5-abda-68f27c66294c`.

- Runner: one Script entry succeeded, exit code 0, no failed or skipped entries,
  and package SHA-256 checked before execution. Runner duration: 4.9 seconds.
- Registry result: nine of nine operations succeeded, all with `Outcome=Created`:
  three key-only operations and six String/DWord values.
- Independent read-back: Registry64 contained `CreatedIn64BitView` and 64;
  Registry32 contained `CreatedIn32BitView` and 32; both EmptyKey subkeys existed
  without values. All missing levels of the deep HKLM test path were present.
- With no switch, the separate Default subkey resolved to Registry64 in the
  recorded 64-bit process; `HostDefault`, 0 and its empty subkey were verified.
- PreInstall had no acquisition targets. No cache was used. Network availability
  was not measured; this is not evidence of a disconnected-network test.

This physical acceptance covers creation and read-back under HKLM on x64 Windows.
It does not claim physical HKCR/HKU coverage, native 32-bit Windows or ARM
coverage, a second physical idempotence run, or a combined apps-plus-registry run.
Repeated execution and updating one view are covered by the automated tests.
The separately successful 14-entry app deployment remains separate evidence.

For a registry-only physical test use the supplied launcher example and an empty
Windows deployment. Keep the existing working USB module under its old folder;
place this candidate in `OSDStage-Registry` alongside it. Do not erase app caches
or publish to the Gallery to test this feature. The successful acceptance above
does not require repeating the same deployment after documentation-only changes.

See the [candidate review and release handoff](release-candidate-0.52.0.md) for
breaking-contract requirements, known reporting limits and publication boundaries.
