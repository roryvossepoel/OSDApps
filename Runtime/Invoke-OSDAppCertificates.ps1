[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'))
$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'OSDAppCertificate.ps1')

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
