function Add-OSDStageEnvironmentVariable {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Set')]
    param(
        [Parameter(Mandatory, ParameterSetName='Set')]
        [Parameter(Mandatory, ParameterSetName='Remove')]
        [string]$Name,
        [Parameter(Mandatory, ParameterSetName='Set')][AllowEmptyString()][string]$Value,
        [Parameter(ParameterSetName='Set')][switch]$ExpandString,
        [Parameter(Mandatory, ParameterSetName='Remove')][switch]$Remove,
        [Parameter(Mandatory, ParameterSetName='Path')][string[]]$AppendPath,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage machine environment changes in WinPE after OSDCloud, not on the preparation PC.' }

    $operation = switch ($PSCmdlet.ParameterSetName) {
        'Set' { [pscustomobject]@{ Action='Set';Name=$Name;Value=$Value;Kind=if ($ExpandString) {'ExpandString'} else {'String'} } }
        'Remove' {
            if (-not $Remove) { throw 'Remove must be explicitly enabled.' }
            [pscustomobject]@{ Action='Remove';Name=$Name }
        }
        'Path' { [pscustomobject]@{ Action='AppendPath';Name='Path';Entries=@($AppendPath) } }
    }
    Assert-OSDStageEnvironmentOperation -Operation $operation

    $target=Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDStage'
    $payloadRoot=Join-Path $stage 'BuiltIn\EnvironmentVariables'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDStageEnvironmentVariables.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Environment Variables runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Packages') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=2;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Packages=@()} }

    $manifest=Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Packages | Where-Object Id -eq 'EnvironmentVariables')
    if ($previous.Count -gt 1) { throw 'Duplicate EnvironmentVariables entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'EnvironmentVariableScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.EnvironmentVariableSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing EnvironmentVariables staging is not an intact OSDStage-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert-OSDStageEnvironmentConfiguration -Configuration $existing
        if ([string]$existing.DeploymentId -ne [string]$manifest.DeploymentId) { throw 'Environment staging belongs to another deployment.' }
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned EnvironmentVariables staging directory exists. Nothing was replaced.'
    }

    if ($operation.Action -ne 'AppendPath') {
        # A replacement/removal supersedes earlier intent for the same machine variable.
        $operations = @($operations | Where-Object { [string]$_.Name -ine [string]$operation.Name })
    }
    $operations = @($operations) + @($operation)

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'EnvironmentVariables-Result.json')
        Operations=@($operations)
    }

    Assert-OSDStageEnvironmentConfiguration -Configuration ([pscustomobject]$config)

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} machine environment operation(s) for SetupComplete" -f $operations.Count))) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.EnvironmentVariables-' + [guid]::NewGuid().ToString('N'))
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
            Id='EnvironmentVariables';DisplayName='Machine environment variables';Vendor='OSDStage'
            Source='BuiltIn';PackageType='Script';Type='EnvironmentVariableScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\EnvironmentVariables\Install.ps1'
            Configuration='BuiltIn\EnvironmentVariables\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            EnvironmentVariableSchema=1;EnvironmentVariableOperationCount=$operations.Count
        }
        $manifest=Set-OSDStageManifestApp -Manifest $manifest -App $app
        $manifest.StagedAt=(Get-Date).ToUniversalTime().ToString('o')
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestTemp -Encoding UTF8
        Add-OSDStageSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDStage' -Confirm:$false -ErrorAction Stop | Out-Null

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
        PSTypeName='OSDStage.StagedApp';Name='EnvironmentVariables';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Names=@($operations | ForEach-Object Name | Select-Object -Unique)
    }
}
