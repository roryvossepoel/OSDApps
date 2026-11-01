# OSDStage contract

OSDStage is a new module identity. There is no transition module, old-command alias layer or conversion of OSDApps catalogs, cache data or device staging. Existing tested deployment behavior is the baseline. The renamed candidate passed its focused empty-cache Windows deployment; see [the acceptance record](osdstage-rename-acceptance.md).

## Names and contracts

| Surface | OSDStage contract |
| --- | --- |
| Module | `OSDStage.psd1`, `OSDStage.psm1`, new module GUID, initial version `0.1.0` |
| Commands | `Add-OSDStageFont`, `Add-OSDStageCertificate`, `Add-OSDStageDriver`, `Add-OSDStageWiFiProfile`, and the corresponding OSDStage discovery, configuration and sync commands |
| Repository catalog | `SchemaVersion: 2`, root `Packages`, each ID with an `Architectures` array |
| Package manifest | `SchemaVersion: 2`, `Payload: { FileName, Sha256 }` |
| Published content | `Packages/<Id>/<Version>/<Architecture>/manifest.json` and `Package.zip` |
| Cache catalog | Schema 2, flat `Packages` entries with `Payload` metadata |
| Device manifest | Schema 2, one ordered `Packages` queue |
| Deployment result | Schema `2.0`, `Packages` results |
| Configuration/result JSON | Owned configuration schemas use version 2; native Windows XML/JSON formats retain their native contracts |
| USB | Label `OSDCloud`, detected dynamically; cache root `\OSDStage` |
| Device staging | `Windows\Temp\OSDStage` |
| Durable logs/results | `ProgramData\OSDStage` |

Keep architecture in its own field and directory. Different configurations use different package IDs, such as `HorizonClient` and `HorizonClientKiosk`. Repository ID aliases remain an optional authoring feature; they are not aliases for old module commands or a product migration mechanism.

## Cache behavior

Preparing a USB content cache is optional. Repository staging synchronizes selected content from the configured catalog unless explicitly told to skip refresh. Most built-ins stage intent in WinPE and acquire or refresh content during full-Windows PreInstall, with an available OSDCloud-labeled USB as cache. Company Portal and CMTrace Open retain their documented pre-cache requirement. Configuration-only commands do not need downloadable content.

An empty OSDStage cache is a normal starting state. Existing integrity, transaction and incomplete-metadata recovery behavior remains in place within that cache. Renaming does not copy or delete an OSDApps cache. For disconnected deployment, populate the new cache explicitly before use.

## Release and acceptance

The GitHub repository was renamed to [roryvossepoel/OSDStage](https://github.com/roryvossepoel/OSDStage) on 1 November 2026 after PRs #99 and #100 merged and main CI passed. Source, icon, help and module metadata URLs now use that canonical repository name. Release creation remains manual; these changes do not publish OSDStage to the Gallery.

Windows PowerShell 5.1 and PowerShell 7 validation, fresh-cache content acquisition, ordered SetupComplete execution, renamed paths and independent cleanup checks have passed for the candidate recorded in [rename acceptance](osdstage-rename-acceptance.md). CI on later changes is separate evidence. Historical feature records remain scoped to their recorded candidates. Viewer publication, public Pages documentation and Gallery release remain separate work.
