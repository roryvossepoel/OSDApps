function Add-OSDStageMozillaFirefoxEnterpriseInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('Rapid','ESR')][string]$Channel = 'Rapid',
        [ValidateSet('x64','x86')][string]$Architecture = 'x64',
        [string]$Language = 'en-US',
        [Parameter(Mandatory)][string]$PackageUri,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$StagedRelativePath = 'Windows\Temp\OSDStage'
    )

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $relativeRoot = Join-Path 'BuiltIn\MozillaFirefoxEnterprise' (Join-Path $Channel (Join-Path $Architecture $Language))
    $destinationBuiltIn = Join-Path $destinationRoot $relativeRoot
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDStage\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath $relativeRoot } else { $null }
    $cacheHasPayload = $cacheRoot -and (Test-OSDStageBuiltInPayload -Root $cacheRoot -ExpectedExtension '.msi')

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Mozilla Firefox Enterprise deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) { Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) { Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='2.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Packages=@() }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = 'MozillaFirefoxEnterprise'
        DisplayName = 'Mozilla Firefox Enterprise'
        Type = 'VendorMsi'
        Package = $null
        Channel = $Channel
        Architecture = $Architecture
        Language = $Language
        PackageUri = $PackageUri
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        CachePreferred = [bool]$CachePath
    }

    Set-OSDStageManifestPayload -App $manifestApp -StagedPath $destinationRoot -AllowPending
    $deviceManifest = Set-OSDStageManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDStageLog -LogPath $clientLogPath -Component 'MozillaFirefoxEnterprise' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDStageLog -LogPath $clientLogPath -Component 'MozillaFirefoxEnterprise' -Event 'StageTarget' -Message 'Mozilla Firefox Enterprise deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDStageLog -LogPath $clientLogPath -Component 'MozillaFirefoxEnterprise' -Event 'FirefoxStageComplete' -Message 'Mozilla Firefox Enterprise deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Channel=$Channel; Architecture=$Architecture; Language=$Language; InstallTimeoutMinutes=$InstallTimeoutMinutes }

    [pscustomobject]@{ PSTypeName='OSDStage.StagedApp'; Name='MozillaFirefoxEnterprise'; CachePath=$CachePath; WindowsPath=$WindowsPath; StagedPath=$destinationBuiltIn; Source='BuiltIn'; CacheAvailable=$cacheHasPayload }
}
