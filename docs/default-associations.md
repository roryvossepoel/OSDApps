# Initial default file and protocol associations

`Add-OSDStageDefaultAssociation` stages initial defaults for new Windows users.
Use it in WinPE after OSDCloud applies Windows, and put the entry after the
installers that provide the selected handlers. This candidate supports Windows
11 client with native 64-bit PowerShell during SetupComplete. It is experimental
until the physical acceptance test below passes.

## Explicit initial defaults only

Installing an app and choosing its defaults are separate operations. OSDStage
does not infer association selections from installed apps, their capabilities or
installation order. Without an `Add-OSDStageDefaultAssociation` call, no association
entry or DISM association import is added. Windows and the vendor installers
retain their normal behavior; OSDStage does not suppress their app registration.

Only identifiers supplied through parameters or the selected XML are explicit
overrides. A full XML export selects every association in that file, so use a
smaller selection when you only intend to choose a browser or PDF reader. The
runtime preserves the exported baseline for other identifiers. It does not claim
all supported extensions of the selected app.

These are initial defaults for each new user's first sign-in. There is no enforce
mode, recurring policy or correction task. Users can change their defaults later.

## Multiple browsers and a separate PDF choice

Stage all desired apps first, then explicitly choose a handler for the web
protocols and HTML files. Installing another browser does not make OSDStage select
it as the default. For example, in WinPE:

```powershell
Add-OSDStageGoogleChromeEnterprise -Architecture x64
Add-OSDStageMozillaFirefoxEnterprise -Architecture x64
Add-OSDStageAdobeAcrobatUnified -Architecture x64

# Explicit initial browser choice; PDF is independent.
Add-OSDStageDefaultAssociation -Identifier @('http','https','.htm','.html') -ProgId 'ChromeHTML' -AppName 'Google Chrome'

# Explicit PDF choice; other Adobe file types are not selected here.
Add-OSDStageDefaultAssociation -Identifier '.pdf' -ProgId 'Acrobat.Document.DC' -AppName 'Adobe Acrobat'
```

Omit either association call to leave those identifiers without an OSDStage
override. Omit both to install the apps without staging association settings.
To choose a different browser, supply that installed version's registered handler
ID; there is no guessed browser-to-ProgId lookup. Later calls for the same
identifier replace earlier explicit selections, independently of app order.

## Parameters or XML

```powershell
# Example handler IDs: verify them against your installed app versions first.
Add-OSDStageDefaultAssociation -Identifier '.pdf' -ProgId 'Acrobat.Document.DC' -AppName 'Adobe Acrobat'
Add-OSDStageDefaultAssociation -Identifier @('.htm','.html','http','https') -ProgId 'ChromeHTML' -AppName 'Google Chrome'
```

`Identifier` is an extension with its leading dot, or a protocol scheme without
a colon. `ProgId` is the registered Windows handler ID, not a repository ID,
executable path, package name or friendly name. `AppName` is display text; it
does not install or locate an app. No built-in app-to-handler lookup is guessed.
Handler IDs are retained as literal registry names, including relative subkeys;
validation checks their shape, not whether the intended app registered them.

The Adobe example targets Acrobat Unified: the tested x64 version 26.002.22031
registers `Acrobat.Document.DC`. Do not substitute the standalone Reader handler
`AcroExch.Document.DC` unless that handler exists on the target. A successful DISM
import can still leave a user pointing at an unregistered handler; the import
result alone does not validate the mapping.

Alternatively, select an existing DISM export:

```powershell
Add-OSDStageDefaultAssociation -XmlPath 'C:\DeploymentData\DefaultAssociations.xml'
```

Use the actual path available in WinPE. `Path` is an alias for `XmlPath`.
The parameter set and XML set are mutually exclusive in one call, but may be
combined across calls. Both merge into one DefaultAssociations queue entry;
the last call for an identifier wins, case-insensitively. Unselected staged
identifiers remain. Re-adding the entry moves it to the end of the current
queue, consistent with other Add commands. Call it after your selected apps;
no dependency sorting or later app repair is inferred.

To create a reference export, install the intended apps on a matching reference
Windows build, choose the desired defaults in Settings, then run elevated:

```powershell
dism.exe /Online /Export-DefaultAppAssociations:C:\Temp\DefaultAssociations.xml
```

The accepted XML shape is:

```xml
<DefaultAssociations>
  <Association Identifier=".pdf" ProgId="Acrobat.Document.DC" ApplicationName="Adobe Acrobat" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
```

XML accepts exactly the shown root, elements and attributes. DTDs, entities,
namespaces, duplicate identifiers, unexpected content and policy-specific
Version/Suggested attributes are rejected. Input is limited to 1 MiB and 2048
entries. XML escaping is generated internally for parameter input. Source XML
is read during staging and never changed; it is not needed at runtime. Full
exports and smaller explicit selections use the same merge behavior.

## One-shot mechanism

WinPE only writes the integrity-checked bundled Script/configuration and normal
runner files. It does not modify host defaults, user profiles or offline user
registry choices. No repository package, download or USB cache entry is required
for the association settings themselves.

During SetupComplete, under SYSTEM, the runtime:

1. Checks Windows/runtime context and refuses an already configured machine
   default-associations policy that could override this import.
2. Runs native `dism.exe /Online /Export-DefaultAppAssociations` into a new
   attempt directory on the running Windows installation.
3. Requires a valid, nonempty export; retains its entries and overlays the
   requested identifiers. No import occurs if export/validation fails.
4. Generates one merged XML and invokes `/Import-DefaultAppAssociations` once,
   with `/NoRestart`. DISM exit 0 or 3010 is accepted and recorded.

This uses Windows image defaults, not a recurring Group Policy or CSP. It does
not write UserChoice hashes, use SetUserFTA, remove Windows defaults, schedule a
task or force a reboot. DISM documents these imported defaults for each user's
first logon; existing user choices are not the target. Users can subsequently
choose their own defaults, subject to any later management policy.

Each native command has a five-minute timeout. Failures retain their output and
do not trigger retry or rollback of Windows servicing. If DISM times out or
fails after beginning an import, partial changes cannot be ruled out.
The runtime does not change a later Intune/GPO policy or guarantee that Windows
will accept an unregistered, delayed-install or per-user-only handler.

Preserving every exported entry avoids deliberately dropping unselected
associations. It does not establish that a pre-OOBE SYSTEM export contains every
implicit/delayed-install app default. Microsoft documents completeness limits
for reference exports; fresh-image testing must check for reset notifications
and unaffected defaults. Do not treat an export or import exit code as proof of
the final user experience.

## Results and cleanup

`DefaultAssociations-Result.json` uses the deployment's configured result folder
and DeploymentId. It records requested identifiers/handlers, exported/imported
counts, native output, exit codes, errors and restart-needed state. Success is
`ImportedForFirstSignIn`, with `UserDefaultsVerified=false` and
`RebootRequested=false`; it is not a claim that a user has opened a file.

Baseline.xml, Merged.xml and native DISM logs live in the owned attempt folder
under `Windows\Temp\OSDStage\BuiltIn\DefaultAssociations`. Normal CleanupMode
applies; Never retains these files for inspection. DISM stores imported defaults
in Windows, so the source XML need not remain after successful staging cleanup.
Removing the queue entry before execution discards the pending selection;
removing it after execution does not undo imported Windows defaults.

## Physical acceptance

Use a freshly applied x64 Windows image for the initial candidate test. Stage
Adobe and Chrome before the associations, verifying that the example ProgIds
match those versions. First test parameter input, then the equivalent selected
XML in a separate fresh deployment when needed to establish both input routes.
The [example](../Examples/Stage-OSDStageDefaultAssociationsTest.ps1) supports both.

Record the exact module commit, Windows build/edition, chosen handlers and
DeploymentId. During the normal OOBE/first-sign-in flow manually confirm:

- Requested file/protocol defaults differ from the original Windows defaults
  and open the intended installed apps.
- An unrelated file type retains its original default; no unexpected app-reset
  notifications appear.
- Changing a selected default through Settings is allowed. Record continued
  editability separately; no automated post-sign-in verification is installed.

CI covers parsing, merge/escaping, staging/rollback, integrity, result handling,
a native read-only DISM export and production runner rejection outside SYSTEM.
It never imports defaults into the CI machine. SYSTEM export/import and the
first-user outcome remain physical acceptance requirements before deciding
whether to retain this feature. ARM64 is not physically validated.

## Microsoft references

- [DISM association servicing](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-default-application-association-servicing-command-line-options)
- [Reference exports, imports and completeness limits](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/export-or-import-default-application-associations)

[Back to documentation](README.md)
