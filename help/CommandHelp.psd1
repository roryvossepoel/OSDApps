@{
    # Build-time source for packaged Get-Help. Example code is never executed.
    SchemaVersion = 1
    CommonParameters = @{
        PreventSleep = 'Prevent automatic idle sleep during PreInstall and Runner. Defaults to true; use -PreventSleep $false before staging to disable it. Uses a temporary power request, not a power-plan change. Keep AC power connected; explicit sleep and battery power policies can override it.'
        WindowsPath = 'Root of the intended Windows volume, for example D:\, not D:\Windows. When omitted, deployment commands discover a Windows installation. Use Add deployment commands in WinPE after applying Windows, not on the preparation computer.'
        Architecture = 'Requested package architecture; match the target and offline cache variant. Allowed values and source defaults are included below.'
        PackageUri = 'Optional vendor-owned package URL overriding the built-in source. Does not bypass signature/publisher validation for supported MSI packages.'
        MinimumFreeSpaceGB = 'Minimum free space before preparing a replacement cache generation, in PowerShell GB units. A larger payload estimate plus working margin can require more. Unchanged MSI/ZIP reuse skips this check. This does not reserve space or guarantee that an unknown download will fit.'
        InstallTimeoutMinutes = 'Maximum installer runtime in minutes during SetupComplete. Does not configure download timeouts.'
        Channel = 'Vendor release channel. Match the channel used to prepare offline content.'
        Language = 'Vendor language identifier or identifiers. Match the language used to prepare offline content.'
        ProductId = 'Office product identifier for generated Office Deployment Tool configuration.'
        AcceptEula = 'Write the vendor EULA acceptance option into generated configuration. Supply a Boolean value to change the default.'
        SharedComputerLicensing = 'Generate Office shared-computer licensing configuration. Cannot be enabled with DeviceBasedLicensing. Does not verify entitlement or activation.'
        DeviceBasedLicensing = 'Generate Office device-based licensing configuration. Cannot be enabled with SharedComputerLicensing. Does not verify entitlement or activation.'
        UpdatesEnabled = 'Enable updates in generated Office XML. Supply -UpdatesEnabled $false to disable that XML setting.'
        IncludeVisio = 'Include Visio Professional in generated Office XML. Does not grant a license.'
        IncludeProject = 'Include Project Professional in generated Office XML. Does not grant a license.'
        ExcludeApp = 'Office app identifiers to exclude from generated XML; does not replace settings inside custom XML.'
        ConfigurationXml = 'Existing custom Office XML. Syntax is validated and the file is copied instead of generating XML from simple options. Vendor semantic correctness and effective installed update-channel state are not verified.'
        OfficeDeploymentToolUri = 'Vendor-owned ODT setup.exe URL. The signed executable must match Microsoft; this check does not cover the Office data tree.'
        MicrosoftTeamsBootstrapperUri = 'Vendor-owned Teams bootstrapper URL recorded in deployment intent. Runtime checks the bootstrapper, not the entire Teams MSIX.'
        BootstrapperUri = 'Vendor-owned Teams bootstrapper URL for synchronization. Authenticode and expected Microsoft publisher are required.'
        InstallMeetingAddin = 'Request the Teams meeting add-in during installation. Stored in deployment intent; does not install it while staging.'
        AutoStartWithWindows = 'Generate Cisco Webex AUTOSTART_WITH_WINDOWS MSI property.'
        PreventPreLoginUpdates = 'Generate Cisco PREVENT_PRELOGIN_UPDATES=1 when enabled.'
        EnableOutlookIntegration = 'Optional Cisco ENABLEOUTLOOKINTEGRATION property. Omit to preserve vendor default; explicit false writes 0.'
        DefaultTheme = 'Optional Cisco Webex theme. Omission preserves vendor behavior.'
        EmailHint = 'Literal Cisco placeholder: $userPrincipalName, $mail or $SAMAccountName. Quote the placeholder. A fixed email address is rejected for this all-users install.'
        AdditionalMsiProperties = 'Cisco NAME=VALUE pairs. Managed properties, duplicates, unsupported quotes and control characters are rejected. Prefer dedicated parameters.'
        Id = 'Technical repository app identifier, used in metadata and paths; not a display name.'
        DisplayName = 'Human-readable repository app name for discovery and the Viewer.'
        Vendor = 'Optional descriptive publisher metadata, not a cryptographic result or installer argument.'
        Version = 'Repository package version written into authoring metadata and paths. Does not query installed apps.'
        PackagePath = 'Existing Package.zip archive. App and Script packages require Package/Install.ps1; Font packages require at least one .ttf or .otf under Package/. Driver packages require INFs and their complete vendor payload under Package/.'
        PackageType = 'Repository package semantics: App, Script, Font, Certificate or Driver. App and Script execute Package/Install.ps1; Font, Certificate and Driver use dedicated OSDApps runtimes and do not require Install.ps1.'
        RepositoryPath = 'Local repository root containing catalog.json and Apps; not a remote URL or deployment target.'
        SuccessCodes = 'App/Script installer exit codes treated as success. Default accepts 0 and 3010. Dedicated Font, Certificate and Driver runtimes use fixed result semantics.'
    }
    Commands = @{
        'Add-OSDAppRegistryKey' = @{
            Synopsis = 'Stage a registry key change without writing to the preparation PC or WinPE registry.'
            Description = 'Adds or replaces an operation in one local RegistrySettings Script package. SetupComplete creates missing keys, preserves unrelated values and verifies every change by read-back. No view switch means the runtime host default. No external repository, download, registry ACL changes or profile loading is required.'
            Environment = 'WinPE after OSDCloud has applied Windows. Execution happens later in full Windows under SetupComplete.'
            Output = 'OSDApps.StagedApp with OperationCount. One RegistrySettings queue entry represents all registry operations; staging is not execution proof.'
            Parameters = @{
                Path = 'Absolute HKLM, HKCR or loaded HKU path. HKCR explicitly targets machine SOFTWARE\Classes. Missing child keys are created at runtime. HKCU, HKCC and explicit WOW6432Node are rejected.'
                Registry32 = 'Use the explicit 32-bit registry view during SetupComplete. Mutually exclusive with Registry64.'
                Registry64 = 'Use the explicit 64-bit registry view during SetupComplete. Rejected on 32-bit Windows. Mutually exclusive with Registry32.'
            }
            Examples = @(@{ Code = 'Add-OSDAppRegistryKey -Path ''HKLM:\SOFTWARE\OSDApps\Tests\RegistryStaging\Level1\Level2'' -Registry64'; Remarks = 'Stage a deep machine registry path in the explicit 64-bit view.' })
            Link = 'docs/registry-staging.md'
        }
        'Add-OSDAppRegistryValue' = @{
            Synopsis = 'Stage a registry value change without writing to the preparation PC or WinPE registry.'
            Description = 'Adds or replaces an operation in one local RegistrySettings Script package. SetupComplete creates missing keys, preserves unrelated values and verifies every change by read-back. No view switch means the runtime host default. No external repository, download, registry ACL changes or profile loading is required.'
            Environment = 'WinPE after OSDCloud has applied Windows. Execution happens later in full Windows under SetupComplete.'
            Output = 'OSDApps.StagedApp with OperationCount. One RegistrySettings queue entry represents all registry operations; staging is not execution proof.'
            Parameters = @{
                Path = 'Absolute HKLM, HKCR or loaded HKU path. HKCR explicitly targets machine SOFTWARE\Classes. Missing child keys are created at runtime. HKCU, HKCC and explicit WOW6432Node are rejected.'
                Registry32 = 'Use the explicit 32-bit registry view during SetupComplete. Mutually exclusive with Registry64.'
                Registry64 = 'Use the explicit 64-bit registry view during SetupComplete. Rejected on 32-bit Windows. Mutually exclusive with Registry32.'
                Name = 'Registry value name. An empty string selects the unnamed default value.'
                Type = 'Explicit registry data type: String, ExpandString, MultiString, Binary, DWord or QWord.'
                Value = 'Literal registry data. Byte arrays for Binary, string arrays for MultiString, strings or whole integers for numeric types. No text is executed as code.'
            }
            Examples = @(@{ Code = 'Add-OSDAppRegistryValue -Path ''HKLM:\SOFTWARE\OSDApps\Tests\RegistryStaging\Level1\Level2'' -Registry64 -Name ''Marker'' -Type String -Value ''CreatedIn64BitView'''; Remarks = 'Stage a deep machine registry path in the explicit 64-bit view.' })
            Link = 'docs/registry-staging.md'
        }
        'Add-OSDAppMicrosoftCompanyPortal' = @{
            Synopsis = 'Stage the Microsoft Company Portal offline Preinstall Kit for Windows provisioning.'
            Description = 'Stages the Microsoft-supplied appbundle, offline license and five matching dependencies from a locally prepared OSDCloud cache. SetupComplete provisions the package for newly created users; it does not directly deploy into an existing signed-in user session.'
            Environment = 'WinPE after OSDCloud has applied Windows, with the pre-prepared OSDCloud USB cache.'
            Output = 'OSDApps.StagedApp with target, selected architecture and preinstall kit version. Staging does not prove provisioning succeeded.'
            Parameters = @{}
            Examples = @(@{ Code = 'Add-OSDAppMicrosoftCompanyPortal -Architecture x64'; Remarks = 'Stage the x64 package from the prepared offline USB cache.' })
            Link = 'docs/microsoft-company-portal.md'
        }
        'Sync-OSDAppMicrosoftCompanyPortal' = @{
            Synopsis = 'Prepare Microsoft Company Portal from the official offline Preinstall Kit.'
            Description = 'Downloads the official Microsoft Preinstall Kit by default. Optionally accepts a local official ZIP through -KitPath. Retains the original bundle, license and dependency filenames, records SHA-256 hashes and exact filename metadata, and transactionally updates the USB cache. WinPE stages prepared content; SetupComplete provisions it without a network download.'
            Environment = 'Full Windows preparation machine with the OSDCloud USB connected; internet access for automatic download, or a local official kit.'
            Output = 'Cache preparation record including selected architecture, bundle version and target cache path.'
            Parameters = @{ KitPath = 'Optional path to an official Microsoft kit ZIP. Omit this parameter for automatic Microsoft download.' }
            Examples = @(@{ Code = 'Sync-OSDAppMicrosoftCompanyPortal -Architecture x64'; Remarks = 'Download the official Microsoft kit and prepare the x64 cache. Supply -KitPath only to use a local official ZIP.' })
            Link = 'docs/microsoft-company-portal.md'
        }
        'Add-OSDAppCMTraceOpen' = @{
            Synopsis = 'Stage a signed CMTrace Open MSI for setup before Windows OOBE.'
            Description = 'Copies a previously synchronized, SHA-256-verified CMTrace Open MSI from the USB cache to the offline Windows installation and schedules the vendor MSI through the existing SetupComplete runner. Optionally enforces managed update-check settings.'
            Environment = 'WinPE after OSDCloud has applied Windows, with a populated OSDCloud USB cache.'
            Output = 'OSDApps.StagedApp containing the selected version and target Windows root. Staging does not establish installation success.'
            Parameters = @{ DisableUpdateChecks = 'When true, install with DISABLEUPDATECHECKS=1 so managed devices do not automatically check for in-app updates.' }
            Examples = @(@{ Code = 'Add-OSDAppCMTraceOpen -Architecture x64 -DisableUpdateChecks $true'; Remarks = 'Stage the cached signed x64 MSI and disable vendor update checks for managed deployment.' })
            Link = 'docs/cmtrace-open.md'
        }
        'Sync-OSDAppCMTraceOpen' = @{
            Synopsis = 'Synchronize the latest stable signed CMTrace Open MSI to the OSDCloud USB cache.'
            Description = 'Queries the official GitHub stable release, selects the architecture-specific MSI, checks the GitHub-published SHA-256 and Windows Authenticode signature, and transactionally replaces a compatible USB cache variant.'
            Environment = 'Full Windows preparation machine with internet access and a writable OSDCloud USB cache.'
            Output = 'Built-in cache record including architecture, version and the updated cache location.'
            Parameters = @{}
            Examples = @(@{ Code = 'Sync-OSDAppCMTraceOpen -Architecture x64'; Remarks = 'Download and integrity-verify the current stable x64 MSI from the official project release.' })
            Link = 'docs/cmtrace-open.md'
        }
        'Add-OSDAppCertificate' = @{
            Synopsis = 'Stage public CA certificates for machine-wide import during SetupComplete.'
            Description = 'Stages a repository Certificate package by Id, using its manifest destination, or accepts individual DER or PEM X.509 certificates in .cer or .crt files. Explicitly selects LocalMachine Root or CA. Duplicate thumbprint/store pairs are staged once; certificates already present are reported without replacement. Private keys and certificate bundles are rejected.'
            Environment = 'WinPE after applying Windows; SetupComplete imports certificates once as SYSTEM.'
            Output = 'A staged repository package summary, or a built-in Script summary with subjects, thumbprints, target stores and operation count.'
            Parameters = @{
                Path = 'One or more local .cer or .crt files, each containing one public CA certificate without a private key.'
                Id = 'Canonical repository Certificate package Id. The destination comes from CertificateStore in its manifest.'
                SkipCacheRefresh = 'Use the existing USB cache without refreshing it from the repository.'
                Store = 'Required destination under LocalMachine: Root for trusted roots or CA for intermediate certification authorities. No automatic trust-store selection.'
            }
            Examples = @(@{ Code = 'Add-OSDAppCertificate -Path ''E:\OSDApps-TestData\Certificates\root.cer'' -Store Root'; Remarks = 'Stage an explicitly selected public root CA for machine-wide trust in the deployed Windows installation.' })
            Link = 'docs/certificate-staging.md'
        }
        'Add-OSDAppWiFiProfile' = @{
            Synopsis = 'Stage Wi-Fi profiles from parameters or XML for all users during SetupComplete.'
            Description = 'Accepts WPA2-Personal, WPA3-Personal and open WLAN XML exports. Repeated profile names replace prior staged definitions. Preserves connection mode and updates existing profiles. Credential-bearing staging is restricted to SYSTEM/Administrators and consumed after one runtime attempt, even with CleanupMode Never.'
            Environment = 'WinPE after applying Windows; the runtime requires a working WLAN driver and service in full Windows.'
            Output = 'A staged built-in Script summary containing profile names and operation count, without XML or shared keys.'
            Parameters = @{
                Path = 'One or more local WLAN XML exports. Personal profiles must be exported with key=clear. Never upload these credential-bearing files.'
                SSID = 'Network name, encoded as 1 to 32 UTF-8 bytes. Mutually exclusive with Path; XML is generated internally.'
                Security = 'Explicit network security: WPA2Personal (WPA2PSK/AES), WPA3Personal (WPA3SAE/AES), or Open (open/none).'
                Password = 'Personal-network passphrase: 8 to 63 printable ASCII characters, as a plain string or SecureString. Required for personal networks and forbidden for Open. A hardcoded value remains readable in your script.'
                ProfileName = 'Optional Windows profile name, defaulting to SSID. Repeated case-sensitive names replace previously staged definitions.'
                ConnectionMode = 'Auto (default) or Manual. Controls the generated profile connection mode; staging does not initiate a connection.'
                Hidden = 'Set nonBroadcast=true in the generated profile for a hidden network. Defaults to false.'
            }
            Examples = @(@{ Code = 'Add-OSDAppWiFiProfile -SSID ''DeploymentWiFi'' -Security WPA2Personal -Password ''ExampleOnly123!'''; Remarks = 'Generate a profile without prompts or an XML input file. The example password is fictitious.' }, @{ Code = 'Add-OSDAppWiFiProfile -Path ''E:\OSDApps-TestData\WiFi\profile.xml'''; Remarks = 'Stage a local profile export using automatic offline Windows discovery.' })
            Link = 'docs/wifi-staging.md'
        }
        'Add-OSDAppWindowsFeature' = @{
            Parameters = @{
                Enable = 'Windows optional feature names to enable. Names are passed to Windows servicing without OSDApps autocomplete or a maintained feature catalog.'
                Disable = 'Windows optional feature names to disable. A feature cannot appear in both Enable and Disable in the same call.'
            }
            Synopsis = 'Stage declarative Windows optional feature enable/disable operations.'
            Description = 'Stages one OSDApps-owned built-in Script that applies Windows optional feature operations during SetupComplete. Operations are processed independently; invalid or unavailable feature names are reported as failures without preventing later operations from being attempted. Native Windows servicing runs with NoRestart. OSDApps records restart-needed state but never reboots the device. Re-adding a feature replaces its earlier desired state.'
            Environment = 'WinPE after OSDCloud has applied Windows; execution happens later in full Windows under SYSTEM.'
            Output = 'OSDApps.StagedApp with the combined operation count and desired enable/disable lists.'
            Examples = @(
                @{ Code = 'Add-OSDAppWindowsFeature -Enable @(''NetFx3'',''Microsoft-Windows-Subsystem-Linux'') -Disable ''Printing-XPSServices-Features'''; Remarks = 'Stage explicit desired Windows optional feature states.' }
            )
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppWindowsInboxCleanup' = @{
            Parameters = @{
                Remove = 'Exact Windows Appx DisplayName identifiers to remove; patterns and empty selections are rejected. Required unless using -Preset Tested13.'
                Preset = 'Explicit opt-in Tested13 selection validated on a Windows 11 25H2 test image. This is not a guarantee for all Windows builds.'
                DiagnoseOnly = 'Record selected and present packages under SYSTEM without removing anything during SetupComplete.'
            }
            Synopsis = 'Stage optional built-in Windows inbox package cleanup.'
            Description = 'Copies the signed-module bundled cleanup PowerShell script and selected config to the offline Windows installation. Both files receive SHA-256 integrity metadata in DeviceManifest.json and are validated before SetupComplete. During first boot, SYSTEM removes provisioned packages and user registrations, verifies they are absent, and writes dedicated logs and per-package results. No cloud repository or USB cache is required. Protected packages are skipped; failures return non-zero. No removal is performed merely by importing OSDApps.'
            Environment = 'WinPE after OSDCloud has applied Windows; operation runs later in SetupComplete under SYSTEM.'
            Output = 'OSDApps.StagedApp with selected package count. Staging is not proof of removal.'
            Examples = @(
                @{ Code = 'Add-OSDAppWindowsInboxCleanup -Preset Tested13'; Remarks = 'Stage the explicit previously tested set.' },
                @{ Code = 'Add-OSDAppWindowsInboxCleanup -Remove @(''Microsoft.BingWeather'',''Microsoft.MicrosoftSolitaireCollection'') -DiagnoseOnly'; Remarks = 'Stage a non-destructive diagnostic run.' }
            )
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppVisualCRedist' = @{
            Parameters = @{ Architecture = 'Required single package architecture: x86 or x64. No default and no combined selection.' }
            Synopsis = 'Add Microsoft runtime prerequisites.'
            Description = 'Specify one architecture explicitly: x86 or x64. DotNetRuntime defaults to Desktop and channel 10.0; choose Runtime for the standalone runtime. Only supported stable .NET channels are offered; expired channels cannot use cached fallback. Each architecture, runtime type and channel has a separate cache and deployment identity. Downloads require Microsoft Authenticode; .NET also requires the official release SHA-512. Existing suitable installed versions are retained. No SDK, ASP.NET Core or legacy .NET Framework is installed.'
            Environment = 'WinPE after applying Windows.'
            Output = 'OSDApps.StagedApp.'
            Examples = @(@{ Code = 'Add-OSDAppVisualCRedist -Architecture x64'; Remarks = 'Select x64 explicitly.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppVisualCRedist' = @{
            Parameters = @{ Architecture = 'Required single package architecture: x86 or x64. No default and no combined selection.' }
            Synopsis = 'Sync Microsoft runtime prerequisites.'
            Description = 'Specify one architecture explicitly: x86 or x64. DotNetRuntime defaults to Desktop and channel 10.0; choose Runtime for the standalone runtime. Only supported stable .NET channels are offered; expired channels cannot use cached fallback. Each architecture, runtime type and channel has a separate cache and deployment identity. Downloads require Microsoft Authenticode; .NET also requires the official release SHA-512. Existing suitable installed versions are retained. No SDK, ASP.NET Core or legacy .NET Framework is installed.'
            Environment = 'Full Windows preparation computer.'
            Output = 'OSDApps.BuiltInCache.'
            Examples = @(@{ Code = 'Sync-OSDAppVisualCRedist -Architecture x64'; Remarks = 'Select x64 explicitly.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppDotNetRuntime' = @{
            Parameters = @{
                Architecture = 'Required single package architecture: x86 or x64. No default and no combined selection.'
                RuntimeType = 'Runtime selects the standalone Microsoft.NETCore.App runtime. Desktop includes Microsoft.WindowsDesktop.App and the ordinary runtime. Default: Desktop.'
                Channel = 'Supported stable release channel: 8.0, 9.0 or 10.0. Default: 10.0. Selects its newest stable patch. The support deadline is enforced even offline; preview and EOL channels are rejected.'
            }
            Synopsis = 'Add Microsoft runtime prerequisites.'
            Description = 'Specify one architecture explicitly: x86 or x64. DotNetRuntime defaults to Desktop and channel 10.0; choose Runtime for the standalone runtime. Only supported stable .NET channels are offered; expired channels cannot use cached fallback. Each architecture, runtime type and channel has a separate cache and deployment identity. Downloads require Microsoft Authenticode; .NET also requires the official release SHA-512. Existing suitable installed versions are retained. No SDK, ASP.NET Core or legacy .NET Framework is installed.'
            Environment = 'WinPE after applying Windows.'
            Output = 'OSDApps.StagedApp.'
            Examples = @(@{ Code = 'Add-OSDAppDotNetRuntime -Architecture x64'; Remarks = 'Select x64 explicitly.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppDotNetRuntime' = @{
            Parameters = @{
                Architecture = 'Required single package architecture: x86 or x64. No default and no combined selection.'
                RuntimeType = 'Runtime selects the standalone Microsoft.NETCore.App runtime. Desktop includes Microsoft.WindowsDesktop.App and the ordinary runtime. Default: Desktop.'
                Channel = 'Supported stable release channel: 8.0, 9.0 or 10.0. Default: 10.0. Selects its newest stable patch. The support deadline is enforced even offline; preview and EOL channels are rejected.'
            }
            Synopsis = 'Sync Microsoft runtime prerequisites.'
            Description = 'Specify one architecture explicitly: x86 or x64. DotNetRuntime defaults to Desktop and channel 10.0; choose Runtime for the standalone runtime. Only supported stable .NET channels are offered; expired channels cannot use cached fallback. Each architecture, runtime type and channel has a separate cache and deployment identity. Downloads require Microsoft Authenticode; .NET also requires the official release SHA-512. Existing suitable installed versions are retained. No SDK, ASP.NET Core or legacy .NET Framework is installed.'
            Environment = 'Full Windows preparation computer.'
            Output = 'OSDApps.BuiltInCache.'
            Examples = @(@{ Code = 'Sync-OSDAppDotNetRuntime -Architecture x64'; Remarks = 'Select x64 explicitly.' })
            Link = 'docs/built-in-apps.md'
        }

        'Add-OSDAppVisualStudioCode' = @{
            Synopsis = 'Stage Visual Studio Code Stable for all users before OOBE.'
            Description = 'Stages intent and any available cache. Windows PreInstall checks the official Microsoft update service for the x64 or ARM64 system installer. Validates SHA-256 and Microsoft Authenticode before reuse, promotion and execution. Uses silent Inno Setup arguments without launching the editor. No extensions or user settings are configured.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'OSDApps.StagedApp.'
            Examples = @(@{ Code = 'Add-OSDAppVisualStudioCode'; Remarks = 'Stage the x64 Stable system installer.' }, @{ Code = 'Add-OSDAppVisualStudioCode -Architecture arm64'; Remarks = 'Stage the ARM64 system installer.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppVisualStudioCode' = @{
            Synopsis = 'Synchronize a verified Visual Studio Code system-installer cache.'
            Description = 'Checks the official Stable update metadata. Reuses a matching verified generation or downloads and validates a complete candidate before replacing the active generation. Requires access to update.code.visualstudio.com and vscode.download.prss.microsoft.com. No apps are installed.'
            Environment = 'Full Windows preparation computer with cache volume attached.'
            Output = 'OSDApps.BuiltInCache with Version, Architecture and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppVisualStudioCode'; Remarks = 'Prepare or update the x64 cache.' }, @{ Code = 'Sync-OSDAppVisualStudioCode -WhatIf'; Remarks = 'Preview without downloading or changing the cache.' })
            Link = 'docs/built-in-apps.md'
        }

        'Add-OSDApp7Zip' = @{
            Synopsis = 'Stage 7Zip for silent machine-wide installation before OOBE.'
            Description = 'Stages intent and any available cache. Windows PreInstall checks the latest stable official ip7z/7zip release and validates its SHA-256, size and PE architecture. Runner rechecks the staged hash before executing the official EXE with /S. Does not change file associations or install on the preparation computer.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'OSDApps.StagedApp.'
            Examples = @(@{ Code = 'Add-OSDApp7Zip'; Remarks = 'Stage x64 7Zip; acquisition is deferred to Windows.' }, @{ Code = 'Add-OSDApp7Zip -Architecture arm64'; Remarks = 'Stage the native ARM64 installer.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDApp7Zip' = @{
            Synopsis = 'Synchronize a validated 7Zip generation on the configured cache volume.'
            Description = 'Checks the latest stable official GitHub release. Reuses a hash-valid matching generation or downloads and validates a complete candidate before replacing the active generation. Requires GitHub API and release-download access. No apps are installed.'
            Environment = 'Full Windows preparation computer with cache volume attached.'
            Output = 'OSDApps.BuiltInCache with Version, Architecture and Updated.'
            Examples = @(@{ Code = 'Sync-OSDApp7Zip'; Remarks = 'Prepare or update the x64 cache.' }, @{ Code = 'Sync-OSDApp7Zip -WhatIf'; Remarks = 'Preview without downloading or changing the cache.' })
            Link = 'docs/built-in-apps.md'
        }

        'Set-OSDAppConfiguration' = @{
            Synopsis = 'Configure OSDApps for the current PowerShell module session.'
            Description = 'Updates supplied settings only. Staging later records relevant settings in DeviceManifest.json. A different session does not automatically reuse them. This command does not install or stage apps.'
            Environment = 'Full Windows or WinPE; current module session.'
            Output = 'No output by default; PassThru returns OSDApps.Configuration.'
            Parameters = @{
                CatalogUri = 'HTTP/HTTPS repository catalog.json URL; supply $null to clear it. Built-ins do not require a repository catalog.'
                EnableBuiltIns = 'Enable or disable built-in apps and OSDApps-owned staging features for Add/discovery. Default is True.'
                EnableRepository = 'Enable or disable repository/catalog packages for Add/discovery. Default is True.'
                CleanupMode = 'OnSuccess schedules local staging cleanup after installation success; Never retains it. Failures retain source. Does not clear USB cache.'
                CacheVolumeLabel = 'Label used to find the cache volume; default configuration is OSDCloud. Does not rename or format a volume.'
                LogPath = 'Runtime log path recorded during staging. Default configuration is %ProgramData%\OSDApps\Logs\Runtime.log.'
                ResultPath = 'Machine-readable final deployment result path recorded during staging. Default configuration is %ProgramData%\OSDApps\Results\Latest.json.'
                PassThru = 'Return effective configuration after updating it.'
            }
            Examples = @(
                @{ Code = 'Set-OSDAppConfiguration -CleanupMode OnSuccess -CacheVolumeLabel ''OSDCloud'' -PassThru'; Remarks = 'Windows or WinPE: configure the session without staging.' },
                @{ Code = 'Set-OSDAppConfiguration -CatalogUri ''https://example.org/osdapps/catalog.json'''; Remarks = 'Replace the URL with your own published repository.' },
                @{ Code = 'Set-OSDAppConfiguration -EnableRepository $false'; Remarks = 'Use built-ins only for this module session.' },
                @{ Code = 'Set-OSDAppConfiguration -EnableBuiltIns $false'; Remarks = 'Use repository/catalog packages only for this module session.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Get-OSDAppConfiguration' = @{
            Synopsis = 'Read the effective session configuration.'
            Description = 'Returns CatalogUri, source enablement, CleanupMode, CacheVolumeLabel, LogPath, ResultPath and Scope. Initializes in-memory defaults when needed. Does not read a device manifest or persist configuration.'
            Environment = 'Full Windows or WinPE; current module session.'
            Output = 'OSDApps.Configuration with Scope=Session.'
            Examples = @(@{ Code = 'Get-OSDAppConfiguration | Format-List'; Remarks = 'Inspect effective settings before staging.' })
            Link = 'docs/getting-started.md'
        }
        'Get-OSDAppCatalog' = @{
            Synopsis = 'Report availability of the configured repository catalog.'
            Description = 'Reads catalog metadata over HTTP/HTTPS and reports app count and schema version when Repository is enabled. Does not download archives. No configured catalog or a read failure produces Available=False, not a detailed cause diagnosis.'
            Environment = 'Full Windows or WinPE; online lookup when configured.'
            Output = 'OSDApps.CatalogStatus object.'
            Examples = @(@{ Code = 'Get-OSDAppCatalog | Format-List'; Remarks = 'Check catalog metadata, not installed apps.' })
            Link = 'docs/repository.md'
        }
        'Get-OSDApp' = @{
            Synopsis = 'Discover built-in and repository apps.'
            Description = 'Combines built-in definitions, configured online repository and existing cache metadata. Does not synchronize or stage apps. Cached/CachedOnly describe local repository availability with/without an online match, not installation state.'
            Environment = 'Full Windows or WinPE; online discovery unless Offline is supplied or no catalog is configured.'
            Output = 'OSDApps.App objects, not installed-software inventory.'
            Parameters = @{
                Name = 'Optional canonical Id, declared repository alias or DisplayName filters; wildcards supported.'
                Offline = 'Skip online catalog and package-manifest lookup only; does not disconnect networking or control SetupComplete.'
            }
            Examples = @(
                @{ Code = 'Get-OSDApp -Offline'; Remarks = 'Read locally known apps without repository requests.' },
                @{ Code = 'Get-OSDApp -Name ''*Firefox*'''; Remarks = 'Filter by Id or display name.' }
            )
            Link = 'docs/viewer.md'
        }
        'Get-OSDAppCache' = @{
            Synopsis = 'Inspect the detected app cache without changing it.'
            Description = 'Lists repository ZIP and built-in CacheInfo entries. Repository Valid means matching archive hash; built-in Valid means required files present. SignatureStatus is separate. Missing media returns no entries. Does not refresh or install packages.'
            Environment = 'Full Windows or WinPE; version/signature inspection has reduced capability in WinPE.'
            Output = 'OSDApps.CacheEntry objects with variant, size, validity and optional signature details.'
            Parameters = @{
                Name = 'Optional Id wildcard filters; does not match DisplayName.'
                ResolveVersions = 'Inspect supported existing packages for exact versions on full Windows. WinPE uses recorded metadata. Does not write CacheInfo or download.'
                VerifySignatures = 'Opt in to MSI/EXE Authenticode and expected-publisher inspection. May use certificate/revocation networking. Office checks setup.exe only; Teams checks bootstrapper only. Adobe and repository ZIPs are not assessed by this path. WinPE reports unavailability.'
                CachePath = 'Explicit OSDApps cache root to inspect instead of auto-detecting a volume labeled OSDCloud. The directory must already exist.'
            }
            Examples = @(
                @{ Code = 'Get-OSDAppCache'; Remarks = 'Inventory with repository hashes but no requested signature inspection.' },
                @{ Code = 'Get-OSDAppCache -ResolveVersions -VerifySignatures | Select-Object Id, Version, Valid, SignatureStatus, SignatureScope'; Remarks = 'Full Windows: independently inspect versions, integrity and supported signatures.' }
            )
            Link = 'docs/viewer.md'
        }
        'Get-OSDAppCacheHealth' = @{
            Synopsis = 'Compare cache contents with desired state and classify cleanup work.'
            Description = 'Returns one read-only health plan for repository and built-in cache content. Repository entries are classified as Active, Pinned, Obsolete, Orphaned, Renamed, Incomplete or Corrupt. It verifies recorded SHA-256 values but never downloads, repairs or deletes files.'
            Environment = 'Full Windows or WinPE with an accessible cache; desired-state lookup is optional and can be disabled with Offline.'
            Output = 'One OSDApps.CacheHealth object with CatalogError/CacheCatalogError diagnostics, aggregate counts, removable size and detailed OSDApps.CacheHealthEntry records in Entries.'
            Parameters = @{
                CachePath = 'Explicit OSDApps cache root to inspect instead of auto-detecting a volume labeled OSDCloud. A missing path returns CacheAvailable=False.'
                CatalogUri = 'Explicit HTTP/HTTPS root catalog used as desired repository state. Cannot be combined with CatalogPath or Offline.'
                CatalogPath = 'Explicit local catalog.json used as desired repository state. Cannot be combined with CatalogUri or Offline.'
                Offline = 'Do not query the configured repository catalog. Locally cataloged packages can still be Active when their recorded SHA-256 passes.'
                Architecture = 'Desired repository target architecture: x64 or arm64. Defaults to the host architecture for desired-state comparison. Offline inspection does not select variants.'
                PinnedId = 'Repository cache Ids intentionally retained outside desired state. A pin does not make missing, corrupt or renamed content healthy.'
            }
            Examples = @(
                @{ Code = 'Get-OSDAppCacheHealth -Offline | Select-Object Healthy, ActiveCount, CorruptCount'; Remarks = 'Inspect local integrity without any repository request.' },
                @{ Code = '$health = Get-OSDAppCacheHealth -CatalogPath ''C:\Work\Repository\catalog.json'' -Architecture x64; $health.Entries | Where-Object Action -ne ''None'''; Remarks = 'Preview desired-state differences from a local repository before pruning.' }
            )
            Link = 'docs/repository.md'
        }
        'Get-OSDAppDeploymentResult' = @{
            Synopsis = 'Read the latest machine-readable SetupComplete deployment result.'
            Description = 'Reads and minimally validates the JSON written atomically by the standalone one-shot runner. It reports PreInstall context, succeeded/failed/skipped counts and per-app outcomes; it does not retry deployment or infer licensing, sign-in or later app health.'
            Environment = 'Full Windows after or during SetupComplete; any host with access to a copied result file can use Path.'
            Output = 'OSDApps.DeploymentResult with status, timing, PreInstall context and app results.'
            Parameters = @{
                Path = 'Optional explicit result JSON path. Omit it to use the current session ResultPath configuration.'
            }
            Examples = @(
                @{ Code = 'Get-OSDAppDeploymentResult | Select-Object Status, SuccessfulAppCount, FailedAppCount, SkippedAppCount'; Remarks = 'Read the configured Latest.json after first boot.' },
                @{ Code = 'Get-OSDAppDeploymentResult -Path ''C:\Evidence\Latest.json'''; Remarks = 'Inspect a result copied from another device.' }
            )
            Link = 'docs/runtime.md'
        }
        'Test-OSDAppCache' = @{
            Synopsis = 'Summarize cache integrity and optional signature readiness.'
            Description = 'Validates repository SHA-256 and built-in payload presence, then returns one aggregate result plus entry details. Optional signature checks cover only supported MSI/EXE scope; this command does not download, repair or clear cache content.'
            Environment = 'Full Windows or WinPE; signature inspection is incomplete in WinPE and can require certificate/revocation networking.'
            Output = 'One OSDApps.CacheValidation object with counts, Entries and Valid.'
            Parameters = @{
                Name = 'Optional Id wildcard filters applied before the aggregate status is calculated.'
                ResolveVersions = 'Inspect supported cached packages for exact versions on full Windows without modifying cache metadata.'
                VerifySignatures = 'Require all supported, signable cache candidates in the result to pass expected-publisher validation. Non-signable formats remain explicitly outside this scope.'
                CachePath = 'Explicit OSDApps cache root to validate instead of auto-detecting a volume labeled OSDCloud. A missing path returns CacheAvailable=False.'
            }
            Examples = @(
                @{ Code = '$cache = Test-OSDAppCache -VerifySignatures; $cache.Valid'; Remarks = 'Full Windows: validate payloads and supported signatures.' },
                @{ Code = 'Test-OSDAppCache -CachePath ''E:\OSDApps'' | Select-Object Valid, EntryCount, InvalidEntryCount'; Remarks = 'Validate a known cache root directly.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Test-OSDAppDeployment' = @{
            Synopsis = 'Preflight staged OSDApps deployment intent before reboot.'
            Description = 'Validates DeviceManifest.json, queue identity, SetupComplete integration, staged runtime version, repository hashes, built-in definitions and optional complete offline payload readiness. It does not install apps or contact vendors.'
            Environment = 'WinPE after all Add commands and before reboot; can also inspect a mounted offline Windows tree.'
            Output = 'One OSDApps.DeploymentValidation object with required checks and per-app readiness.'
            Parameters = @{
                RequireOfflineReady = 'Fail validation unless every repository and built-in payload required by the queue is already staged locally. Alias: RequireCache.'
                MinimumFreeSpaceGB = 'Optional minimum free space required on the offline Windows volume. Zero records available space without enforcing a threshold.'
                ThrowOnFailure = 'Throw one aggregate terminating error when a required check fails instead of returning only Valid=False.'
            }
            Examples = @(
                @{ Code = 'Test-OSDAppDeployment -WindowsPath ''C:\'' | Format-List Valid, OfflineReady, NetworkRequired'; Remarks = 'WinPE: preflight a deployment that may acquire built-ins online.' },
                @{ Code = 'Test-OSDAppDeployment -WindowsPath ''C:\'' -RequireOfflineReady -ThrowOnFailure'; Remarks = 'Stop the workflow unless all queued payloads are local.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Show-OSDAppUI' = @{
            Synopsis = 'Open the read-only OSDApps Viewer.'
            Description = 'Displays staging, apps, cache and logs without changing manifest, cache or configuration. A configured repository is read unless Offline is supplied. Supported signatures are checked by default on full Windows. No app installation, staging or removal controls exist.'
            Environment = 'STA PowerShell with Windows Forms on full Windows or provisioned WinPE. Full Windows otherwise inspects its current system root.'
            Output = 'Interactive window, no deployment-result objects. Staged is not installed.'
            Parameters = @{
                WindowsPath = 'Windows volume root to inspect, not its Windows subdirectory. Cannot combine with TestMode. WinPE otherwise discovers a target; full Windows uses its system drive.'
                Offline = 'Skip repository lookup only. Optional, not required for read-only behavior, not a network detector; signature checks stay enabled.'
                PreviewOnly = 'Legacy compatibility parameter. Viewer is always read-only; this does not add separate preview behavior.'
                TestMode = 'Inspect the existing isolated TEMP\OSDApps-GUI-Staging-Test folder. Does not create it. Intended for full-Windows tests, not ordinary WinPE deployment.'
                SkipSignatureVerification = 'Skip Viewer signature inspection, not deployment enforcement. Combine with Offline to suppress both catalog and signature requests by the Viewer.'
            }
            Examples = @(
                @{ Code = 'Show-OSDAppUI'; Remarks = 'STA: inspect local state and any configured online catalog.' },
                @{ Code = 'Show-OSDAppUI -Offline'; Remarks = 'Inspect locally; signature inspection remains enabled on full Windows.' },
                @{ Code = 'Show-OSDAppUI -WindowsPath ''D:\'' -Offline'; Remarks = 'Replace D:\ with your intended prepared Windows volume.' }
            )
            Link = 'docs/viewer.md'
        }
        'Add-OSDApp' = @{
            Synopsis = 'Synchronize and stage repository apps for SetupComplete.'
            Description = 'Resolves exact Ids, validates SHA-256 and updates local payloads, ordered device manifest and OSDApps SetupComplete blocks. May fall back only when all requested cache entries are valid. Without USB, uses target-local repository cache. Built-ins require dedicated Add commands. Re-adding an Id moves it to the end without duplication.'
            Environment = 'Intended for WinPE after Windows image app and before first boot. Do not target the running preparation PC.'
            Output = 'OSDApps.StagedApp objects; not installation proof.'
            Parameters = @{
                Name = 'Exact canonical repository Ids or declared retired aliases, with pipeline support. Built-in Ids and wildcard selections are not supported here.'
                SkipCacheRefresh = 'Use existing repository cache only; all requested archives must pass SHA-256. Does not change built-in acquisition.'
            }
            Examples = @(
                @{ Code = 'Add-OSDApp -Name ''ExampleApp'' -WindowsPath ''C:\'' -WhatIf'; Remarks = 'WinPE: preview with your own repository Id/target, without download or staging.' },
                @{ Code = 'Add-OSDApp -Name ''ExampleApp'' -WindowsPath ''C:\'' -SkipCacheRefresh'; Remarks = 'WinPE: stage an existing valid cached package.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Add-OSDAppDriver' = @{
            Synopsis = 'Stage a repository driver ZIP for one-shot import during SetupComplete.'
            Description = 'Requires PackageType Driver and reuses repository synchronization, USB caching and SHA-256 verification. Keeps the complete vendor directory structure. SetupComplete adds each INF to the Driver Store, then asks PnPUtil to apply it to matching devices. Windows selects applicable drivers. No forced reboot, vendor detection, scheduled retry or later remediation.'
            Environment = 'WinPE after applying Windows for staging; full Windows SetupComplete as SYSTEM for driver import.'
            Output = 'OSDApps.StagedApp with the repository package and staging paths. Runtime writes Driver-Id-Result.json with per-INF command output, exit codes, store/device outcomes and reboot requirements.'
            Parameters = @{
                Id = 'Canonical Id of a repository package classified as Driver.'
                WindowsPath = 'Optional offline Windows volume root; resolved automatically when omitted.'
                SkipCacheRefresh = 'Stage the existing SHA-256-validated USB package without online discovery or repository synchronization.'
            }
            Examples = @(
                @{ Code = 'Add-OSDAppDriver -Id ''WorkstationDrivers'''; Remarks = 'Stage the selected complete driver package for the deployed Windows installation.' },
                @{ Code = 'Add-OSDAppDriver -Id ''WorkstationDrivers'' -SkipCacheRefresh'; Remarks = 'Use the driver ZIP already prepared in the USB cache.' }
            )
            Link = 'docs/driver-packages.md'
        }
        'Add-OSDAppFont' = @{
            Synopsis = 'Stage a repository Font package for machine-wide installation.'
            Description = 'Requires a repository package classified as Font, then reuses the normal catalog, cache, SHA-256 and offline staging pipeline. SetupComplete extracts the package and installs supported TTF/OTF files machine-wide; no package Install.ps1 is executed for Font packages.'
            Environment = 'WinPE after OSDCloud has applied Windows, with a configured catalog or a valid existing repository cache.'
            Output = 'OSDApps.StagedApp for the selected repository Font package; staging is not installation proof.'
            Parameters = @{
                Id = 'Exact canonical repository Id of a package classified as Font.'
                SkipCacheRefresh = 'Use existing repository cache only; the selected Font archive must already pass repository SHA-256 validation.'
            }
            Examples = @(
                @{ Code = 'Add-OSDAppFont -Id ''CorporateFonts'''; Remarks = 'Resolve and stage the Font package through the configured repository.' },
                @{ Code = 'Add-OSDAppFont -Id ''CorporateFonts'' -SkipCacheRefresh'; Remarks = 'Stage only from an existing validated repository cache.' }
            )
            Link = 'docs/repository.md'
        }
        'Remove-OSDAppStaging' = @{
            Synopsis = 'Remove apps from pending OSDApps staging.'
            Description = 'Removes selected local app files and manifest entries, not installed apps or USB cache. Removing the last app removes only owned SetupComplete blocks/runtime scripts. Malformed SetupComplete blocks stop the change.'
            Environment = 'WinPE for real target removal; full Windows requires TestMode and only touches the isolated TEMP target.'
            Output = 'OSDApps.UnstagedApps with Removed, Remaining and Changed.'
            Parameters = @{
                Name = 'Exact staged app Ids; no wildcard expansion.'
                WindowsPath = 'WinPE offline Windows volume root. Cannot combine with TestMode.'
                TestMode = 'Full Windows only: remove staging in the isolated TEMP test folder, not active Windows.'
            }
            Examples = @(
                @{ Code = 'Remove-OSDAppStaging -Name MicrosoftTeams -WindowsPath ''C:\'' -WhatIf'; Remarks = 'WinPE: preview without removing USB content.' },
                @{ Code = 'Remove-OSDAppStaging -Name MicrosoftTeams -TestMode -WhatIf'; Remarks = 'Full Windows: preview only in the isolated test target.' }
            )
            Link = 'docs/viewer.md'
        }
        'Sync-OSDAppRepository' = @{
            Synopsis = 'Synchronize repository packages into the configured cache volume.'
            Description = 'Requires CatalogUri and cache media. Resolves exactly one compatible package per canonical Id and validates every new archive before committing. Prune reconciles the complete catalog as one transaction, removing renamed, obsolete and orphaned folders only after replacements validate; rollback restores the prior cache when commit fails. Does not write device staging or install apps.'
            Environment = 'Full Windows or WinPE; configured repository and cache required.'
            Output = 'FileInfo for resulting CacheCatalog.json.'
            Parameters = @{
                Name = 'Optional exact canonical Ids or declared aliases. Omit to synchronize all compatible catalog packages. Cannot be combined with Prune.'
                Prune = 'Reconcile the complete catalog and transactionally remove unpinned renamed, obsolete and orphaned repository folders. Preview with WhatIf.'
                Architecture = 'Repository target architecture: x64 or arm64. Defaults to the host architecture. Exact variants take precedence over any. One variant is cached per Id; changing architecture can replace that Id.'
                PinnedId = 'Canonical cached package Ids to retain outside desired state during Prune. Pins must already be valid and cannot name aliases.'
            }
            Examples = @(
                @{ Code = 'Sync-OSDAppRepository -Name ''ExampleApp'' -Architecture x64'; Remarks = 'Use your own published catalog Id or alias; may update USB cache files.' },
                @{ Code = 'Sync-OSDAppRepository -Prune -PinnedId ''LegacyApp'' -WhatIf'; Remarks = 'Preview complete desired-state reconciliation while retaining one valid legacy package.' }
            )
            Link = 'docs/repository.md'
        }
        'Clear-OSDAppCache' = @{
            Synopsis = 'Delete selected app cache content.'
            Description = 'Deletes cache, not installed apps or staging. WITHOUT A SCOPE, clears ALL repository and built-in cache content. Preview with WhatIf. Logs remain unless IncludeLogs is supplied; the clear operation may write a new Client.log.'
            Environment = 'Full Windows or WinPE with the intended cache volume attached.'
            Output = 'OSDApps.CacheClearResult with scope and removed entries.'
            Parameters = @{
                All = 'Clear repository and built-in caches. Also the default with no scope argument.'
                Repository = 'Clear repository archives and CacheCatalog.json only.'
                BuiltIn = 'Clear built-in cache only.'
                Prune = 'With BuiltIn, remove only unmanaged top-level app folders and loose files. Preserve managed app trees, links and transaction recovery content. Preview with WhatIf; inspect Review in the result.'
                Name = 'Exact safe cache Ids. Matching built-in and repository paths are both removed, including retired identities; inspect operations with WhatIf.'
                IncludeLogs = 'Also remove existing cache logs; new audit entries are written afterward.'
            }
            Examples = @(
                @{ Code = 'Clear-OSDAppCache -All -WhatIf'; Remarks = 'Preview the destructive all-cache scope.' },
                @{ Code = 'Clear-OSDAppCache -BuiltIn -Prune -WhatIf'; Remarks = 'Preview unmanaged built-in namespace cleanup while retaining current app variants and transaction recovery content.' },
                @{ Code = 'Clear-OSDAppCache -Name MicrosoftTeams -WhatIf'; Remarks = 'Preview a named entry; target staging remains separate.' }
            )
            Link = 'docs/faq.md'
        }
        'Add-OSDAppMicrosoft365Apps' = @{
            Synopsis = 'Stage Office deployment intent and available fallback files.'
            Description = 'Writes Office configuration, queue and runtime. Acquisition/install occur in SetupComplete, not during Add. Compatible complete cache supports offline use only when setup.exe passes trust checks. Custom XML replaces generated XML. Shared and device licensing cannot both be enabled.'
            Environment = 'WinPE after applying Windows, before first boot; optional populated USB cache.'
            Output = 'Staging summary, not installed Office or activation status.'
            Examples = @(@{ Code = 'Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language ''nl-nl'' -Architecture x64 -WindowsPath ''C:\'''; Remarks = 'WinPE: stage the selected Office configuration.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppMicrosoftTeams' = @{
            Synopsis = 'Stage Teams provisioning for SetupComplete.'
            Description = 'Stages MicrosoftTeams intent, available fallback and runtime integration. Does not provision Teams during Add. Runtime verifies bootstrapper and Microsoft publisher; that does not verify the full MSIX.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = 'Add-OSDAppMicrosoftTeams -Architecture x64 -WindowsPath ''C:\'''; Remarks = 'WinPE: prepare Teams on the intended Windows target.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppGoogleChromeEnterprise' = @{
            Synopsis = 'Stage Google Chrome Enterprise MSI deployment.'
            Description = 'Stages intent and existing cache when available. SetupComplete acquires/validates the local MSI and expected Google publisher before installation. Does not install on the preparation computer.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = 'Add-OSDAppGoogleChromeEnterprise -Architecture x64 -WindowsPath ''C:\'''; Remarks = 'Stage Chrome for the indicated Windows root.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppMozillaFirefoxEnterprise' = @{
            Synopsis = 'Stage a Firefox channel, architecture and language variant.'
            Description = 'Stages intent and matching cached MSI. SetupComplete verifies the Mozilla publisher and installs locally. A different cached channel or language is not the requested offline variant.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = 'Add-OSDAppMozillaFirefoxEnterprise -Channel ESR -Architecture x64 -Language en-US -WindowsPath ''C:\'''; Remarks = 'Offline deployment requires the same ESR/x64/en-US variant prepared earlier.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppZoomWorkplace' = @{
            Synopsis = 'Stage the Zoom Workplace machine-wide MSI and optional settings.'
            Description = 'Stages cached content or acquisition intent. PreInstall verifies the Zoom publisher and refreshes transactionally; the existing MSI runner installs before OOBE. This is the standard Workplace client, not Zoom Rooms or VDI.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary; not installation proof.'
            Parameters = @{
                NoDesktopShortcut = 'Prevent the Zoom desktop shortcut by writing zNoDesktopShortCut=True. Omit to preserve the vendor default.'
                SsoHost = 'Optional Zoom vanity host without scheme or path, passed as zSSOHost. Does not sign in a user.'
                ZConfig = 'Hashtable of enforced Zoom settings. Boolean values become 1/0. Keys and command-line syntax are validated; vendor support and effective behavior require testing. No secrets.'
                ZRecommend = 'Hashtable of recommended Zoom defaults that users may change. Same validation as ZConfig; enforced ZConfig takes precedence.'
            }
            Examples = @(
                @{ Code = 'Add-OSDAppZoomWorkplace'; Remarks = 'Stage the x64 standard Workplace client with vendor defaults.' },
                @{ Code = 'Add-OSDAppZoomWorkplace -NoDesktopShortcut -ZConfig @{ DisableZoomOnboarding = $true }'; Remarks = 'Disable the desktop shortcut and enforce the documented onboarding setting.' }
            )
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppZoomWorkplace' = @{
            Synopsis = 'Synchronize the Zoom Workplace MSI cache transactionally.'
            Description = 'Downloads the standard Workplace MSI for the selected architecture and verifies its signature and Zoom publisher before promotion. Reuses a validated generation when remote metadata is unchanged. Does not install Zoom.'
            Environment = 'Full Windows preparation machine; not WinPE.'
            Output = 'Built-in cache summary with version, architecture and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppZoomWorkplace -Architecture x64'; Remarks = 'Prepare the optional USB flash drive cache without installing Zoom.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppCiscoWebex' = @{
            Synopsis = 'Stage Cisco Webex App MSI and per-machine settings.'
            Description = 'Stages Webex App, not separate Meetings/VDI bundles. Writes validated MSI options; SetupComplete installs after the Cisco publisher check. Sign-in hints require placeholders, not a fixed user email.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = 'Add-OSDAppCiscoWebex -Architecture x64 -AutoStartWithWindows $false -WindowsPath ''C:\'''; Remarks = 'Stage the all-users Webex app without Windows autostart.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppAdobeAcrobatUnified' = @{
            Synopsis = 'Stage Adobe Acrobat Unified ZIP deployment.'
            Description = 'Stages the ZIP or acquisition intent in the architecture-specific target. SetupComplete extracts locally and runs Adobe setup. Outer ZIP is not assessed by Authenticode; staging is not signature verification or installation proof.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = 'Add-OSDAppAdobeAcrobatUnified -Architecture x64 -InstallTimeoutMinutes 20 -WindowsPath ''C:\'''; Remarks = 'Set a 20-minute installer timeout for Acrobat.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMicrosoft365Apps' = @{
            Synopsis = 'Prepare Office cache with the Office Deployment Tool.'
            Description = 'Verifies setup.exe, writes custom/generated XML, runs ODT download and records cache metadata. Does not install Office. Signature check covers setup.exe only. Match deployment XML, channel, languages and architecture. Updates the shared Office cache directory.'
            Environment = 'Full Windows only; configured cache and vendor access. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache with version and cache path.'
            Examples = @(@{ Code = 'Sync-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language ''nl-nl'' -Architecture x64'; Remarks = 'Windows preparation machine: download selected Office content.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMicrosoftTeams' = @{
            Synopsis = 'Prepare the Teams bootstrapper and MSIX cache.'
            Description = 'Validates a new bootstrapper and Microsoft publisher. Reuses unchanged MSIX by metadata; Updated=False is not zero HTTP requests or no bootstrapper download. Explicit signature check does not cover MSIX. Architectures share the MicrosoftTeams cache directory. The cache records the exact vendor filename, SHA-256 and size. Start with a fresh cache; no old layout is migrated.'
            Environment = 'Full Windows only with configured cache and vendor access. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache; Updated describes MSIX replacement; cache metadata pins the actual vendor filename.'
            Examples = @(@{ Code = 'Sync-OSDAppMicrosoftTeams -Architecture x64'; Remarks = 'Prepare x64 content without installing Teams.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppGoogleChromeEnterprise' = @{
            Synopsis = 'Synchronize the Chrome Enterprise MSI cache.'
            Description = 'Checks vendor metadata; verifies MSI and Google publisher before replacement and revalidates existing hits. Records MSI version when available. Does not install or stage apps.'
            Environment = 'Full Windows only; configured cache required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache with version, Cached and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppGoogleChromeEnterprise -Architecture x64'; Remarks = 'Prepare or refresh x64 Chrome content.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMozillaFirefoxEnterprise' = @{
            Synopsis = 'Synchronize the selected Firefox MSI variant.'
            Description = 'Caches by channel/architecture/language, validates candidate and existing MSI publisher, and records ProductVersion when available. Does not install or stage Firefox.'
            Environment = 'Full Windows only; configured cache required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache for the requested variant.'
            Examples = @(@{ Code = 'Sync-OSDAppMozillaFirefoxEnterprise -Channel ESR -Architecture x64 -Language en-US'; Remarks = 'Prepare the same variant later requested during WinPE staging.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppCiscoWebex' = @{
            Synopsis = 'Synchronize the Cisco Webex App MSI cache.'
            Description = 'Uses the non-localized vendor MSI. Validates Authenticode/Cisco organization before cache acceptance. Does not stage MSI options or install Webex.'
            Environment = 'Full Windows only; configured cache required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache with version and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppCiscoWebex -Architecture x64'; Remarks = 'Cache the Webex App MSI on the preparation machine.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppAdobeAcrobatUnified' = @{
            Synopsis = 'Synchronize the Adobe Acrobat Unified ZIP cache.'
            Description = 'Reuses/updates the architecture-specific ZIP using vendor metadata. Can record the included patch version; not installed or base-MSI version proof. ZIP is outside explicit Authenticode checks. Does not install Acrobat.'
            Environment = 'Full Windows only; configured cache required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary.'
            Examples = @(@{ Code = 'Sync-OSDAppAdobeAcrobatUnified -Architecture x64'; Remarks = 'Populate or refresh the vendor ZIP cache.' })
            Link = 'docs/built-in-apps.md'
        }
        'New-OSDAppRepository' = @{
            Synopsis = 'Create a local static repository structure.'
            Description = 'Creates Apps and an empty catalog.json only when absent; preserves existing catalog. Does not host/upload content. Use Add-OSDAppPackage to publish packages locally.'
            Environment = 'Repository preparation machine with a writable local directory.'
            Output = 'OSDApps.Repository with root, catalog and Apps paths.'
            Parameters = @{ Path = 'Local repository directory to create/reuse. No volume formatting.' }
            Examples = @(@{ Code = 'New-OSDAppRepository -Path ''C:\Work\Repository'''; Remarks = 'Create local content; hosting remains a separate operation.' })
            Link = 'docs/repository.md'
        }
        'New-OSDAppPackage' = @{
            Synopsis = 'Build Package.zip from a local repository source folder.'
            Description = 'App and Script packages require Install.ps1 at source root. Font packages require at least one TTF/OTF file and do not require Install.ps1. Certificate packages accept only public CA .cer/.crt files. Driver packages require an INF and preserve all vendor files, including hidden files; INF applicability and signatures are checked later by Windows. After source validation, normal execution wraps files under Package/ and replaces OutputPath/Package.zip; source content is never executed.'
            Environment = 'Repository preparation machine with source and writable build/TEMP directories.'
            Output = 'OSDApps.Package with Id, Version, PackagePath and Sha256 after building; no package-success object when previewed or declined.'
            Parameters = @{
                SourcePath = 'Existing source folder. App/Script requires Install.ps1; Font requires one or more .ttf/.otf files. Driver requires at least one INF and its complete vendor payload.'
                OutputPath = 'Build directory; Package.zip may be replaced during normal execution. Do not use the only copy of an existing package.'
                PackageType = 'App, Script, Font, Certificate or Driver. Defaults to App and controls structural validation only; package source is never executed during authoring.'
            }
            Examples = @(@{ Code = 'New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath ''C:\Work\ExampleApp'' -OutputPath ''C:\Work\Build\ExampleApp'''; Remarks = 'Provide your own unattended installer script and payload.' })
            Link = 'docs/repository.md'
        }
        'Add-OSDAppPackage' = @{
            Synopsis = 'Publish an existing package into a local repository.'
            Description = 'Validates input structure and the canonical Id/alias graph before asking for destination approval. Only after approval does it copy the archive, write its manifest and update the Id/architecture catalog reference. PackageType selects App, Script, Font, Certificate or Driver semantics; Font packages use the OSDApps font runtime rather than Package/Install.ps1. Omitting Alias on an update preserves existing aliases; an explicitly empty Alias removes them. WhatIf or declined confirmation leaves the destination unchanged. Older repository source folders may remain. Does not upload or execute installers; normal publication is not transactional rollback.'
            Environment = 'Repository preparation machine with writable local repository.'
            Output = 'OSDApps.RepositoryPackage with archive SHA-256 and manifest reference after publication; no package-success object when previewed or declined.'
            Parameters = @{
                Alias = 'Optional retired Ids that resolve to this canonical Id and are eligible for renamed-cache detection. Values cannot collide with another Id or alias.'
                CertificateStore = 'Required for new Certificate packages: Root or CA under LocalMachine. Existing variants preserve their store when omitted. Invalid for other package types.'
                PackageType = 'Optional App, Script, Font, Certificate or Driver classification. New packages default to App; republishing an existing variant preserves its current type when omitted. Font uses the dedicated machine-wide font runtime.'
            }
            Examples = @(@{ Code = 'Add-OSDAppPackage -Id ConfigureWindows -DisplayName ''Configure Windows'' -Version 1.0.0 -Architecture x64 -PackageType Script -PackagePath ''C:\Work\Build\ConfigureWindows\Package.zip'' -RepositoryPath ''C:\Work\Repository'''; Remarks = 'Publish a script package using the same repository and SetupComplete runtime contract as an app.' })
            Link = 'docs/repository.md'
        }
        'Test-OSDAppPackage' = @{
            Synopsis = 'Validate repository archive structure and report SHA-256.'
            Description = 'Extracts into owned temporary storage and validates structure for the selected PackageType. App/Script require Package/Install.ps1; Font requires at least one TTF/OTF file. Certificate requires only public CA .cer/.crt files under Package/; no scripts or private keys. Driver checks are structural only: at least one INF, complete Package directory layout and no reparse points. Windows validates INF content and signatures during import. Validation never executes package content.'
            Environment = 'Preparation machine or suitable PowerShell with archive support and writable TEMP.'
            Output = 'OSDApps.PackageValidation with PackageType, structure flags, FontCount, DriverInfCount, CertificateCount, Sha256 and Valid.'
            Parameters = @{
                PackageType = 'Validate the archive as App, Script, Font, Certificate or Driver. Defaults to App.'
                CertificateStore = 'Optional Root or CA destination for Certificate validation. Without a destination, validates public CA content; Root additionally requires self-issued certificates.'
            }
            Examples = @(@{ Code = 'Test-OSDAppPackage -PackagePath ''C:\Work\Build\ExampleApp\Package.zip'' -PackageType App'; Remarks = 'Inspect an existing package using its intended semantic type.' })
            Link = 'docs/repository.md'
        }
        'Test-OSDAppRepository' = @{
            Synopsis = 'Validate local repository manifests, references and packages.'
            Description = 'Checks identity, architecture, success codes, archive definition, structure, hash and missing/duplicate/orphaned entries. Does not repair content or execute installers. Structural checks use temporary extraction.'
            Environment = 'Preparation machine with read access and writable TEMP.'
            Output = 'OSDApps.RepositoryValidation objects. Inspect each Valid result and expected app count.'
            Examples = @(@{ Code = 'Test-OSDAppRepository -RepositoryPath ''C:\Work\Repository'' | Where-Object { -not $_.Valid }'; Remarks = 'Review invalid entries. No output alone does not prove expected content is present.' })
            Link = 'docs/repository.md'
        }
    }
}
