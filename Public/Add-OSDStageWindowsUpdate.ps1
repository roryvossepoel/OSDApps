function Add-OSDStageWindowsUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$IncludeDrivers,
        [switch]$ScanOnly,
        [ValidateRange(5,180)][int]$TimeoutMinutes=30,
        [string]$WindowsPath
    )

    $ErrorActionPreference='Stop'
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage Windows Update in WinPE after OSDCloud, not on the preparation PC.' }

    $target=Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDStage'
    $payloadRoot=Join-Path $stage 'BuiltIn\WindowsUpdate'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDStageWindowsUpdate.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Windows Update runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Packages') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=2;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Packages=@()} }

    $manifest=Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Packages | Where-Object Id -eq 'WindowsUpdate')
    if ($previous.Count -gt 1) { throw 'Duplicate WindowsUpdate entry in device manifest.' }

    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'WindowsUpdateScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.WindowsUpdateSchema -ne 1 -or
            [string]$entry.Script -ne 'BuiltIn\WindowsUpdate\Install.ps1' -or
            [string]$entry.Configuration -ne 'BuiltIn\WindowsUpdate\config.json' -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing WindowsUpdate staging is not an intact OSDStage-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert-OSDStageWindowsUpdateConfiguration -Configuration $existing
        if ([string]$existing.DeploymentId -ne [string]$manifest.DeploymentId) { throw 'Windows Update staging belongs to another deployment.' }
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned WindowsUpdate staging directory exists. Nothing was replaced.'
    }

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'WindowsUpdate-Result.json')
        IncludeDrivers=[bool]$IncludeDrivers
        ScanOnly=[bool]$ScanOnly
        TimeoutMinutes=$TimeoutMinutes
    }

    Assert-OSDStageWindowsUpdateConfiguration -Configuration ([pscustomobject]$config)

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,'Stage Windows Update as the last SetupComplete step')) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.WindowsUpdate-' + [guid]::NewGuid().ToString('N'))
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
            Id='WindowsUpdate';DisplayName='Windows Update';Vendor='OSDStage'
            Source='BuiltIn';PackageType='Script';Type='WindowsUpdateScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\WindowsUpdate\Install.ps1'
            Configuration='BuiltIn\WindowsUpdate\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            WindowsUpdateSchema=1
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
        PSTypeName='OSDStage.StagedApp';Name='WindowsUpdate';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';IncludeDrivers=[bool]$IncludeDrivers;ScanOnly=[bool]$ScanOnly
        NetworkRequired=$true;ExecutionOrder='Last'
    }
}
