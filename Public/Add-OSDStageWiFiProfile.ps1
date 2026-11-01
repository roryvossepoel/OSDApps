function Add-OSDStageWiFiProfile {
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='File')]
    param(
        [Parameter(Mandatory,ParameterSetName='File')][ValidateNotNullOrEmpty()][string[]]$Path,
        [Parameter(Mandatory,ParameterSetName='Settings')][ValidateNotNullOrEmpty()][string]$SSID,
        [Parameter(Mandatory,ParameterSetName='Settings')][ValidateSet('WPA2Personal','WPA3Personal','Open')][string]$Security,
        [Parameter(ParameterSetName='Settings')][object]$Password,
        [Parameter(ParameterSetName='Settings')][string]$ProfileName,
        [Parameter(ParameterSetName='Settings')][ValidateSet('Auto','Manual')][string]$ConnectionMode='Auto',
        [Parameter(ParameterSetName='Settings')][switch]$Hidden,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage Wi-Fi profile changes in WinPE after OSDCloud, not on the preparation PC.' }

    # Read and validate every input before changing offline staging.
    if($PSCmdlet.ParameterSetName -eq 'File') {
        $newOperations=@(foreach($file in $Path) { Read-OSDStageWiFiProfile -LiteralPath $file })
    }
    else {
        $settings=@{SSID=$SSID;Security=$Security;ConnectionMode=$ConnectionMode;Hidden=$Hidden}
        if($PSBoundParameters.ContainsKey('Password')){$settings.Password=$Password}
        if($PSBoundParameters.ContainsKey('ProfileName')){$settings.ProfileName=$ProfileName}
        $newOperations=@(New-OSDStageWiFiProfileDefinition @settings)
    }

    $target=Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage=Join-Path $target 'Windows\Temp\OSDStage'
    $payloadRoot=Join-Path $stage 'BuiltIn\WiFiProfiles'
    $manifestPath=Join-Path $stage 'DeviceManifest.json'
    $moduleRoot=Split-Path $PSScriptRoot -Parent
    $scriptSource=Join-Path $moduleRoot 'Runtime\Invoke-OSDStageWiFiProfiles.ps1'

    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) { throw 'Wi-Fi profiles runtime script is missing from this module.' }

    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Packages') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=2;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Packages=@()} }

    $manifest=Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $previous=@($manifest.Packages | Where-Object Id -eq 'WiFiProfiles')
    if ($previous.Count -gt 1) { throw 'Duplicate WiFiProfiles entry in device manifest.' }

    $operations=@()
    $configPath=Join-Path $payloadRoot 'config.json'
    $installedScript=Join-Path $payloadRoot 'Install.ps1'
    if ($previous.Count -eq 1) {
        $entry=$previous[0]
        if ([string]$entry.Source -ne 'BuiltIn' -or [string]$entry.Type -ne 'WiFiProfileScript' -or
            [string]$entry.PackageType -ne 'Script' -or [int]$entry.WiFiProfileSchema -ne 1 -or
            -not (Test-Path -LiteralPath $installedScript -PathType Leaf) -or
            -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash -ne [string]$entry.ScriptSha256 -or
            (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne [string]$entry.ConfigurationSha256) {
            throw 'Existing WiFiProfiles staging is not an intact OSDStage-owned built-in. Nothing was replaced.'
        }
        $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $operations=@($existing.Operations)
    }
    elseif (Test-Path -LiteralPath $payloadRoot) {
        throw 'Unowned WiFiProfiles staging directory exists. Nothing was replaced.'
    }

    foreach($operation in $newOperations) {
        $operations=@($operations | Where-Object { [string]$_.Name -cne [string]$operation.Name }) + @($operation)
    }

    $resultDirectory=Split-Path ([string]$manifest.Runtime.ResultPath) -Parent
    $config=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$manifest.DeploymentId
        ResultPath=(Join-Path $resultDirectory 'WiFiProfiles-Result.json')
        Operations=@($operations)
    }

    if (-not $PSCmdlet.ShouldProcess($payloadRoot,("Stage {0} Wi-Fi profile operation(s) for SetupComplete" -f $operations.Count))) { return }

    $builtInRoot=Split-Path $payloadRoot -Parent
    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null
    $transaction=Join-Path $builtInRoot ('.WiFiProfiles-' + [guid]::NewGuid().ToString('N'))
    $backup=$transaction + '.previous'
    $manifestTemp=$manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $promoted=$false;$backedUp=$false;$committed=$false
    try {
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        Protect-OSDStageWiFiDirectory -LiteralPath $transaction
        Copy-Item -LiteralPath $scriptSource -Destination (Join-Path $transaction 'Install.ps1') -ErrorAction Stop
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $transaction 'config.json') -Encoding UTF8 -ErrorAction Stop

        $scriptHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'Install.ps1') -Algorithm SHA256).Hash
        $configHash=(Get-FileHash -LiteralPath (Join-Path $transaction 'config.json') -Algorithm SHA256).Hash
        $app=[pscustomobject]@{
            Id='WiFiProfiles';DisplayName='Wi-Fi profiles';Vendor='OSDStage'
            Source='BuiltIn';PackageType='Script';Type='WiFiProfileScript';Version='1.0.0';Architecture='any'
            Script='BuiltIn\WiFiProfiles\Install.ps1'
            Configuration='BuiltIn\WiFiProfiles\config.json'
            ScriptSha256=$scriptHash;ConfigurationSha256=$configHash
            WiFiProfileSchema=1;WiFiProfileOperationCount=$operations.Count
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
        PSTypeName='OSDStage.StagedApp';Name='WiFiProfiles';PackageType='Script';Source='BuiltIn'
        WindowsPath=$target;StagedPath=$payloadRoot;Version='1.0.0';OperationCount=$operations.Count
        Profiles=@($operations | ForEach-Object Name)
    }
}
