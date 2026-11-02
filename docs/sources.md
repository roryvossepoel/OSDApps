# Sources and design references

[Documentation](README.md) · [GitHub Pages](https://roryvossepoel.github.io/OSDStage/)

This register records external documentation and upstream implementations used to
inform OSDStage. It is not a list of required services or a claim that an upstream
example has been validated in every deployment phase. Download endpoints and
publisher checks are documented separately in [built-in apps](built-in-apps.md).

The initial register was assembled on **1 November 2026** from references retained
in the repository and the Windows Update investigation. It is not a complete
retroactive browser history. Add newly consulted sources here as work proceeds.

## Windows deployment and updates

| Source | Used for | Project decision / evidence |
| --- | --- | --- |
| [Microsoft: custom scripts during Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup) | SetupComplete execution and restart constraints | [Runtime](runtime.md); an update component must not reboot or assume SetupComplete resumes after restarting |
| [Microsoft: WUA search, download and install example](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates) | Native COM workflow and per-update outcomes | [Windows Update investigation #109](https://github.com/roryvossepoel/OSDStage/issues/109); the example alone is not a deployment implementation |
| [Microsoft: IUpdateSearcher.Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search) | Search criteria, software/drivers and automatic/optional selection | #109; software type alone does not exclude feature upgrades |
| [Microsoft: Get-WsusClassification](https://learn.microsoft.com/en-us/powershell/module/updateservices/get-wsusclassification) | Language-independent update classification identities | #109; use classification metadata, not only translated update titles |
| [Microsoft: asynchronous WUA guidance](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/guidelines-for-asynchronous-wua-operations) | Callback lifetime, completion and cleanup | #109; request cancellation and wait safely, never terminate servicing to enforce a cosmetic timeout |
| [Microsoft: BeginInstall](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-begininstall) and [reboot prerequisite](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-get_rebootrequiredbeforeinstallation) | Async installation and pending restart handling | #109; report deferred work and reboot requirements |
| [Microsoft: automatic and optional drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/understanding-windows-update-automatic-and-optional-rules-for-driver-distribution) | Driver offering semantics | #109; drivers require a separate opt-in; an automatic offer is not an organizational approval |
| [Microsoft: firmware through Windows Update](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/updating-device-firmware-using-windows-update) | Firmware and extension-driver distribution | #109; firmware/BIOS is outside the initial scope |
| [OSDeploy/OSD: Start-WindowsUpdate](https://github.com/OSDeploy/OSD/blob/master/Public/OSDCloudTS/Start-WindowsUpdate.ps1) | Existing native-WUA implementation for comparison | Historical/upstream example; not proof of behavior in the current Recast OSDCloud workflow |
| [RecastSoftware/RecastOSDCloud](https://github.com/RecastSoftware/RecastOSDCloud) | Current OSDCloud workflow context | Keep OSDStage staging separate from deployment orchestration |
| [PowerShell FAQs: installing Windows updates](https://powershellfaqs.com/install-windows-updates-using-powershell/) | User-supplied COM example that prompted investigation | Background reading; technical decisions are checked against Microsoft documentation |

**Validation boundary:** PC1 completed a native WUA scan as SYSTEM within
SetupComplete in 20.8 seconds. This did not validate downloading/installing updates,
reboot completion or Autopilot handoff. Follow #109 for later evidence.

## Languages and Features on Demand

| Source | Used for | Project decision / evidence |
| --- | --- | --- |
| [Microsoft: add language packs to Windows](https://learn.microsoft.com/windows-hardware/manufacture/desktop/add-language-packs-to-windows?view=windows-11) | Language packs, associated capabilities and servicing order | [Language evaluation](language-evaluation.md); choose the desired base language in OSDCloud or maintain a custom image |
| [Microsoft: Install-Language](https://learn.microsoft.com/powershell/module/languagepackmanagement/install-language) | Full-Windows language installation alternative | Language evaluation; distinct from offline image injection |
| [Microsoft: checkpoint cumulative updates](https://learn.microsoft.com/windows/deployment/update/catalog-checkpoint-cumulative-updates) | Servicing prerequisites for the language experiment | Language evaluation; no monthly language/update payload repository is built into OSDStage |
| [Microsoft: capabilities / FoD](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11) and [non-language FoD](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod?view=windows-11) | Capability identity and content availability | [Windows capabilities](windows-capabilities.md) |
| [Microsoft: Add-WindowsCapability](https://learn.microsoft.com/en-us/powershell/module/dism/add-windowscapability) | Servicing sources and online acquisition behavior | Windows capabilities; do not confuse installed OS components with available download payloads |

## Device configuration and package installation

| Source | Used for | Project documentation |
| --- | --- | --- |
| [Microsoft: export/import default associations](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/export-or-import-default-application-associations) and [DISM association servicing](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-default-application-association-servicing-command-line-options) | Initial file/protocol associations | [Default associations](default-associations.md) |
| [Microsoft: ConfigureStartPins](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-start#configurestartpins) and [Start layout](https://learn.microsoft.com/windows/configuration/start/layout) | Initial Start pin configuration and supported builds | [Desktop settings](desktop-settings.md) |
| [Microsoft: taskbar pinned apps](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps) | Taskbar layout and timing | Desktop settings |
| [Microsoft: PnPUtil syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) and [return values](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-return-values) | Driver package installation and result interpretation | [Driver packages](driver-packages.md) |
| [CMTrace Open releases](https://github.com/adamgell/cmtraceopen/releases) | Upstream release and asset metadata | [CMTrace Open](cmtrace-open.md) |

## Maintaining this register

- Add the exact source, its purpose, and a link to the relevant design or validation record in the same PR as the change.
- Prefer Microsoft/vendor documentation and the actual upstream code. Label community articles as background rather than product guarantees.
- Distinguish researched behavior, implemented behavior, automated checks and physical acceptance. A source link is not test evidence.
- When revisiting a source for changed behavior, record the review date and affected Windows/module version in the linked validation record.
- Keep this file canonical. The website links here; do not maintain an independent copy of the source list.
