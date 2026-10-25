# Registry staging

`Add-OSDAppRegistryKey` stages a key without adding or deleting values.
`Add-OSDAppRegistryValue` stages a value and creates all missing parent keys when
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
$key = 'HKLM:\SOFTWARE\OSDApps\Tests\RegistryStaging\Level1\Level2\Level3'
Add-OSDAppRegistryKey -Path "$key\EmptyKey" -Registry64
Add-OSDAppRegistryKey -Path "$key\EmptyKey" -Registry32
Add-OSDAppRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn64BitView' -Registry64
Add-OSDAppRegistryValue -Path $key -Name Marker -Type String -Value 'CreatedIn32BitView' -Registry32
Add-OSDAppRegistryValue -Path "$key\Default" -Name Marker -Type String -Value 'HostDefault'
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
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
runner and Viewer. The internal Package.zip is an OSDApps-owned script archive,
not a renamed vendor download. It contains only code and registry configuration.
The existing app installer runtime is unchanged by this feature.

Repeated calls replace the same action/path/value-name/view intent. Different
views remain distinct. Calls that overlap a Default and explicit view are
executed in recorded order; the final write wins where Windows resolves them to
the same location. A key-only request never clears existing values.

`AppCount` increases by one, not by the number of registry operations. The
separate `%ProgramData%\OSDApps\Results\Registry-Result.json` reports each
operation, effective view, process bitness and Created/Updated/Unchanged outcome.
The normal `Latest.json` records the Script exit code. Configuration is validated
before any write. Individual runtime failures are reported and the Script exits
with failure; successful earlier writes are not rolled back.

## Validation boundaries

Automated tests cover staging without registry mutation, both host bitnesses,
both explicit views, Default resolution, empty keys, read-back, repeated runs,
updates, type conversion and invalid input. Real registry tests use only unique
GUID-named subtrees under HKLM\SOFTWARE\OSDApps\Tests and remove those subtrees.
A physical WinPE/SetupComplete test is still required for the new feature.

For a registry-only physical test use the supplied launcher example and an empty
Windows deployment. Keep the existing working USB module under its old folder;
place this candidate in `OSDApps-Registry` alongside it. Do not erase app caches
or publish to the Gallery to test this feature.
