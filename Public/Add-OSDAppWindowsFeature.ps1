function Add-OSDAppWindowsFeature {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Enable,
        [string[]]$Disable,
        [string]$WindowsPath
    )

    Assert-OSDAppSourceEnabled -Source BuiltIn
    if (-not (Test-OSDAppWinPE)) { throw 'Stage Windows feature changes in WinPE after OSDCloud, not on the preparation PC.' }

    $enableNames=@($Enable | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $disableNames=@($Disable | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($enableNames.Count -eq 0 -and $disableNames.Count -eq 0) { throw 'Specify at least one feature with -Enable or -Disable.' }

    foreach($name in @($enableNames)+@($disableNames)) {
        if ($name.Length -gt 256 -or $name -match '[\x00-\x1F]') {
            throw "Invalid Windows feature name '$name'."
        }
    }
    $conflicts=@($enableNames | Where-Object { $_ -in $disableNames })
    if ($conflicts.Count -gt 0) { throw "A Windows feature cannot be enabled and disabled in the same call: $($conflicts -join ', ')." }

    $target=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDApps'
    $payloadRoot=Join-Path $stage 'BuiltIn\WindowsFeatures'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDAppWindowsFeatures.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Windows Features runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Apps') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()} }

    $manifest=Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Apps | Where-Object Id -eq 'WindowsFeatures')
    if ($previous.Count -gt 1) { throw 'Duplicate WindowsFeatures entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'WindowsFeatureScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.WindowsFeatureSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing WindowsFeatures staging is not an intact OSDApps-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned WindowsFeatures staging directory exists. Nothing was replaced.'
    }

    $newOperations=@()
    foreach($name in $enableNames){$newOperations += [pscustomobject]@{Action='Enable';Name=[string]$name}}
    foreach($name in $disableNames){$newOperations += [pscustomobject]@{Action='Disable';Name=[string]$name}}
    foreach($operation in $newOperations) {
        $operations=@($operations | Where-Object { [string]$_.Name -ine [string]$operation.Name }) + @($operation)
    }

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=1
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'WindowsFeatures-Result.json')
        Operations=@($operations)
    }

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} Windows feature operation(s) for SetupComplete" -f $operations.Count))) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.WindowsFeatures-' + [guid]::NewGuid().ToString('N'))
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
            Id='WindowsFeatures';DisplayName='Windows optional features';Vendor='OSDApps'
            Source='BuiltIn';PackageType='Script';Type='WindowsFeatureScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\WindowsFeatures\Install.ps1'
            Configuration='BuiltIn\WindowsFeatures\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            WindowsFeatureSchema=1;WindowsFeatureOperationCount=$operations.Count
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
        PSTypeName='OSDApps.StagedApp';Name='WindowsFeatures';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Enabled=@($operations | Where-Object Action -eq 'Enable' | ForEach-Object Name)
        Disabled=@($operations | Where-Object Action -eq 'Disable' | ForEach-Object Name)
    }
}
