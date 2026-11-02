# Microsoft 365 Apps

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

Run in WinPE after OSDCloud has applied Windows:

```powershell
Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl
```

## Configuration

The examples below are alternatives. Repeated Add calls replace the app selection; choose the configuration for this device.

Supported channels:

```text
Current
MonthlyEnterprise
SemiAnnual
CurrentPreview
SemiAnnualPreview
BetaChannel
```

Supported product IDs:

```text
O365ProPlusRetail
O365BusinessRetail
```

Supported architectures:

```text
x64 (default)
x86
```

ODT configuration XML still uses OfficeClientEdition=64/32.

The Office cache contains the Office Deployment Tool, `configuration.xml`, and `Office\Data`.

The built-in Office configuration uses a shared XML generator for `Add-OSDStageMicrosoft365Apps` and `Sync-OSDStageMicrosoft365Apps`. The common parameters are `Architecture` (x86/x64, x64 by default), `Channel`, `ProductId`, `Language`, `UpdatesEnabled`, `AcceptEula`, `SharedComputerLicensing`, `DeviceBasedLicensing`, and `ExcludeApp`. Optional `IncludeVisio` and `IncludeProject` switches include `VisioProRetail` and `ProjectProRetail` as separate Office Deployment Tool products. Each product gets the requested languages; exclusions apply only to Microsoft 365 Apps. The respective licenses must be assigned separately.

```powershell
# Without cached configuration: Enterprise x64, Current channel, en-us, updates on
Add-OSDStageMicrosoft365Apps

# Typical Dutch Office with monthly enterprise updates and Visio/Project
Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl -IncludeVisio -IncludeProject

# Shared workstation with licensed individual users
Add-OSDStageMicrosoft365Apps -SharedComputerLicensing $true

# Specialized device-based licensing, requiring an eligible device license
Add-OSDStageMicrosoft365Apps -DeviceBasedLicensing $true

# Disable Office updates (manage Office updates separately)
Add-OSDStageMicrosoft365Apps -UpdatesEnabled $false
```

When no Office configuration parameter is supplied to `Add-OSDStageMicrosoft365Apps`, a usable cached configuration can be retained. Specify the channel, language and other required choices explicitly when you want to override it. The README does this for MonthlyEnterprise/en-us.

For advanced or unusual configurations, export XML from Microsoft's Office Customization Tool and pass `-ConfigurationXml <path>`. The supplied XML is checked only for file existence and well-formed XML syntax (without DTD or external entity resolution), then preserved without modification. Office Deployment Tool validates its own products, channels, languages and other configuration semantics. Do not simultaneously supply conflicting generated configuration switches; the custom XML takes precedence.

## Optional cache preparation

Run on a full Windows preparation PC. Match the configuration you will stage in WinPE. Changing Sync parameters rewrites the desired Office configuration and refreshes the cache.

```powershell
Sync-OSDStageMicrosoft365Apps `
    -Channel MonthlyEnterprise `
    -Architecture x64 `
    -ProductId O365ProPlusRetail `
    -Language nl-nl
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
