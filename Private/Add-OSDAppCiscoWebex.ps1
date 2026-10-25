function Add-OSDAppCiscoWebexInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [Parameter(Mandatory)][string]$PackageUri,
        [bool]$AutoStartWithWindows = $false,
        [bool]$AcceptEula = $true,
        [bool]$PreventPreLoginUpdates = $false,
        [Nullable[bool]]$EnableOutlookIntegration,
        [ValidateSet('Light','Dark')][string]$DefaultTheme,
        [string]$EmailHint,
        [string[]]$AdditionalMsiProperties,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    # Validate optional MSI properties before writing staging files.
    $msiParameters = @{
        AutoStartWithWindows = $AutoStartWithWindows
        AcceptEula = $AcceptEula
        PreventPreLoginUpdates = $PreventPreLoginUpdates
        EnableOutlookIntegration = $EnableOutlookIntegration
        DefaultTheme = $DefaultTheme
        EmailHint = $EmailHint
        AdditionalMsiProperties = $AdditionalMsiProperties
    }
    if (-not $DefaultTheme) { $msiParameters.Remove('DefaultTheme') | Out-Null }
    $msiProperties = @(New-OSDAppCiscoWebexMsiProperties @msiParameters)

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $relativeRoot = Join-Path 'BuiltIn\CiscoWebex' $Architecture
    $destinationBuiltIn = Join-Path $destinationRoot $relativeRoot
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath $relativeRoot } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheHasPayload = Test-OSDAppBuiltInPayload -Root $cacheRoot -ExpectedExtension '.msi'
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Cisco Webex deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force -ErrorAction Stop | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force -ErrorAction Stop
        $stagedMsi = (Resolve-OSDAppBuiltInPayloadPath -Root $destinationBuiltIn -ExpectedExtension '.msi')
        if (-not (Test-Path -LiteralPath $stagedMsi -PathType Leaf)) {
            throw "Cisco Webex cache staging failed; expected MSI: $stagedMsi"
        }
        if ((Get-Item -LiteralPath $stagedMsi).Length -ne (Get-Item -LiteralPath ((Resolve-OSDAppBuiltInPayloadPath -Root $cacheRoot -ExpectedExtension '.msi'))).Length) {
            throw "Cisco Webex cache staging failed; MSI size differs: $stagedMsi"
        }
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $deviceManifest = [pscustomobject]@{
            SchemaVersion = '1.0'
            StagedAt = (Get-Date).ToUniversalTime().ToString('o')
            Apps = @()
        }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = 'CiscoWebex'
        DisplayName = 'Cisco Webex'
        Type = 'VendorMsi'
        Package = $null
        PackageUri = $PackageUri
        Architecture = $Architecture
        MsiProperties = @($msiProperties)
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        CachePreferred = [bool]$CachePath
    }

    Set-OSDAppManifestPayload -App $manifestApp -StagedPath $destinationRoot -AllowPending
    $deviceManifest = Set-OSDAppManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'CiscoWebex' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'CiscoWebex' -Event 'StageTarget' -Message 'Cisco Webex deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'CiscoWebex' -Event 'WebexStageComplete' -Message 'Cisco Webex deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Architecture=$Architecture; InstallTimeoutMinutes=$InstallTimeoutMinutes }

    [pscustomobject]@{
        PSTypeName = 'OSDApps.StagedApp'
        Name = 'CiscoWebex'
        CachePath = $CachePath
        WindowsPath = $WindowsPath
        StagedPath = $destinationBuiltIn
        Source = 'BuiltIn'
        CacheAvailable = $cacheHasPayload
    }
}
