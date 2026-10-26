# Public CA certificate staging

In WinPE after OSDCloud applies Windows, stage public certificates for one SetupComplete import as SYSTEM:

```powershell
Add-OSDAppCertificate -Path 'E:\Certificates\root.cer' -Store Root
Add-OSDAppCertificate -Path 'E:\Certificates\intermediate.crt' -Store CA
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

Replace example paths with your actual media path; OSDApps resolves the offline Windows installation automatically. The preparation PC is never the target. `-WindowsPath` can explicitly select an offline Windows volume. `-WhatIf` validates inputs without staging.

## Scope

Each `.cer`/`.crt` file must contain one public X.509 CA certificate, in DER or PEM format. PFX/P12, bundles, private keys and end-entity certificates are rejected. Store selection is mandatory: `Root` means `LocalMachine\Root`; `CA` means `LocalMachine\CA`. Root inputs must be self-issued CA certificates. Input validation does not establish trustworthiness or validate the full chain, revocation, self-signature or validity period: only stage CAs you intend to trust. Expired certificates are not automatically removed or renewed.

Repeated thumbprint/store pairs are staged once. One `Certificates` built-in Script entry contains the public certificate bytes and target stores. Script and configuration are SHA-256 checked before execution. Sources are copied into the configuration, so the original media is unnecessary at runtime. Transactional updates preserve the previous payload if staging fails.

SetupComplete validates the entire configuration before modifying trust stores, then imports each requested certificate once. An existing thumbprint in the selected store returns `AlreadyPresent`; other certificates remain untouched. An import failure is reported and remaining operations continue. There are no forced reboots, scheduled retries or post-reboot checks. Importing into Root grants machine-wide trust.

`Certificates-Result.json` records deployment ID, subject, thumbprint, destination store, outcome and errors. Exit code is 0 on success or 1 on failure; RestartNeeded is false. Public certificate staging follows the global cleanup mode (including retaining it with Never). Original `.cer` files are unchanged. No private-key support is included in this version.
