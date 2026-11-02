# Microsoft runtime prerequisites

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Visual C++ v14 and modern .NET runtimes are optional built-ins. Add them in WinPE
after Windows is applied, just like apps:

```powershell
# Select exactly one architecture per command.
Add-OSDStageVisualCRedist -Architecture x64

# Standalone runtime for console apps and services.
Add-OSDStageDotNetRuntime -RuntimeType Runtime -Channel 10.0 -Architecture x64

# Desktop runtime for WPF/Windows Forms; includes the ordinary .NET runtime.
Add-OSDStageDotNetRuntime -RuntimeType Desktop -Channel 10.0 -Architecture x64
```

Normally choose Runtime **or** Desktop for the same channel and architecture;
Desktop already includes the ordinary runtime. Different .NET channels and
architectures may coexist. `-Channel` defaults to `10.0`; `-RuntimeType` defaults
to `Desktop`. All four runtime Add/Sync cmdlets require `-Architecture x86`
or `-Architecture x64`. There is no default or combined architecture selection.
Separate explicit calls remain separate deployment items. Native ARM64 runtimes are not included
in this addition. Legacy .NET Framework, ASP.NET Core, SDKs, Java and older
Visual C++ runtime families such as 2013 are separate products and are not installed.

Runtime staging puts these prerequisites before app entries while
preserving the relative order within each group. This is not a dependency engine:
OSDStage does not infer which apps need which runtimes, and its normal
continue-queue behavior still applies if a prerequisite fails.

## Why Visual C++ has one evergreen family

`Add-OSDStageVisualCRedist` and `Sync-OSDStageVisualCRedist` offer the latest supported
v14 redistributable through Microsoft's official evergreen endpoint. There is no
year or legacy-version selector. Visual Studio 2017, 2019, 2022 and 2026 use the
same v14 runtime family; the redistributable must be at least as recent as the
build tools used by the app. Microsoft also documents upgrading the
original 2015 redistributable in place to the current v14 runtime.

Separate 2017/2019/2022 built-ins would duplicate this selection. Some older v14
servicing branches remain supported, but this built-in deliberately follows the
latest supported release instead of pinning a servicing branch. Select exactly
one architecture explicitly per command; x64 does not satisfy an x86 app's
runtime requirement.

Visual C++ 2013 (v12), 2012 (v11), 2010 (v10), 2008 (v9) and 2005 (v8) are separate
legacy families outside general support. The latest v14 does not replace their
dependencies. Do not remove them from an existing computer simply because v14 is
installed. A legacy dependency, or a vendor-required pinned branch, belongs in an
explicitly maintained [repository package](repository.md) for the app
that needs it, rather than another evergreen built-in. Packaging it yourself does
not restore Microsoft support. Microsoft's limited product-specific support
exceptions do not make those old runtimes generally supported.

See Microsoft's [runtime lifecycle FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/visual-c-faq)
and [latest supported downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

## Acquisition and verification

- Visual C++ uses Microsoft's official `https://aka.ms/vc14/vc_redist.<architecture>.exe`
  links. A HEAD request checks the resolved Microsoft URL, length, ETag and/or
  Last-Modified before confirming reuse. The downloaded installer must be signed
  by Microsoft and report a v14 file version. Its locally recorded SHA-256 and
  size are checked on subsequent reuse. This is not a Microsoft-published SHA-256.
- .NET uses Microsoft's `builds.dotnet.microsoft.com/dotnet/release-metadata/<channel>/releases.json`.
  It selects the latest published stable patch within the requested channel and
  the exact Windows Runtime or Desktop EXE. Preview channels are rejected.
  Only channels `8.0`, `9.0` and `10.0` are currently offered, and only during their
  support lifecycle. Microsoft metadata must report active or maintenance support
  for online acquisition. EOL and preview status blocks acquisition and fallback.
  The requested channel is never silently upgraded to another major version.
  The official SHA-512 and Microsoft
  Authenticode signature are checked before promotion and execution.
- Each replacement is downloaded separately and validated before promotion.
  Download or validation failure preserves the previous generation. Offline or
  failed online acquisition can use a verified compatible staged fallback;
  this is reported separately from confirmed current cache reuse.
  Missing, corrupt, incompatible or untrusted fallback content is never executed.
  Without a usable fallback, that runtime fails and the deployment reports failure;
  independent queue entries follow the existing continue-queue policy. A direct
  `Sync` call reports acquisition errors and preserves the old generation rather
  than claiming it synchronized successfully. A metadata outage or missing support
  field may use verified staged content only while the bundled lifecycle policy
  still permits that channel; known EOL status never uses fallback.
- Runner checks the installed version for the requested architecture and runtime
  family/channel. A suitable equal or newer installation is retained. Otherwise
  the installer runs with `/install /quiet /norestart`; exit codes 0 and 3010
  require a successful post-install version check. Existing other channels are
  not removed. No machine reboot or global runtime/PATH configuration is requested.

## Supported .NET channels

The bundled offline policy permits .NET 8.0 and 9.0 through November 10, 2026,
and .NET 10.0 through November 14, 2028 (UTC dates). Staging, acquisition, cache
validation and execution reject these channels after their deadline, even without
internet access. The computer clock must be correct. Expired cache files and
existing installations are not deleted automatically. Microsoft release metadata
can reject a channel sooner; a module update is required to add a new major channel
or adopt a changed lifecycle date. These checks enforce supported channel lifetimes,
not a guarantee that an offline fallback is the newest available patch.

## Cache and preparation computer

```powershell
Sync-OSDStageVisualCRedist -Architecture x64
Sync-OSDStageDotNetRuntime -RuntimeType Desktop -Channel 10.0 -Architecture x64
Get-OSDStageCache -Name VisualCRedist,DotNetRuntime -VerifySignatures
```

Sync runs on full Windows, prepares the USB flash drive and installs nothing on
the preparation computer. Run Add in WinPE. Cache paths are
`BuiltIn/VisualCRedist/<architecture>` and
`BuiltIn/DotNetRuntime/<runtime-type>/<channel>/<architecture>`.
Only the active patch is retained per variant; a different channel or architecture
uses a different generation. Deployment IDs include the variant, for example
`VisualCRedist-x86` and `DotNetRuntime-Desktop-10.0-x64`.
`Get-OSDStageCache` exposes `VariantId` and `RuntimeType` to distinguish them.
The app list summarizes x64 Visual C++ and Desktop 10.0 x64; inspect the cache
inventory for all variants.

Sources: [Visual C++ downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist),
[.NET installers and runtime types](https://learn.microsoft.com/en-us/dotnet/core/install/windows),
[.NET release metadata](https://github.com/dotnet/core/tree/main/release-notes).

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
