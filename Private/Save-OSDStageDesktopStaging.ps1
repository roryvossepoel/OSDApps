function Save-OSDStageDesktopStaging {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Operation, [string]$WindowsPath)

    $ErrorActionPreference='Stop'
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage desktop settings in WinPE after OSDCloud, not on the preparation PC.' }
    Assert-OSDStageDesktopOperation -Operation $Operation

    $target=Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDStage'
    $payloadRoot=Join-Path $stage 'BuiltIn\DesktopSettings'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDStageDesktopSettings.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'DesktopSettings runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Packages') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=2;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Packages=@()} }

    $manifest=Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Packages | Where-Object Id -eq 'DesktopSettings')
    if ($previous.Count -gt 1) { throw 'Duplicate DesktopSettings entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'DesktopSettingsScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.DesktopSettingsSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing DesktopSettings staging is not an intact OSDStage-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert-OSDStageDesktopConfiguration -Configuration $existing
        if ([string]$existing.DeploymentId -ne [string]$manifest.DeploymentId) { throw 'Desktop staging belongs to another deployment.' }
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned DesktopSettings staging directory exists. Nothing was replaced.'
    }

    $operations = @($operations | Where-Object { [string]$_.Kind -ne [string]$Operation.Kind }) + @($Operation)

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'DesktopSettings-Result.json')
        Operations=@($operations)
    }

    Assert-OSDStageDesktopConfiguration -Configuration ([pscustomobject]$config)

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} desktop setting(s) for SetupComplete" -f $operations.Count))) { return }

    if ($Operation.Kind -eq 'StartPins') { Assert-OSDStageOfflineStartPins -WindowsPath $target }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.DesktopSettings-' + [guid]::NewGuid().ToString('N'))
    $backup=$transaction + '.previous'
    $manifestTemp=$manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $committed=$false
    try {
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        Copy-Item -LiteralPath $scriptSource -Destination (Join-Path $transaction 'Install.ps1') -ErrorAction Stop
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $transaction 'config.json') -Encoding UTF8 -ErrorAction Stop

        $scriptHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'Install.ps1') -Algorithm SHA256).Hash
        $configHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'config.json') -Algorithm SHA256).Hash
        $app=[pscustomobject]@{
            Id='DesktopSettings';DisplayName='Windows StartPins & TaskbarPins';Vendor='OSDStage'
            Source='BuiltIn';PackageType='Script';Type='DesktopSettingsScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\DesktopSettings\Install.ps1'
            Configuration='BuiltIn\DesktopSettings\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            DesktopSettingsSchema=1;DesktopOperationCount=$operations.Count
        }
        $manifest=Set-OSDStageManifestApp -Manifest $manifest -App $app
        $manifest.StagedAt=(Get-Date).ToUniversalTime().ToString('o')
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestTemp -Encoding UTF8
        Add-OSDStageSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDStage' -Confirm:$false -ErrorAction Stop | Out-Null

        $commitFiles = {
            if (Test-Path -LiteralPath $payloadRoot) { Move-Item -LiteralPath $payloadRoot -Destination $backup -ErrorAction Stop }
            try {
                Move-Item -LiteralPath $transaction -Destination $payloadRoot -ErrorAction Stop
                Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force -ErrorAction Stop
            }
            catch {
                if (Test-Path -LiteralPath $payloadRoot) { Remove-Item -LiteralPath $payloadRoot -Recurse -Force }
                if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $payloadRoot -ErrorAction Stop }
                throw
            }
        }
        if ($Operation.Kind -eq 'TaskbarPins') {
            Set-OSDStageOfflineTaskbar -WindowsPath $target -Pins @($Operation.Pins) -Commit $commitFiles
        }
        else { & $commitFiles }
        $committed=$true
    }
    finally {
        if ($committed -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if (Test-Path -LiteralPath $transaction) { Remove-Item -LiteralPath $transaction -Recurse -Force }
        if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp -Force }
    }

    [pscustomobject]@{
        PSTypeName='OSDStage.StagedApp';Name='DesktopSettings';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Settings=@($operations | ForEach-Object Kind)
    }
}
