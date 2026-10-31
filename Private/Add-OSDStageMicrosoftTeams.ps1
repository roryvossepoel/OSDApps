function Add-OSDStageMicrosoftTeamsInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('x86','x64','arm64')][string]$Architecture = 'x64',
        [bool]$InstallMeetingAddin = $false,
        [string]$MicrosoftTeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$StagedRelativePath = 'Windows\Temp\OSDStage'
    )

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\MicrosoftTeams'
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDStage\Logs\Client.log' }

    $resolvedArchitecture = $Architecture

    $msixUri = switch ($resolvedArchitecture) {
        'x86' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
        'x64' { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
        'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
    }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath 'BuiltIn\MicrosoftTeams' } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheHasPayload = (
            (Test-OSDStageBuiltInPayload -Root $cacheRoot -ExpectedExtension '.msix') -and
            (Test-Path -LiteralPath (Join-Path $cacheRoot 'teamsbootstrapper.exe') -PathType Leaf)
        )
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft Teams deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='2.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Packages=@() }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = 'MicrosoftTeams'
        DisplayName = 'Microsoft Teams'
        Type = 'MicrosoftTeamsBootstrapper'
        Setup = 'BuiltIn\MicrosoftTeams\teamsbootstrapper.exe'
        OfflinePackage = $null
        InstallMeetingAddin = $InstallMeetingAddin
        Architecture = $resolvedArchitecture
        BootstrapperUri = $MicrosoftTeamsBootstrapperUri
        MsixUri = $msixUri
        CachePreferred = [bool]$CachePath
    }

    Set-OSDStageManifestPayload -App $manifestApp -StagedPath $destinationRoot -AllowPending
    $deviceManifest = Set-OSDStageManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDStageLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDStageLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'StageTarget' -Message 'Microsoft Teams deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDStageLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'MicrosoftTeamsStageComplete' -Message 'Microsoft Teams deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Architecture=$resolvedArchitecture }

    [pscustomobject]@{
        PSTypeName='OSDStage.StagedApp'
        Name='MicrosoftTeams'
        CachePath=$CachePath
        WindowsPath=$WindowsPath
        StagedPath=$destinationBuiltIn
        Source='BuiltIn'
        CacheAvailable=$cacheHasPayload
    }
}