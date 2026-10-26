function Add-OSDAppCertificate {
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='File')]
    param(
        [Parameter(Mandatory,ParameterSetName='File')][ValidateNotNullOrEmpty()][string[]]$Path,
        [Parameter(Mandatory,ParameterSetName='File')][ValidateSet('Root','CA')][string]$Store,
        [Parameter(Mandatory,ParameterSetName='Repository')][Alias('Name')][string]$Id,
        [Parameter(ParameterSetName='Repository')][switch]$SkipCacheRefresh,
        [string]$WindowsPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'Repository') {
        Assert-OSDAppSourceEnabled -Source Repository
        $matches=@(Get-OSDApp -Name $Id | Where-Object { [string]$_.Source -eq 'Repository' -and [string]$_.Id -ieq $Id })
        if ($matches.Count -ne 1) { throw "Repository certificate package '$Id' was not found uniquely in the configured catalog/cache." }
        if ([string]$matches[0].PackageType -ne 'Certificate') { throw "Repository package '$Id' is not Certificate." }
        if (-not $PSCmdlet.ShouldProcess($Id,'Stage repository certificate package for SetupComplete')) { return }
        Add-OSDApp -Name $Id -WindowsPath $WindowsPath -SkipCacheRefresh:$SkipCacheRefresh -Confirm:$false
        return
    }

    Assert-OSDAppSourceEnabled -Source BuiltIn
    if (-not (Test-OSDAppWinPE)) { throw 'Stage certificates in WinPE after OSDCloud, not on the preparation PC.' }
    $newOperations=@(foreach($file in $Path) { Read-OSDAppCertificate -LiteralPath $file -Store $Store })

    $target=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDApps'
    $payloadRoot=Join-Path $stage 'BuiltIn\Certificates'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDAppCertificates.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Certificates runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Apps') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()} }

    $manifest=Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Apps | Where-Object Id -eq 'Certificates')
    if ($previous.Count -gt 1) { throw 'Duplicate Certificates entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'CertificateScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.CertificateSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing Certificates staging is not an intact OSDApps-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned Certificates staging directory exists. Nothing was replaced.'
    }

    foreach($operation in $newOperations) {
        $operations=@($operations | Where-Object { ([string]$_.Thumbprint -ne [string]$operation.Thumbprint -or [string]$_.Store -ne [string]$operation.Store) }) + @($operation)
    }

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=1
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'Certificates-Result.json')
        Operations=@($operations)
    }

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} certificate operation(s) for SetupComplete" -f $operations.Count))) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.Certificates-' + [guid]::NewGuid().ToString('N'))
    $backup=$transaction + '.previous'
    $manifestTemp=$manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $promoted=$false;$backedUp=$false;$committed=$false
    try {
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        # Embed shared functions so the existing script hash covers the entire local importer.
        $shared=Get-Content -LiteralPath (Join-Path $moduleRoot 'Runtime\OSDAppCertificate.ps1') -Raw -Encoding UTF8
        $runtime=Get-Content -LiteralPath $scriptSource -Raw -Encoding UTF8
        $runtime=$runtime.Replace('. (Join-Path $PSScriptRoot ''OSDAppCertificate.ps1'')',$shared)
        $runtime | Set-Content -LiteralPath (Join-Path $transaction 'Install.ps1') -Encoding UTF8 -ErrorAction Stop
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $transaction 'config.json') -Encoding UTF8 -ErrorAction Stop

        $scriptHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'Install.ps1') -Algorithm SHA256).Hash
        $configHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'config.json') -Algorithm SHA256).Hash
        $app=[pscustomobject]@{
            Id='Certificates';DisplayName='Public CA certificates';Vendor='OSDApps'
            Source='BuiltIn';PackageType='Script';Type='CertificateScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\Certificates\Install.ps1'
            Configuration='BuiltIn\Certificates\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            CertificateSchema=1;CertificateOperationCount=$operations.Count
        }
        $manifest=Set-OSDAppManifestApp -Manifest $manifest -App $app
        $manifest.StagedAt=(Get-Date).ToUniversalTime().ToString('o')
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestTemp -Encoding UTF8
        Add-OSDAppSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDApps' -Confirm:$false -ErrorAction Stop | Out-Null

        if (Test-Path -LiteralPath $payloadRoot) { Move-Item -LiteralPath $payloadRoot -Destination $backup -ErrorAction Stop;$backedUp=$true }
        Move-Item -LiteralPath $transaction -Destination $payloadRoot -ErrorAction Stop;$promoted=$true
        Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force -ErrorAction Stop;$committed=$true
    }
    finally {
        if (-not $committed) {
            if ($promoted -and (Test-Path -LiteralPath $payloadRoot)) { Remove-Item -LiteralPath $payloadRoot -Recurse -Force }
            if ($backedUp) { Move-Item -LiteralPath $backup -Destination $payloadRoot -ErrorAction Stop }
        }
        if ($committed -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if (Test-Path -LiteralPath $transaction) { Remove-Item -LiteralPath $transaction -Recurse -Force }
        if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp -Force }
    }

    [pscustomobject]@{
        PSTypeName='OSDApps.StagedApp';Name='Certificates';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Certificates=@($operations | Select-Object Subject,Thumbprint,Store)
    }
}
