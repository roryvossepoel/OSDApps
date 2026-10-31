# Language-pack evaluation and scope decision

## Decision — 31 October 2026

Language-pack installation and multilingual OOBE image preparation are **outside
OSDApps scope**. The maintainer accepted the technical experiment but rejected
the associated language-media, build-matching and cumulative/checkpoint update
management as module responsibilities. No language cmdlet, bundled Microsoft
binaries or automatic update acquisition is introduced. Existing
[Windows capabilities](windows-capabilities.md) remain in scope; their contract
does not promise full display-language or OOBE orchestration.

Select the base language and corresponding Microsoft ESD through OSDCloud for
ordinary deployments. Where first-start OOBE must offer several languages,
prepare and maintain a multilingual WIM separately. Adding languages later in
running Windows is a separate option, not an equivalent pre-OOBE feature.

## Experiment and observed outcome

This was a manually supplied DISM experiment, not an OSDApps implementation or
commit-pinned module acceptance. The device was not enrolled in Autopilot.

| Item | Recorded evidence |
| --- | --- |
| Target | Dutch base ESD, Windows 11 Pro x64, image build 10.0.26300.9711. WinPE DISM reported 10.0.26100.1. |
| Added language | en-US Client Language Pack CAB, amd64, package version 10.0.26100.1. DISM package inspection reported Applicable: Yes. This alone does not establish complete media compatibility. |
| Added language capabilities | Basic, OCR, Handwriting, TextToSpeech and Speech for en-US, from the operator's LanguagesAndOptionalFeatures source with LimitAccess. |
| Initial attempt | Language and capability commands succeeded. English appeared in the language picker, but OOBE mixed Dutch/English and returned to language selection after Domain join instead. Dutch selection reached account creation. |
| Revised attempt | A fresh deployment used language pack, language capabilities, then KB5127648 as the DISM Add-Package target with KB5043080 available alongside it. All commands returned success. |
| Revised language inventory | en-US fully localized and nl-NL partially localized with en-US fallback; default system UI language remained nl-NL. No forced language/locale override was added. |
| Revised OOBE | Operator reported that the previously missing country/region page appeared after choosing English, and subsequently confirmed reaching the desktop with the result looking correct. The requested scenario used Netherlands as region and a local account; no final machine-readable locale inventory was supplied. |

The revised preparation log directory reported by the device was
`C:\Windows\Logs\OSDApps-LanguageTest-20261031-103812`.
The supplied console output shows success for all four stages, including the
update operation and Get-Intl. The detailed cumulative-update DISM log and
Packages.txt were not supplied, so no component-by-component resource comparison
is claimed. Raw device logs and screenshots are not published in this repository.

Including the cumulative-update step was the intended difference between the
attempts and is consistent with Microsoft's image-servicing guidance. The
successful retest is strong practical evidence for this preparation sequence,
not a proven root-cause analysis of the earlier OOBE reset. Earlier diagnostic
reports included black-screen diagnostics and Edge/WebView update errors; no
causal connection was established. It does not establish behavior for every
language, build, architecture, app resource set, recovery image or Autopilot flow.

## Servicing guidance behind the experiment

Microsoft's offline-image instructions add the language pack, the applicable
language FoDs and language satellites for existing FoDs. If an LCU was applied
before adding languages, the instructions require reapplying it so its language
resources are included. This is different from simply downloading a language
through Settings or Install-Language on a running Windows installation.

Windows 11 24H2 and later checkpoint servicing can distribute the required
payload across multiple update files. Microsoft's offline FoD/language
customization guidance calls for the target cumulative update and preceding
checkpoints together, with the target MSU passed to DISM. These ongoing source
and update requirements are the reason for excluding this workflow from OSDApps,
not a claim that multilingual Windows images are unsupported.

- [Add languages to Windows images](https://learn.microsoft.com/windows-hardware/manufacture/desktop/add-language-packs-to-windows?view=windows-11)
- [Checkpoint cumulative updates and offline customization](https://learn.microsoft.com/windows/deployment/update/catalog-checkpoint-cumulative-updates)
- [Install-Language for running Windows](https://learn.microsoft.com/powershell/module/languagepackmanagement/install-language)

[Back to feature scope and validation](feature-status.md)
