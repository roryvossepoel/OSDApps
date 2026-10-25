function Add-OSDAppAdobeAcrobatUnifiedInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('x64','x86')][string]$Architecture = 'x64',
        [Parameter(Mandatory)][string]$PackageUri,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 15,
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    # Use the same architecture-specific relative path for USB cache,
    # WinPE staging, DeviceManifest and the SetupComplete runtime.
    $relativeRoot = Join-Path 'BuiltIn\AdobeAcrobatUnified' $Architecture
    $destinationBuiltIn = Join-Path $destinationRoot $relativeRoot
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath $relativeRoot } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheHasPayload = Test-OSDAppBuiltInPayload -Root $cacheRoot -ExpectedExtension '.zip'
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Adobe Acrobat Unified deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force -ErrorAction Stop
        $stagedArchive = (Resolve-OSDAppBuiltInPayloadPath -Root $destinationBuiltIn -ExpectedExtension '.zip')
        if (-not (Test-Path -LiteralPath $stagedArchive -PathType Leaf)) {
            throw "Adobe Acrobat Unified cache staging failed; expected archive: $stagedArchive"
        }
        if ((Get-Item -LiteralPath $stagedArchive).Length -ne (Get-Item -LiteralPath ((Resolve-OSDAppBuiltInPayloadPath -Root $cacheRoot -ExpectedExtension '.zip'))).Length) {
            throw "Adobe Acrobat Unified cache staging failed; archive size differs: $stagedArchive"
        }
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{
            SchemaVersion='1.0'
            StagedAt=(Get-Date).ToUniversalTime().ToString('o')
            Apps=@()
        }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = 'AdobeAcrobatUnified'
        DisplayName = 'Adobe Acrobat Unified'
        Type = 'AdobeAcrobatUnifiedZip'
        Package = $null
        Architecture = $Architecture
        PackageUri = $PackageUri
        CachePreferred = [bool]$CachePath
        InstallArguments = '/sAll /msi ADDLOCAL=ALL'
        InstallTimeoutMinutes = $InstallTimeoutMinutes
    }

    Set-OSDAppManifestPayload -App $manifestApp -StagedPath $destinationRoot -AllowPending
    $deviceManifest = Set-OSDAppManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'StageTarget' -Message 'Adobe Acrobat Unified deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'AdobeStageComplete' -Message 'Adobe Acrobat Unified deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Architecture=$Architecture; InstallTimeoutMinutes=$InstallTimeoutMinutes }

    [pscustomobject]@{
        PSTypeName='OSDApps.StagedApp'
        Name='AdobeAcrobatUnified'
        CachePath=$CachePath
        WindowsPath=$WindowsPath
        StagedPath=$destinationBuiltIn
        Source='BuiltIn'
        CacheAvailable=$cacheHasPayload
    }
}
