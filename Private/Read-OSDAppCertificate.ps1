function Read-OSDAppCertificate {
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
