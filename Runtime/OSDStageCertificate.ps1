function Read-OSDStageCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][ValidateSet('Root','CA')][string]$Store
    )
    $file=Get-Item -LiteralPath $LiteralPath -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -notin @('.cer','.crt') -or $file.Length -gt 1MB) {
        throw 'Provide an individual public .cer or .crt certificate of at most 1 MB.'
    }
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    # Check the container before loading: never import keys from a disguised PFX.
    if ([Security.Cryptography.X509Certificates.X509Certificate2]::GetCertContentType($bytes) -ne
        [Security.Cryptography.X509Certificates.X509ContentType]::Cert) {
        throw 'Only individual public X.509 certificates are supported; PFX and bundles are not accepted.'
    }
    $text=[Text.Encoding]::ASCII.GetString($bytes)
    if ($text.Contains('-----BEGIN')) {
        if ($text -notmatch '\A\s*-----BEGIN CERTIFICATE-----\s*[A-Za-z0-9+/=\s]+-----END CERTIFICATE-----\s*\z') {
            throw 'PEM input must contain exactly one certificate and no private key or other content.'
        }
    }
    $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
    try {
        if (-not $text.Contains('-----BEGIN') -and [Convert]::ToBase64String($bytes) -ne [Convert]::ToBase64String($cert.RawData)) {
            throw 'DER input must contain exactly one certificate without trailing content.'
        }
        if ($cert.HasPrivateKey) { throw 'Private keys are not supported.' }
        $constraints=@($cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
        if ($constraints.Count -ne 1 -or -not $constraints[0].CertificateAuthority) {
            throw 'Root and CA stores require a certificate with the CA basic constraint.'
        }
        if ($Store -eq 'Root' -and [Convert]::ToBase64String($cert.SubjectName.RawData) -ne [Convert]::ToBase64String($cert.IssuerName.RawData)) {
            throw 'Root requires a self-issued CA certificate. Use CA for intermediate certificates.'
        }
        [pscustomobject]@{
            Subject=$cert.Subject;Thumbprint=$cert.Thumbprint;Store=$Store
            Certificate=[Convert]::ToBase64String($cert.RawData)
        }
    }
    finally { $cert.Dispose() }
}

function ConvertFrom-OSDStageCertificateOperation {
    param([Parameter(Mandatory)]$Operation)
    if ([string]$Operation.Store -notin @('Root','CA')) { throw 'Unsupported certificate store.' }
    if ([string]$Operation.Thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Invalid certificate thumbprint.' }
    $bytes=[Convert]::FromBase64String([string]$Operation.Certificate)
    if ($bytes.Length -gt 1MB -or
        [Security.Cryptography.X509Certificates.X509Certificate2]::GetCertContentType($bytes) -ne
        [Security.Cryptography.X509Certificates.X509ContentType]::Cert) { throw 'Invalid public certificate payload.' }
    $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
    try {
        if ($cert.HasPrivateKey -or $cert.Thumbprint -ne [string]$Operation.Thumbprint) { throw 'Certificate identity mismatch.' }
        $constraints=@($cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
        if ($constraints.Count -ne 1 -or -not $constraints[0].CertificateAuthority) { throw 'Certificate is not a CA.' }
        if ([string]$Operation.Store -eq 'Root' -and
            [Convert]::ToBase64String($cert.SubjectName.RawData) -ne [Convert]::ToBase64String($cert.IssuerName.RawData)) { throw 'Root requires a self-issued CA.' }
        return $cert
    }
    catch { $cert.Dispose();throw }
}

function Install-OSDStagePublicCertificate {
    param([Parameter(Mandatory)]$Certificate,[Parameter(Mandatory)][ValidateSet('Root','CA')][string]$Store)
    $target=[Security.Cryptography.X509Certificates.X509Store]::new($Store,[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
    try {
        $target.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $existing=$target.Certificates.Find([Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,$Certificate.Thumbprint,$false)
        if ($existing.Count -gt 0) { return 'AlreadyPresent' }
        $target.Add($Certificate)
        return 'Imported'
    }
    finally { $target.Close();$target.Dispose() }
}

function Invoke-OSDStageCertificateOperation {
    param([Parameter(Mandatory)]$Operation)
    $cert=ConvertFrom-OSDStageCertificateOperation -Operation $Operation
    try {
        $outcome=Install-OSDStagePublicCertificate -Certificate $cert -Store ([string]$Operation.Store)
        [pscustomobject]@{
            Subject=$cert.Subject;Thumbprint=$cert.Thumbprint;Store=('LocalMachine\'+[string]$Operation.Store)
            Status='Succeeded';Outcome=$outcome;Error=$null
        }
    }
    finally { $cert.Dispose() }
}

function Get-OSDStageCertificatePackageOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][ValidateSet('Root','CA')][string]$Store
    )
    if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) { throw 'Certificate package directory is missing.' }
    $entries=@(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -Force -ErrorAction Stop)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Certificate packages cannot contain reparse points.' }
    $files=@($entries | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw 'Certificate packages require at least one public .cer or .crt file.' }
    if (@($files | Where-Object { $_.Extension -notin @('.cer','.crt') }).Count) { throw 'Certificate packages may contain only public .cer or .crt files; scripts, PFX and support files are not allowed.' }
    $seen=@{}
    foreach($file in $files) {
        $operation=Read-OSDStageCertificate -LiteralPath $file.FullName -Store $Store
        if (-not $seen.ContainsKey($operation.Thumbprint)) {
            $seen[$operation.Thumbprint]=$true
            $operation
        }
    }
}

function Invoke-OSDStageCertificatePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][ValidateSet('Root','CA')][string]$Store,
        [Parameter(Mandatory)][string]$DeploymentId,
        [Parameter(Mandatory)][string]$ResultPath
    )
    $items=@()
    $failure=$null
    try {
        # Materialize and validate all files before the first trust-store write.
        $operations=@(Get-OSDStageCertificatePackageOperations -PayloadRoot $PayloadRoot -Store $Store)
        $items=@(foreach($operation in $operations) {
            try { Invoke-OSDStageCertificateOperation -Operation $operation }
            catch {
                [pscustomobject]@{
                    Subject=$operation.Subject;Thumbprint=$operation.Thumbprint;Store=('LocalMachine\'+$Store)
                    Status='Failed';Outcome='Failed';Error=$_.Exception.Message
                }
            }
        })
    }
    catch { $failure=$_.Exception.Message }
    $failed=@($items | Where-Object Status -eq Failed).Count
    $exitCode=if($failure -or $failed){1}else{0}
    $record=[ordered]@{
        SchemaVersion=2;DeploymentId=$DeploymentId;PackageId=$PackageId
        Status=if($exitCode){'Failed'}else{'Succeeded'}
        OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed)
        FailedOperationCount=$failed;RestartNeeded=$false;Items=$items
        Error=if($failure){$failure}elseif($failed){"$failed certificate operation(s) failed."}else{$null}
    }
    New-Item -ItemType Directory -Path (Split-Path $ResultPath -Parent) -Force -ErrorAction Stop | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -ErrorAction Stop
    [pscustomobject]@{ExitCode=$exitCode;Integrity='Sha256Validated';ResultPath=$ResultPath}
}
