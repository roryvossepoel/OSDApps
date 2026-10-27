function Add-OSDAppService {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Automatic','AutomaticDelayedStart','Manual','Disabled')][string]$StartupType,
        [ValidateSet('Running','Stopped')][string]$State,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 30,
        [string]$WindowsPath
    )

    Assert-OSDAppSourceEnabled -Source BuiltIn
    if (-not (Test-OSDAppWinPE)) { throw 'Stage service changes in WinPE after OSDCloud, not on the preparation PC.' }

    $operation = [pscustomobject]@{Name=$Name;StartupType=$StartupType;State=$State;TimeoutSeconds=$TimeoutSeconds}
    Assert-OSDAppServiceOperation -Operation $operation

    $target=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDApps'
    $payloadRoot=Join-Path $stage 'BuiltIn\Services'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDAppServices.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Services runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Apps') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()} }

    $manifest=Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Apps | Where-Object Id -eq 'Services')
    if ($previous.Count -gt 1) { throw 'Duplicate Services entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'ServiceScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.ServiceSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing Services staging is not an intact OSDApps-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert-OSDAppServiceConfiguration -Configuration $existing
        if ([string]$existing.DeploymentId -ne [string]$manifest.DeploymentId) { throw 'Service staging belongs to another deployment.' }
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned Services staging directory exists. Nothing was replaced.'
    }

    $prior = @($operations | Where-Object { [string]$_.Name -ieq $Name })
    if ($prior.Count -gt 1) { throw 'Duplicate service staging.' }
    if ($prior.Count -eq 1) {
        if (-not $PSBoundParameters.ContainsKey('StartupType')) { $operation.StartupType = [string]$prior[0].StartupType }
        if (-not $PSBoundParameters.ContainsKey('State')) { $operation.State = [string]$prior[0].State }
        if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $operation.TimeoutSeconds = [int]$prior[0].TimeoutSeconds }
    }
    Assert-OSDAppServiceOperation -Operation $operation
    $operations = @($operations | Where-Object { [string]$_.Name -ine $Name }) + @($operation)

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=1
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'Services-Result.json')
        Operations=@($operations)
    }

    Assert-OSDAppServiceConfiguration -Configuration ([pscustomobject]$config)

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} service operation(s) for SetupComplete" -f $operations.Count))) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.Services-' + [guid]::NewGuid().ToString('N'))
    $backup=$transaction + '.previous'
    $manifestTemp=$manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $promoted=$false;$backedUp=$false;$committed=$false
    try {
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        Copy-Item -LiteralPath $scriptSource -Destination (Join-Path $transaction 'Install.ps1') -ErrorAction Stop
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $transaction 'config.json') -Encoding UTF8 -ErrorAction Stop

        $scriptHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'Install.ps1') -Algorithm SHA256).Hash
        $configHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'config.json') -Algorithm SHA256).Hash
        $app=[pscustomobject]@{
            Id='Services';DisplayName='Windows services';Vendor='OSDApps'
            Source='BuiltIn';PackageType='Script';Type='ServiceScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\Services\Install.ps1'
            Configuration='BuiltIn\Services\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            ServiceSchema=1;ServiceOperationCount=$operations.Count
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
        PSTypeName='OSDApps.StagedApp';Name='Services';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Names=@($operations | ForEach-Object Name | Select-Object -Unique)
    }
}
