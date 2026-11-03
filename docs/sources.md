# Sources and design references

[Documentation](README.md) · [GitHub Pages](https://roryvossepoel.github.io/OSDStage/)

This register records external documentation and upstream implementations used to
inform OSDStage. It is not a list of required services or a claim that an upstream
example has been validated in every deployment phase. Download endpoints and
publisher checks are documented separately in [built-in apps](built-in-apps.md).

The initial register was assembled on **1 November 2026** from references retained
in the repository and the Windows Update investigation. It is not a complete
retroactive browser history. Add newly consulted sources here as work proceeds.

On **2 November 2026**, the register was expanded from links retained in the
feature guides, Git history, PR descriptions/comments and the available project
conversation. A retained link shows where a reference was recorded; it does not
establish the first date it was read. Earlier conversations could not be searched
in this review. The coverage notes below make the remaining gaps explicit.

## Windows deployment and updates

| Source | Used for | Project decision / evidence |
| --- | --- | --- |
| [Microsoft: custom scripts during Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup) | SetupComplete execution and restart constraints | [Runtime](runtime.md); an update component must not reboot or assume SetupComplete resumes after restarting |
| [Microsoft: WUA search, download and install example](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates) | Native COM workflow and per-update outcomes | [Windows Update investigation #109](https://github.com/roryvossepoel/OSDStage/issues/109); the example alone is not a deployment implementation |
| [Microsoft: IUpdateSearcher.Search](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search) | Search criteria, software/drivers and automatic/optional selection | #109; software type alone does not exclude feature upgrades |
| [Microsoft: Get-WsusClassification](https://learn.microsoft.com/en-us/powershell/module/updateservices/get-wsusclassification) | Language-independent update classification identities | #109; use classification metadata, not only translated update titles |
| [Microsoft: asynchronous WUA guidance](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/guidelines-for-asynchronous-wua-operations) | Callback lifetime, completion and cleanup | #109; request cancellation and wait safely, never terminate servicing to enforce a cosmetic timeout |
| [Microsoft: BeginInstall](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-begininstall) and [reboot prerequisite](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-get_rebootrequiredbeforeinstallation) | Async installation and pending restart handling | #109 / [Windows Update](windows-update.md); distinguish a later restart from a prerequisite that blocks the next installation |
| [Microsoft: automatic and optional drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/understanding-windows-update-automatic-and-optional-rules-for-driver-distribution) | Driver offering semantics | #109; drivers require a separate opt-in; an automatic offer is not an organizational approval |
| [Microsoft: firmware through Windows Update](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/updating-device-firmware-using-windows-update) | Firmware and extension-driver distribution | #109 / [Windows Update](windows-update.md); current experimental driver opt-in includes firmware, which may apply at a later restart |
| [Microsoft: InstallationRebootBehavior](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-installationrebootbehavior) | Restart requirements after installation | Retained in [PR #111](https://github.com/roryvossepoel/OSDStage/pull/111); requiring a restart does not authorize the update step to initiate one |
| [Microsoft: component INF files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-a-component-inf-file) and [extension INF files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-an-extension-inf-file) | Independently serviced software-component devices | Reviewed 2 November 2026 after PC1 offered additional components following driver installation/restart; [one-pass boundary](windows-update.md#continuation-and-post-restart-evidence-2-november-2026) |
| [Microsoft: QueryHistory](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-queryhistory) and [OperationResultCode](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-operationresultcode) | Independent WUA history and result interpretation | Reviewed 2 November 2026; PC1 reported 47 successful history events while Settings history was empty; no claim about the cause of the UI discrepancy |
| [Microsoft: PowerSetRequest](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest) | Preventing idle sleep during runtime work and understanding power-policy limits | Retained in [Runtime](runtime.md); this does not prevent explicit sleep, power loss or every battery-powered Modern Standby transition |
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
| [Microsoft Support: language packs for Windows](https://support.microsoft.com/en-us/windows/hardware/input-devices/language-packs-for-windows) | User-supplied starting point for the language-pack investigation | Retained in the project conversation; [language evaluation](language-evaluation.md) records the resulting scope decision |

## Device configuration and package installation

| Source | Used for | Project documentation |
| --- | --- | --- |
| [Microsoft: export/import default associations](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/export-or-import-default-application-associations) and [DISM association servicing](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-default-application-association-servicing-command-line-options) | Initial file/protocol associations | [Default associations](default-associations.md) |
| [Microsoft: ConfigureStartPins](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-start#configurestartpins) and [Start layout](https://learn.microsoft.com/windows/configuration/start/layout) | Initial Start pin configuration and supported builds | [Desktop settings](desktop-settings.md) |
| [Microsoft: taskbar pinned apps](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps) | Taskbar layout and timing | Desktop settings |
| [Microsoft: PnPUtil syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) and [return values](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-return-values) | Driver package installation and result interpretation | [Driver packages](driver-packages.md) |
| [Microsoft: WlanSetProfile](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlansetprofile) and [WlanEnumInterfaces](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlanenuminterfaces) | Native WLAN profile import and interface enumeration | Retained in [Wi-Fi staging](wifi-staging.md); import success does not prove connectivity |
| [Microsoft: environment variables](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables) and [WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange) | Persistent machine environment and change notification | Retained in [Environment variables](environment-variables.md) |
| [Microsoft: sc.exe config](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-config) | Service startup configuration, including delayed automatic start | Retained in [Services](services.md) |
| [Microsoft: Win32 app processing](https://learn.microsoft.com/troubleshoot/mem/intune/app-management/develop-deliver-working-win32-app-via-intune) and [Intune detection rules](https://learn.microsoft.com/intune/intune-service/apps/apps-win32-add#step-4-detection-rules) | Explaining how preinstalled software relates to later Intune detection | Retained in [FAQ](faq.md); staging success is distinct from Intune detection-rule success |

An earlier taskbar reference, [Customize the Windows 11 taskbar](https://learn.microsoft.com/windows-hardware/customize/desktop/customize-the-windows-11-taskbar),
is retained in the [desktop-settings history](https://github.com/roryvossepoel/OSDStage/commits/main/docs/desktop-settings.md).
It is recorded here for historical traceability; the current guide uses the
Start/taskbar configuration references above.

## Built-in software and installer behavior

These references were already recorded in the linked feature documentation.
Payload URLs, architecture-specific endpoints and publisher checks remain in
[Built-in apps](built-in-apps.md), rather than being duplicated as a second
download catalog here.

| Source | Used for | Retained evidence |
| --- | --- | --- |
| [Cisco: Webex installation and automatic upgrade](https://help.webex.com/en-US/article/nw5p67g/Webex-%7C-Installation-and-Automatic-Upgrade) | MSI sources and deployment options | [Webex section](built-in-apps.md#cisco-webex) |
| [Zoom: mass deployment and configuration](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064484) and [administrator downloads](https://zoom.us/download/admin) | MSI deployment and administrator installer sources | [Built-in apps](built-in-apps.md), [Zoom validation](zoom-validation.md) |
| [7-Zip downloads](https://www.7-zip.org/download.html) and [upstream releases](https://github.com/ip7z/7zip/releases/latest) | Installer selection and release assets | [Built-in apps](built-in-apps.md) |
| [VS Code Windows setup](https://code.visualstudio.com/docs/setup/windows), [installer source](https://github.com/microsoft/vscode/blob/main/build/win32/code.iss) and [Inno Setup parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm) | Installer scope, task names and unattended command-line behavior | [Built-in apps](built-in-apps.md); task names are checked against the upstream installer source |
| [Microsoft: Visual C++ downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) and [runtime lifecycle FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/visual-c-faq) | Supported redistributables and runtime lifecycle | [Prerequisites](built-in-apps.md#microsoft-runtime-prerequisites) |
| [Microsoft: .NET installation on Windows](https://learn.microsoft.com/en-us/dotnet/core/install/windows) and [release metadata](https://github.com/dotnet/core/tree/main/release-notes) | Runtime types, channels and release metadata | [Built-in apps](built-in-apps.md) |
| [CMTrace Open releases](https://github.com/adamgell/cmtraceopen/releases) | Upstream release and asset metadata | [CMTrace Open](cmtrace-open.md) |
| Microsoft Download Center preinstall-kit endpoint | Company Portal package acquisition; a download source, not API design guidance | The exact dated URL is preserved in [PR #67's comment](https://github.com/roryvossepoel/OSDStage/pull/67#issuecomment-6390673471); see [Company Portal](microsoft-company-portal.md) for the current acquisition contract |

## Website and icon references

| Source | Context | Evidence boundary |
| --- | --- | --- |
| [Simple Icons](https://github.com/simple-icons/simple-icons) | Webex glyph provenance | Recorded in [Built-in apps](built-in-apps.md); asset attribution is separate from installer behavior |
| [Folder11 Company Portal SVG](https://raw.githubusercontent.com/icon11-community/Folder11/refs/heads/main/svg/microsoft_intune_company_portal.svg) | User-supplied visual reference when discussing removal of the folder background | Retained in the project conversation; this records the reference, not proof that the current icon was copied from it or a license determination |

## Coverage still to recover

No exact external design-reference link was recovered for the following areas in
the materials checked on 2 November. This does **not** mean no source was ever
consulted, nor that the commands are untested. Keep implementation and validation
evidence separate from historical source provenance.

| Area | Available project evidence |
| --- | --- |
| Fonts | [Font implementation and acceptance, PR #82](https://github.com/roryvossepoel/OSDStage/pull/82), [feature status](feature-status.md) |
| Certificates | [Certificate staging](certificate-staging.md), [PR #85](https://github.com/roryvossepoel/OSDStage/pull/85) |
| Registry keys and values | [Registry staging](registry-staging.md) |
| Files and folders | [File system](file-system.md) |
| Inbox cleanup and optional Windows features | [Built-in apps](built-in-apps.md), [feature status](feature-status.md) |
| Cache integrity and signature validation | [Architecture](architecture.md), [built-in apps](built-in-apps.md), [testing](testing.md) |

Where installer documentation records only a vendor download/API endpoint, treat
it as an acquisition source. Do not infer a previously consulted deployment
article from that endpoint. If a missing reference is newly researched, label it
with the new review date instead of presenting it as recovered history.

## Maintaining this register

- Add the exact source, its purpose, and a link to the relevant design or validation record in the same PR as the change.
- Record where a recovered reference was found (guide, commit, PR comment or supplied conversation link). Mark newly researched references separately from historical ones.
- Prefer Microsoft/vendor documentation and the actual upstream code. Label community articles as background rather than product guarantees.
- Distinguish researched behavior, implemented behavior, automated checks and physical acceptance. A source link is not test evidence.
- When revisiting a source for changed behavior, record the review date and affected Windows/module version in the linked validation record.
- Keep this file canonical. The website links here; do not maintain an independent copy of the source list.
