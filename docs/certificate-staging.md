# Repository certificate packages

Certificates can use the same repository, versioning, SHA-256 verification and USB cache as fonts. Publish a ZIP with `PackageType Certificate` and explicitly choose `CertificateStore Root` or `CA` in its manifest. Both destinations are **LocalMachine only**. The deployment command needs only the package Id.

On the preparation machine, put only public CA `.cer` or `.crt` files in the source directory (subdirectories are allowed). Scripts, private keys, PFX files, bundles and support files are rejected. Root requires self-issued CA certificates; CA accepts intermediate CA certificates. Validation does not establish trustworthiness, verify the self-signature, or evaluate expiry/revocation/the full chain; the publisher must approve the certificates.

```powershell
$package = New-OSDStagePackage -Id CompanyRootCA -Version 1.0.0 `
    -PackageType Certificate -SourcePath C:\Work\Certificates `
    -OutputPath C:\Work\Build\CompanyRootCA

Add-OSDStagePackage -Id CompanyRootCA -DisplayName 'Company Root CA' `
    -Version 1.0.0 -Architecture any -PackageType Certificate `
    -CertificateStore Root -PackagePath $package.PackagePath `
    -RepositoryPath C:\Work\Repository
```

Upload the repository as usual and sync its configured catalog to the USB cache with `Sync-OSDStageRepository -Name CompanyRootCA`. Use the volume label `OSDCloud`; no fixed drive letter is required. Republishing an existing variant without CertificateStore preserves that variant's store. A new variant must specify its store explicitly.

In WinPE, after applying Windows:

```powershell
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud -CleanupMode Never
Add-OSDStageCertificate -Id CompanyRootCA -SkipCacheRefresh
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

The existing repository runner imports the package once during SetupComplete, after SHA-256 verification and validation of every certificate. It never runs package scripts. Duplicate thumbprints within a package are imported once; certificates already in the destination are reported as `AlreadyPresent`. Import failures are reported and remaining valid operations are attempted. There is no reboot, scheduled retry, or later repair pass.

`Certificate-CompanyRootCA-Result.json` records the deployment Id, subject, thumbprint, machine store and outcome, without certificate bytes. Public certificate files follow the configured cleanup policy, including retention with `Never`.

The local-file interface remains available and uses the same import functions:

# Public CA certificate staging

In WinPE after OSDCloud applies Windows, stage public certificates for one SetupComplete import as SYSTEM:

```powershell
Add-OSDStageCertificate -Path 'E:\Certificates\root.cer' -Store Root
Add-OSDStageCertificate -Path 'E:\Certificates\intermediate.crt' -Store CA
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

Replace example paths with your actual media path; OSDStage resolves the offline Windows installation automatically. The preparation PC is never the target. `-WindowsPath` can explicitly select an offline Windows volume. `-WhatIf` validates inputs without staging.

## Scope

Each `.cer`/`.crt` file must contain one public X.509 CA certificate, in DER or PEM format. PFX/P12, bundles, private keys and end-entity certificates are rejected. Store selection is mandatory: `Root` means `LocalMachine\Root`; `CA` means `LocalMachine\CA`. Root inputs must be self-issued CA certificates. Input validation does not establish trustworthiness or validate the full chain, revocation, self-signature or validity period: only stage CAs you intend to trust. Expired certificates are not automatically removed or renewed.

Repeated thumbprint/store pairs are staged once. One `Certificates` built-in Script entry contains the public certificate bytes and target stores. Script and configuration are SHA-256 checked before execution. Sources are copied into the configuration, so the original media is unnecessary at runtime. Transactional updates preserve the previous payload if staging fails.

SetupComplete validates the entire configuration before modifying trust stores, then imports each requested certificate once. An existing thumbprint in the selected store returns `AlreadyPresent`; other certificates remain untouched. An import failure is reported and remaining operations continue. There are no forced reboots, scheduled retries or post-reboot checks. Importing into Root grants machine-wide trust.

`Certificates-Result.json` records deployment ID, subject, thumbprint, destination store, outcome and errors. Exit code is 0 on success or 1 on failure; RestartNeeded is false. Public certificate staging follows the global cleanup mode (including retaining it with Never). Original `.cer` files are unchanged. No private-key support is included in this version.
