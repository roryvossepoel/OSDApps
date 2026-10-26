[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'))
$ErrorActionPreference='Stop'

function ConvertFrom-OSDAppCertificateOperation {
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

function Install-OSDAppPublicCertificate {
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

function Invoke-OSDAppCertificateOperation {
    param([Parameter(Mandatory)]$Operation)
    $cert=ConvertFrom-OSDAppCertificateOperation -Operation $Operation
    try {
        $outcome=Install-OSDAppPublicCertificate -Certificate $cert -Store ([string]$Operation.Store)
        [pscustomobject]@{
            Subject=$cert.Subject;Thumbprint=$cert.Thumbprint;Store=('LocalMachine\'+[string]$Operation.Store)
            Status='Succeeded';Outcome=$outcome;Error=$null
        }
    }
    finally { $cert.Dispose() }
}

$configuration=$null
try {
    $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $id=[guid]::Empty
    if ([int]$configuration.SchemaVersion -ne 1 -or
        -not [guid]::TryParse([string]$configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$configuration.ResultPath) -or
        @($configuration.Operations).Count -eq 0) { throw 'Invalid certificate configuration.' }
    # Validate the complete input before changing any machine trust store.
    $seen=@{}
    foreach($operation in @($configuration.Operations)) {
        $cert=ConvertFrom-OSDAppCertificateOperation -Operation $operation
        $cert.Dispose()
        $key=[string]$operation.Store+':'+[string]$operation.Thumbprint
        if ($seen.ContainsKey($key)) { throw 'Duplicate certificate operation.' }
        $seen[$key]=$true
    }
    $items=@(foreach($operation in @($configuration.Operations)) {
        try { Invoke-OSDAppCertificateOperation -Operation $operation }
        catch {
            [pscustomobject]@{
                Subject=[string]$operation.Subject;Thumbprint=[string]$operation.Thumbprint
                Store=('LocalMachine\'+[string]$operation.Store)
                Status='Failed';Outcome='Failed';Error=$_.Exception.Message
            }
        }
    })
    $failed=@($items | Where-Object Status -eq Failed).Count
    $record=[ordered]@{
        SchemaVersion=1;DeploymentId=[string]$configuration.DeploymentId
        Status=if($failed){'Failed'}else{'Succeeded'}
        OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed)
        FailedOperationCount=$failed;RestartNeeded=$false;Items=$items
        Error=if($failed){"$failed certificate operation(s) failed."}else{$null}
    }
    $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if($failed){exit 1}
    exit 0
}
catch {
    $failure=$_.Exception.Message
    try {
        if($configuration -and $configuration.ResultPath) {
            $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
            New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
            [ordered]@{
                SchemaVersion=1;DeploymentId=[string]$configuration.DeploymentId;Status='Failed'
                OperationCount=0;SuccessfulOperationCount=0;FailedOperationCount=0
                RestartNeeded=$false;Items=@();Error=$failure
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        }
    } catch {}
    Write-Output ('Certificate import failed: '+$failure)
    exit 1
}
