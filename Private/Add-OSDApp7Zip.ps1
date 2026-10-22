function Add-OSDApp7ZipInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('x64','x86','arm64')][string]$Architecture = 'x64',
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot (Join-Path 'BuiltIn\7Zip' $Architecture)
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath (Join-Path 'BuiltIn\7Zip' $Architecture) } else { $null }
    $cacheHasPayload = $cacheRoot -and (Test-Path -LiteralPath ((Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $cacheRoot 'Package.exe'))) -PathType Leaf)

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage 7Zip deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) { Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='1.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Apps=@() }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = '7Zip'
        DisplayName = '7Zip'
        Type = '7ZipExe'
        Package = (Join-Path 'BuiltIn\7Zip' (Join-Path $Architecture 'Package.exe'))
        Architecture = $Architecture
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        CachePreferred = [bool]$CachePath
    }

    $deviceManifest = Set-OSDAppManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component '7Zip' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDAppLog -LogPath $clientLogPath -Component '7Zip' -Event 'StageTarget' -Message '7Zip deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDAppLog -LogPath $clientLogPath -Component '7Zip' -Event '7ZipStageComplete' -Message '7Zip deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Architecture=$Architecture; InstallTimeoutMinutes=$InstallTimeoutMinutes }

    [pscustomobject]@{ PSTypeName='OSDApps.StagedApp'; Name='7Zip'; CachePath=$CachePath; WindowsPath=$WindowsPath; StagedPath=$destinationBuiltIn; Source='BuiltIn'; CacheAvailable=$cacheHasPayload }
}
