function Save-OSDStageFileSystemStaging {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Operations, [string]$WindowsPath)
    $OperationsToAdd = @($Operations)
    foreach ($op in $OperationsToAdd) { Assert-OSDStageFileSystemOperation -Operation $op }
    $target=Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDStage'
    $payloadRoot=Join-Path $stage 'BuiltIn\FileSystem'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDStageFileSystem.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'File system runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Packages') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=2;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Packages=@()} }

    $manifest=Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Packages | Where-Object Id -eq 'FileSystem')
    if ($previous.Count -gt 1) { throw 'Duplicate FileSystem entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'FileSystemScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.FileSystemSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing FileSystem staging is not an intact OSDStage-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert-OSDStageFileSystemConfiguration -Configuration $existing
        if ([string]$existing.DeploymentId -ne [string]$manifest.DeploymentId) { throw 'File system staging belongs to another deployment.' }
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned FileSystem staging directory exists. Nothing was replaced.'
    }

    $operations = @($operations) + @($OperationsToAdd)

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'FileSystem-Result.json')
        Operations=@($operations)
    }

    Assert-OSDStageFileSystemConfiguration -Configuration ([pscustomobject]$config)


    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.FileSystem-' + [guid]::NewGuid().ToString('N'))
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
            Id='FileSystem';DisplayName='Files and directories';Vendor='OSDStage'
            Source='BuiltIn';PackageType='Script';Type='FileSystemScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\FileSystem\Install.ps1'
            Configuration='BuiltIn\FileSystem\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            FileSystemSchema=1;FileSystemOperationCount=$operations.Count
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
        PSTypeName='OSDStage.StagedApp';Name='FileSystem';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Paths=@($operations | ForEach-Object Path | Select-Object -Unique)
    }
}
