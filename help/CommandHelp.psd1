@{
    # Build-time source for packaged Get-Help. No downloads or command execution.
    SchemaVersion = 1
    CommonParameters = @{
        WindowsPath = 'Root of the intended Windows volume, for example D:\, not D:\Windows. When omitted, deployment commands discover a Windows installation. Use deployment Add commands in WinPE after applying Windows, not on the running preparation machine.'
        Architecture = 'Package architecture. Use a variant supported by this command and matching the intended deployment. Allowed values and source defaults are included below.'
        PackageUri = 'Optional vendor-owned package URL overriding the built-in source. It does not bypass signature/publisher validation for supported MSI packages.'
        MinimumFreeSpaceGB = 'Minimum free space required on the configured cache volume before synchronization, measured using PowerShell GB units. This is a preflight threshold, not a guarantee that every download will fit.'
        InstallTimeoutMinutes = 'Maximum installer runtime in minutes during SetupComplete. This does not configure the download timeout.'
        Channel = 'Vendor release channel used for the requested content. Match the channel used to prepare an offline cache.'
        Language = 'Vendor language identifier or identifiers supported by this command. Match the language used to prepare an offline cache.'
        ProductId = 'Office product identifier used when generating the Office Deployment Tool configuration.'
        AcceptEula = 'Whether to write the vendor EULA acceptance option into the generated installation configuration. Supply a Boolean value explicitly to change the default.'
        SharedComputerLicensing = 'Generate Office shared-computer licensing configuration. Cannot be enabled together with DeviceBasedLicensing. This setting does not verify licensing entitlement or activation.'
        DeviceBasedLicensing = 'Generate Office device-based licensing configuration. Cannot be enabled together with SharedComputerLicensing. This setting does not verify licensing entitlement or activation.'
        UpdatesEnabled = 'Whether updates are enabled in generated Office XML. Supply -UpdatesEnabled $false to disable that XML setting.'
        IncludeVisio = 'Include Visio Professional in the generated Office configuration. Does not grant or verify a Visio license.'
        IncludeProject = 'Include Project Professional in the generated Office configuration. Does not grant or verify a Project license.'
        ExcludeApp = 'Office application identifiers to exclude from generated XML. Applies to generated configuration rather than replacing content in a supplied custom XML file.'
        ConfigurationXml = 'Existing custom Office XML file. Syntax is validated and the file is copied instead of generating XML from the simple options. Vendor semantic correctness and installed update-channel state are not independently validated.'
        OfficeDeploymentToolUri = 'Vendor-owned Office Deployment Tool setup.exe URL. The signed executable must match the expected Microsoft publisher; this check does not cover the entire Office data tree.'
        MicrosoftTeamsBootstrapperUri = 'Vendor-owned Teams bootstrapper URL written into deployment intent. The bootstrapper signature is checked in full Windows; Teams MSIX is outside this explicit signature check.'
        BootstrapperUri = 'Vendor-owned Teams bootstrapper URL used during cache synchronization. Authenticode and the expected Microsoft publisher remain required.'
        InstallMeetingAddin = 'Whether the Teams installation should also request the meeting add-in. This is stored in deployment intent; it does not install the add-in while staging.'
        AutoStartWithWindows = 'Generate the Cisco Webex AUTOSTART_WITH_WINDOWS MSI property.'
        PreventPreLoginUpdates = 'Generate Cisco PREVENT_PRELOGIN_UPDATES=1 when enabled.'
        EnableOutlookIntegration = 'Optional Cisco ENABLEOUTLOOKINTEGRATION property. Omission leaves the vendor default; explicit false writes 0.'
        DefaultTheme = 'Optional Cisco Webex theme. Omission preserves vendor behavior.'
        EmailHint = 'Cisco sign-in placeholder only: $userPrincipalName, $mail or $SAMAccountName. Quote the literal placeholder. Fixed user email addresses are rejected for this all-users installation.'
        AdditionalMsiProperties = 'Additional Cisco MSI NAME=VALUE pairs. Managed properties, duplicates, unsupported quotes and control characters are rejected. Prefer dedicated parameters when available.'
        Id = 'Technical repository application identifier. This identifies package metadata and paths, not a display name.'
        DisplayName = 'Human-readable repository application name displayed by discovery and the Viewer.'
        Vendor = 'Optional descriptive repository publisher metadata. This value is not a cryptographic verification result or installer argument.'
        Version = 'Repository package version written into authoring metadata and paths. Does not query or change the installed application version.'
        PackagePath = 'Path to an existing Package.zip archive. Repository archives must contain Package/Install.ps1.'
        RepositoryPath = 'Local root directory of a self-maintained repository, containing catalog.json and Apps. This is not a remote URL or deployment target.'
        SuccessCodes = 'Exit codes the repository installer treats as success. The default accepts 0 and 3010.'
    }
    Commands = @{
        'Set-OSDAppConfiguration' = @{
            Synopsis = 'Configure OSDApps for the current PowerShell module session.'
            Description = 'Updates only supplied settings. Staging later copies relevant settings into DeviceManifest.json. Importing the module in another session does not automatically reuse this configuration. No application is installed or staged by this command.'
            Environment = 'Full Windows or WinPE. Configuration affects the current module session.'
            Output = 'No output by default; with PassThru returns an OSDApps.Configuration object.'
            Parameters = @{
                CatalogUri = 'HTTP or HTTPS repository catalog.json URL. Supply $null to clear the session URL. Built-ins do not need a repository catalog.'
                CleanupMode = 'OnSuccess schedules removal of local staging after successful installation; Never retains it. Failures retain source. This does not clear the USB cache.'
                CacheVolumeLabel = 'Label used to locate the cache volume; default configuration is OSDCloud. The command does not rename or format a volume.'
                LogPath = 'Runtime log path recorded by later staging. Default configuration is %ProgramData%\OSDApps\Logs\Runtime.log.'
                PassThru = 'Return the effective configuration after updating it.'
            }
            Examples = @(
                @{ Code = "Set-OSDAppConfiguration -CleanupMode OnSuccess -CacheVolumeLabel 'OSDCloud' -PassThru"; Remarks = 'Windows or WinPE: set session defaults without staging anything.' },
                @{ Code = "Set-OSDAppConfiguration -CatalogUri 'https://example.org/osdapps/catalog.json'"; Remarks = 'Replace the example URL with your own published repository.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Get-OSDAppConfiguration' = @{
            Synopsis = 'Read the effective session configuration.'
            Description = 'Returns CatalogUri, CleanupMode, CacheVolumeLabel, LogPath and Scope. Initializes the in-memory defaults when configuration has not been set. Does not read a device manifest or persist settings to disk.'
            Environment = 'Full Windows or WinPE; current module session.'
            Output = 'OSDApps.Configuration object with Scope=Session.'
            Examples = @(@{ Code = 'Get-OSDAppConfiguration | Format-List'; Remarks = 'Inspect the session settings before staging.' })
            Link = 'docs/getting-started.md'
        }
        'Get-OSDAppCatalog' = @{
            Synopsis = 'Report availability of the configured repository catalog.'
            Description = 'Reads the configured catalog over HTTP/HTTPS and reports application count and schema version. No package archives are downloaded. When no catalog is configured or reading fails, Available is false; this is not a complete diagnostic of the cause.'
            Environment = 'Full Windows or WinPE; online catalog lookup when configured.'
            Output = 'OSDApps.CatalogStatus object.'
            Examples = @(@{ Code = 'Get-OSDAppCatalog | Format-List'; Remarks = 'Check catalog metadata, not installed applications.' })
            Link = 'docs/repository.md'
        }
        'Get-OSDApp' = @{
            Synopsis = 'Discover built-in and repository applications.'
            Description = 'Combines built-in definitions, configured online repository metadata and existing cache metadata. Does not synchronize packages or stage applications. Cached and CachedOnly describe local repository availability with or without an online catalog match, not installed state.'
            Environment = 'Full Windows or WinPE. Online discovery is used when a catalog is configured and Offline is absent.'
            Output = 'OSDApps.App objects; metadata and availability, not installed-software inventory.'
            Parameters = @{
                Name = 'Optional application Id or DisplayName filters; wildcard matching is supported.'
                Offline = 'Skip online repository catalog and package-manifest lookup. Does not disconnect networking or control SetupComplete.'
            }
            Examples = @(
                @{ Code = 'Get-OSDApp -Offline'; Remarks = 'Inspect locally known apps without repository requests.' },
                @{ Code = "Get-OSDApp -Name '*Firefox*'"; Remarks = 'Filter discovery results by Id or readable name.' }
            )
            Link = 'docs/viewer.md'
        }
        'Get-OSDAppCache' = @{
            Synopsis = 'Inspect the detected cache without changing it.'
            Description = 'Lists repository ZIP and built-in CacheInfo entries from the configured cache volume. Repository Valid means the archive hash matches metadata; built-in Valid means required files are present. SignatureStatus is a separate result. Missing cache media returns no entries. Inspection does not refresh or install packages.'
            Environment = 'Full Windows or WinPE. Version/signature inspection has reduced capability in WinPE.'
            Output = 'OSDApps.CacheEntry objects with source, version, variant, size, validity and optional signature details.'
            Parameters = @{
                Name = 'Optional Id filters with wildcard matching; does not filter on DisplayName.'
                ResolveVersions = 'Inspect supported existing cached files for exact versions on full Windows. WinPE uses saved metadata. Does not write CacheInfo or download new content.'
                VerifySignatures = 'Opt in to supported MSI/EXE Authenticode and expected-publisher inspection. Windows may perform certificate/revocation requests. Office checks setup.exe only; Teams checks the bootstrapper only. Adobe ZIP and repository ZIP are not assessed by this Authenticode path. WinPE reports unavailability.'
            }
            Examples = @(
                @{ Code = 'Get-OSDAppCache'; Remarks = 'Fast cache inventory, with repository hashes checked and no signature request.' },
                @{ Code = 'Get-OSDAppCache -ResolveVersions -VerifySignatures | Select-Object Id, Version, Valid, SignatureStatus, SignatureScope'; Remarks = 'Full Windows: inspect supported versions and signatures independently.' }
            )
            Link = 'docs/viewer.md'
        }
        'Show-OSDAppUI' = @{
            Synopsis = 'Open the read-only OSDApps Viewer.'
            Description = 'Displays device staging, app metadata, cache and existing logs. Sorting and selection do not change the manifest, cache or configuration. A configured repository is queried unless Offline is specified. Supported cached signatures are checked by default on full Windows. The Viewer never installs, adds or removes applications.'
            Environment = 'Windows with Windows Forms and an STA PowerShell session, or suitably provisioned WinPE. The current Windows root is inspected on full Windows unless another target is selected.'
            Output = 'Interactive window; no deployment result objects. Staged does not mean installed.'
            Parameters = @{
                WindowsPath = 'Explicit Windows volume root to inspect, not its Windows subdirectory. Cannot be combined with TestMode. WinPE otherwise discovers the target; full Windows otherwise uses its system drive.'
                Offline = 'Skip repository catalog lookup only. This optional switch is not required for read-only operation, does not disable signature checks and is not a network-status detector.'
                PreviewOnly = 'Legacy compatibility parameter. The current Viewer is always read-only; this switch does not add a separate preview behavior.'
                TestMode = 'Inspect the existing isolated TEMP\OSDApps-GUI-Staging-Test folder on full Windows. Does not create the folder or sample staging. Do not use it for a normal WinPE deployment.'
                SkipSignatureVerification = 'Skip Viewer signature inspection explicitly. Does not relax the checks enforced by synchronization or SetupComplete. Combine with Offline to suppress both repository lookup and signature checks by the Viewer.'
            }
            Examples = @(
                @{ Code = 'Show-OSDAppUI'; Remarks = 'STA session: inspect local state and any configured online repository.' },
                @{ Code = 'Show-OSDAppUI -Offline'; Remarks = 'Local catalog/cache/staging inspection; signature checks remain enabled on full Windows.' },
                @{ Code = "Show-OSDAppUI -WindowsPath 'D:\' -Offline"; Remarks = 'Replace D:\ with the intended prepared Windows volume.' }
            )
            Link = 'docs/viewer.md'
        }
        'Add-OSDApp' = @{
            Synopsis = 'Synchronize and stage repository applications for SetupComplete.'
            Description = 'Resolves exact repository Ids, checks SHA-256, copies payloads to the Windows target and updates the ordered manifest and OSDApps SetupComplete blocks. An existing valid cache may be used if synchronization fails. Without USB, repository caching uses the target Windows staging directory. Built-in Ids require their dedicated Add commands. Re-adding an Id moves its entry to the end without duplication.'
            Environment = 'Intended for WinPE after OSDCloud has applied Windows and before the first Windows boot. Do not target the running preparation computer.'
            Output = 'One OSDApps.StagedApp object per requested repository application; not installation evidence.'
            Parameters = @{
                Name = 'Exact repository application Ids (alias Id), including pipeline input. Built-in Ids are rejected. Wildcards are not repository selection syntax.'
                SkipCacheRefresh = 'Use only the existing repository cache. All requested archives must be present and match their recorded SHA-256; this does not change built-in acquisition.'
            }
            Examples = @(
                @{ Code = "Add-OSDApp -Name 'ExampleApp' -WindowsPath 'C:\' -WhatIf"; Remarks = 'WinPE: preview without synchronization or staging. Use your own repository Id and target root.' },
                @{ Code = "Add-OSDApp -Name 'ExampleApp' -WindowsPath 'C:\' -SkipCacheRefresh"; Remarks = 'WinPE: stage an already cached and hash-valid repository package for the next Windows boot.' }
            )
            Link = 'docs/getting-started.md'
        }
        'Remove-OSDAppStaging' = @{
            Synopsis = 'Remove selected apps from pending OSDApps staging.'
            Description = 'Removes app-specific files and manifest entries, not installed software or USB cache. Removing the last app removes only OSDApps-owned SetupComplete blocks and runtime scripts; malformed SetupComplete blocks stop the change. No wildcard expansion is used for Id selection.'
            Environment = 'WinPE for a real offline Windows target. Full Windows requires TestMode and is limited to the isolated TEMP test target.'
            Output = 'OSDApps.UnstagedApps object with Removed, Remaining and Changed.'
            Parameters = @{
                Name = 'Exact application Ids currently staged for the selected target.'
                WindowsPath = 'Offline Windows volume root in WinPE. Omit when using TestMode; it cannot be combined with TestMode.'
                TestMode = 'Full Windows only: remove staging from the isolated TEMP test folder, not the active Windows installation.'
            }
            Examples = @(
                @{ Code = "Remove-OSDAppStaging -Name MicrosoftTeams -WindowsPath 'C:\' -WhatIf"; Remarks = 'WinPE: preview removal while preserving other apps and USB content.' },
                @{ Code = 'Remove-OSDAppStaging -Name MicrosoftTeams -TestMode -WhatIf'; Remarks = 'Full Windows: preview removal only in the isolated test target.' }
            )
            Link = 'docs/viewer.md'
        }
        'Sync-OSDAppRepository' = @{
            Synopsis = 'Synchronize repository packages into the configured cache volume.'
            Description = 'Requires a configured CatalogUri and a detectable cache volume. Resolves compatible packages and validates archive SHA-256 before committing the cache transaction. Does not write a device installation queue or install applications.'
            Environment = 'Full Windows or WinPE, with the configured repository and cache volume available.'
            Output = 'FileInfo for the resulting CacheCatalog.json.'
            Parameters = @{ Name = 'Optional exact repository Ids to synchronize. Omission synchronizes the applicable catalog packages.' }
            Examples = @(@{ Code = "Sync-OSDAppRepository -Name 'ExampleApp'"; Remarks = 'Use your published repository and an actual package Id; cache files may be updated.' })
            Link = 'docs/repository.md'
        }
        'Clear-OSDAppCache' = @{
            Synopsis = 'Delete selected application cache content from the configured volume.'
            Description = 'Deletes cache files, not installed applications or device staging. With no scope argument, the default scope is ALL repository and built-in caches. Inspect with WhatIf before destructive use. Logs are retained unless IncludeLogs is specified; logging the clear operation may create a new Client.log.'
            Environment = 'Full Windows or WinPE with the intended cache volume attached.'
            Output = 'OSDApps.CacheClearResult with selected scope and removed entries.'
            Parameters = @{
                All = 'Clear both repository and built-in caches. This is also the default when no scope parameter is supplied.'
                Repository = 'Clear repository archives and CacheCatalog.json only.'
                BuiltIn = 'Clear built-in cache content only.'
                Name = 'Select named cache entries instead of clearing the entire cache. Review the resolved operations with WhatIf.'
                IncludeLogs = 'Also remove existing cache log files. The operation writes new audit log entries afterward.'
            }
            Examples = @(
                @{ Code = 'Clear-OSDAppCache -All -WhatIf'; Remarks = 'Preview the destructive all-cache operation before deciding to run it.' },
                @{ Code = 'Clear-OSDAppCache -Name MicrosoftTeams -WhatIf'; Remarks = 'Preview removal of Teams cache content without touching target staging.' }
            )
            Link = 'docs/faq.md'
        }
        'Add-OSDAppMicrosoft365Apps' = @{
            Synopsis = 'Stage Microsoft 365 Apps deployment intent and available fallback files.'
            Description = 'Creates Office configuration, updates the device queue and stages the standalone runtime. Acquisition and installation happen during SetupComplete, not while adding. Complete compatible cache content can support offline deployment; setup.exe must pass the runtime signature gate. Custom XML replaces generated XML options. Shared and device licensing cannot both be enabled.'
            Environment = 'WinPE after applying Windows, before the first boot; optional populated cache volume.'
            Output = 'Staging summary, not installed Office status or activation proof.'
            Examples = @(@{ Code = "Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language 'nl-nl' -Architecture x64 -WindowsPath 'C:\'"; Remarks = 'WinPE: stage Dutch x64 Office for the indicated Windows root.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppMicrosoftTeams' = @{
            Synopsis = 'Stage Teams provisioning for SetupComplete.'
            Description = 'Adds MicrosoftTeams deployment intent, existing fallback payloads where available, and SetupComplete integration. Does not provision Teams while staging. The runtime verifies the bootstrapper and expected Microsoft organization; this does not cryptographically verify Teams MSIX.'
            Environment = 'WinPE after applying Windows, before the first boot.'
            Output = 'Staging summary with intended source and target.'
            Examples = @(@{ Code = "Add-OSDAppMicrosoftTeams -Architecture x64 -WindowsPath 'C:\'"; Remarks = 'WinPE: prepare Teams for the selected Windows target.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppGoogleChromeEnterprise' = @{
            Synopsis = 'Stage Google Chrome Enterprise MSI deployment.'
            Description = 'Adds built-in deployment intent and copies a cached MSI when available. SetupComplete acquires or validates the local MSI and requires the expected Google publisher before installation. Does not install Chrome on the preparation computer.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = "Add-OSDAppGoogleChromeEnterprise -Architecture x64 -WindowsPath 'C:\'"; Remarks = 'Stage x64 Chrome for the target Windows volume.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppMozillaFirefoxEnterprise' = @{
            Synopsis = 'Stage Firefox Enterprise for a selected channel, architecture and language.'
            Description = 'Stages intent and compatible available MSI content. The fallback cache is selected by channel, architecture and language. SetupComplete verifies the Mozilla publisher and installs locally. A different cached channel/language is not the requested offline variant.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = "Add-OSDAppMozillaFirefoxEnterprise -Channel ESR -Architecture x64 -Language en-US -WindowsPath 'C:\'"; Remarks = 'For offline deployment, prepare this same ESR/x64/en-US variant first.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppCiscoWebex' = @{
            Synopsis = 'Stage the Cisco Webex App MSI and per-machine configuration.'
            Description = 'Stages the built-in Webex App, not a separate Meetings or VDI bundle. Writes validated MSI properties and deployment intent; installation occurs during SetupComplete. Uses the expected Cisco organization for supported signature checks. Sign-in hints must be literal placeholders rather than a fixed user identity.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = "Add-OSDAppCiscoWebex -Architecture x64 -AutoStartWithWindows $false -WindowsPath 'C:\'"; Remarks = 'WinPE: prepare the per-machine Webex app without Windows autostart.' })
            Link = 'docs/built-in-apps.md'
        }
        'Add-OSDAppAdobeAcrobatUnified' = @{
            Synopsis = 'Stage Adobe Acrobat Unified ZIP deployment.'
            Description = 'Stages the vendor ZIP or acquisition intent at the architecture-specific target path. SetupComplete extracts locally and invokes Adobe setup. The outer ZIP is not assessed by the built-in MSI/EXE Authenticode path; successful staging is not signature verification or proof of installation.'
            Environment = 'WinPE after applying Windows, before first boot.'
            Output = 'Staging summary.'
            Examples = @(@{ Code = "Add-OSDAppAdobeAcrobatUnified -Architecture x64 -InstallTimeoutMinutes 20 -WindowsPath 'C:\'"; Remarks = 'WinPE: configure a 20-minute installation timeout for Acrobat.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMicrosoft365Apps' = @{
            Synopsis = 'Prepare Microsoft 365 Apps cache with the Office Deployment Tool.'
            Description = 'Downloads and verifies setup.exe, writes custom or generated Office XML, runs ODT in download mode and records cache metadata. This does not install Office. Verification covers setup.exe, not the entire Office content tree. Match the XML/channel/language/architecture used when staging. Updates the shared Office cache directory.'
            Environment = 'Full Windows only; requires the configured cache volume and vendor connectivity. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary with resolved version and cache path.'
            Examples = @(@{ Code = "Sync-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language 'nl-nl' -Architecture x64"; Remarks = 'Windows preparation machine: download the selected Office content to the cache.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMicrosoftTeams' = @{
            Synopsis = 'Prepare the Teams bootstrapper and MSIX cache on full Windows.'
            Description = 'Validates the downloaded bootstrapper and expected Microsoft publisher before use. Reuses unchanged MSIX content based on metadata; Updated=False refers to MSIX reuse, not zero HTTP requests or no bootstrapper download. The explicit signature check does not cover MSIX. Variants share the MicrosoftTeams cache directory.'
            Environment = 'Full Windows only, with the configured cache volume and vendor access. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary; Updated describes MSIX replacement.'
            Examples = @(@{ Code = 'Sync-OSDAppMicrosoftTeams -Architecture x64'; Remarks = 'Windows: populate or refresh the x64 Teams cache without installing Teams.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppGoogleChromeEnterprise' = @{
            Synopsis = 'Synchronize the Chrome Enterprise MSI cache.'
            Description = 'Checks vendor metadata, authenticates candidate MSI and expected Google publisher before replacing existing cache, and revalidates an unchanged cache hit. Records MSI ProductVersion when available. This does not install Chrome or create a device queue.'
            Environment = 'Full Windows only; configured cache volume required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary with version, Cached and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppGoogleChromeEnterprise -Architecture x64'; Remarks = 'Windows: prepare or refresh x64 Chrome MSI content.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppMozillaFirefoxEnterprise' = @{
            Synopsis = 'Synchronize the selected Firefox MSI cache variant.'
            Description = 'Caches by channel, architecture and language. Validates a new MSI and expected Mozilla publisher before cache replacement and checks existing hits again. Records MSI ProductVersion when available. No Firefox installation or device staging is performed.'
            Environment = 'Full Windows only; configured cache volume required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary for the requested variant.'
            Examples = @(@{ Code = 'Sync-OSDAppMozillaFirefoxEnterprise -Channel ESR -Architecture x64 -Language en-US'; Remarks = 'Windows: prepare the same variant later requested by the WinPE Add command.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppCiscoWebex' = @{
            Synopsis = 'Synchronize the Cisco Webex App MSI cache.'
            Description = 'Uses the vendor non-localized Webex App MSI. Verifies Windows Authenticode and the expected Cisco organization before accepting downloads or reused cache. Does not stage application-specific MSI settings or install Webex.'
            Environment = 'Full Windows only; configured cache volume required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary including version and Updated.'
            Examples = @(@{ Code = 'Sync-OSDAppCiscoWebex -Architecture x64'; Remarks = 'Windows: cache the Webex App MSI.' })
            Link = 'docs/built-in-apps.md'
        }
        'Sync-OSDAppAdobeAcrobatUnified' = @{
            Synopsis = 'Synchronize the Adobe Acrobat Unified ZIP cache.'
            Description = 'Uses vendor metadata to reuse or update the architecture-specific ZIP. Can record the included patch version from setup.ini; this is not proof of the installed or base-MSI version. Adobe ZIP is outside the explicit Authenticode check. Does not install Acrobat.'
            Environment = 'Full Windows only; configured cache volume required. WinPE is rejected.'
            Output = 'OSDApps.BuiltInCache summary.'
            Examples = @(@{ Code = 'Sync-OSDAppAdobeAcrobatUnified -Architecture x64'; Remarks = 'Windows: populate or refresh the vendor ZIP cache.' })
            Link = 'docs/built-in-apps.md'
        }
        'New-OSDAppRepository' = @{
            Synopsis = 'Create a local static repository structure.'
            Description = 'Creates Apps and, when absent, an empty catalog.json. Does not upload content or create a hosted service. An existing catalog is preserved. Use Add-OSDAppPackage to publish locally authored packages into the structure.'
            Environment = 'Repository preparation machine with write access to the selected local directory.'
            Output = 'OSDApps.Repository object with root, catalog and Apps paths.'
            Parameters = @{ Path = 'Local repository directory to create or reuse. No disk formatting is performed.' }
            Examples = @(@{ Code = "New-OSDAppRepository -Path 'C:\Work\Repository'"; Remarks = 'Create local content; host it separately using your own publishing process.' })
            Link = 'docs/repository.md'
        }
        'New-OSDAppPackage' = @{
            Synopsis = 'Build Package.zip from a local installer source folder.'
            Description = 'Requires Install.ps1 at the source root. Wraps source in Package/ and writes Package.zip to OutputPath, replacing an existing output ZIP. Uses a temporary work directory and cleans it afterward. Does not execute Install.ps1 or establish that the installer is safe. Use a disposable build output; the current implementation can remove an existing output before a WhatIf decision.'
            Environment = 'Repository preparation machine. Requires local source and writable build/temp directories.'
            Output = 'OSDApps.Package object with Id, Version, PackagePath and Sha256.'
            Parameters = @{
                SourcePath = 'Existing source folder containing Install.ps1 and any required payload.'
                OutputPath = 'Build output directory. Package.zip within this directory may be replaced; do not use the only copy of an existing package.'
            }
            Examples = @(@{ Code = "New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath 'C:\Work\ExampleApp' -OutputPath 'C:\Work\Build\ExampleApp'"; Remarks = 'Replace the example source with your own unattended installer script and payload.' })
            Link = 'docs/repository.md'
        }
        'Add-OSDAppPackage' = @{
            Synopsis = 'Publish an existing package into a local static repository.'
            Description = 'Validates Package/Install.ps1 presence, copies the archive, writes its manifest and updates the catalog reference for this Id/architecture. Older version folders may remain. Does not upload to a server or install the package. The current implementation has catalog-side effects outside its individual ShouldProcess blocks; do not treat WhatIf as a transaction guarantee. Work on a controlled local repository copy.'
            Environment = 'Repository preparation machine with writable local repository storage.'
            Output = 'OSDApps.RepositoryPackage metadata object including archive SHA-256 and manifest reference.'
            Examples = @(@{ Code = "Add-OSDAppPackage -Id ExampleApp -DisplayName 'Example App' -Vendor 'Example Publisher' -Version 1.0.0 -Architecture x64 -PackagePath 'C:\Work\Build\ExampleApp\Package.zip' -RepositoryPath 'C:\Work\Repository'"; Remarks = 'Update local repository content; publishing to your HTTP host is a separate action.' })
            Link = 'docs/repository.md'
        }
        'Test-OSDAppPackage' = @{
            Synopsis = 'Validate the repository archive structure and report its hash.'
            Description = 'Extracts the archive into a temporary directory, checks for Package/Install.ps1, computes SHA-256, and removes temporary content. Does not execute Install.ps1. Valid is a structural result, not malware scanning or proof that installation will succeed.'
            Environment = 'Preparation machine or suitable PowerShell environment with archive support and writable TEMP.'
            Output = 'OSDApps.PackageValidation object with structure flags, Sha256 and Valid.'
            Examples = @(@{ Code = "Test-OSDAppPackage -PackagePath 'C:\Work\Build\ExampleApp\Package.zip'"; Remarks = 'Inspect an existing package before adding it to a repository.' })
            Link = 'docs/repository.md'
        }
        'Test-OSDAppRepository' = @{
            Synopsis = 'Validate local repository references, manifests and packages.'
            Description = 'Checks referenced package identity, architecture, success codes, archive definition, structure and SHA-256; reports missing, duplicate and orphaned content. Does not repair the repository or execute installers. Structural package checks use temporary extraction.'
            Environment = 'Preparation machine with read access to the local repository and writable TEMP.'
            Output = 'OSDApps.RepositoryValidation objects. Inspect every returned Valid value rather than treating any output as overall success.'
            Examples = @(@{ Code = "Test-OSDAppRepository -RepositoryPath 'C:\Work\Repository' | Where-Object { -not $_.Valid }"; Remarks = 'Review invalid entries; no output does not by itself prove an expected application count.' })
            Link = 'docs/repository.md'
        }
    }
}
