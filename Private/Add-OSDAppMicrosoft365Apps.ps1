function Add-OSDAppMicrosoft365AppsInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$Channel = 'Current',
        [ValidateSet('x64','x86')][string]$Architecture = 'x64',
        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')][string]$ProductId = 'O365ProPlusRetail',
        [string[]]$Language = @('en-us'),
        [bool]$AcceptEula = $true,
        [bool]$SharedComputerLicensing = $false,
        [bool]$DeviceBasedLicensing = $false,
        [bool]$UpdatesEnabled = $true,
        [switch]$IncludeVisio,
        [switch]$IncludeProject,
        [ValidateSet('Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word')]
        [string[]]$ExcludeApp,
        [string]$ConfigurationXml,
        [bool]$UseCachedConfiguration = $true,
        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    if ($SharedComputerLicensing -and $DeviceBasedLicensing) {
        throw 'SharedComputerLicensing and DeviceBasedLicensing cannot both be enabled.'
    }

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\Microsoft365Apps'
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath 'BuiltIn\Microsoft365Apps' } else { $null }
    $cacheConfig = if ($cacheRoot) { Join-Path $cacheRoot 'configuration.xml' } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheInfoPath = Join-Path $cacheRoot 'CacheInfo.json'
        if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
            try {
                $cacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $cacheValidation = Test-OSDAppOfficeCacheGeneration `
                    -OfficeRoot $cacheRoot `
                    -ExpectedVersion ([string]$cacheInfo.Version) `
                    -Architecture $(if ([string]$cacheInfo.Architecture -eq 'x86') { 'x86' } else { 'x64' }) `
                    -PassThru
                $cacheHasPayload = $cacheValidation.Valid
            }
            catch { $cacheHasPayload = $false }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft 365 Apps deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    $configPath = Join-Path $destinationBuiltIn 'configuration.xml'

    $usedCachedConfiguration = $false
    if ($ConfigurationXml) {
        Test-OSDAppOfficeConfigurationXml -Path $ConfigurationXml | Out-Null
        Copy-Item -LiteralPath $ConfigurationXml -Destination $configPath -Force
    }
    elseif ($UseCachedConfiguration -and $cacheHasPayload -and (Test-Path -LiteralPath $cacheConfig -PathType Leaf)) {
        Copy-Item -LiteralPath $cacheConfig -Destination $configPath -Force
        $usedCachedConfiguration = $true
    }
    else {
        if (-not $Language -or @($Language).Count -eq 0) { throw 'At least one Office language must be specified.' }
        New-OSDAppOfficeConfiguration -Path $configPath `
            -Channel $Channel -Architecture $Architecture -ProductId $ProductId `
            -Language $Language -AcceptEula $AcceptEula -UpdatesEnabled $UpdatesEnabled `
            -SharedComputerLicensing $SharedComputerLicensing -DeviceBasedLicensing $DeviceBasedLicensing `
            -ExcludeApp $ExcludeApp -IncludeVisio:$IncludeVisio -IncludeProject:$IncludeProject
    }

    $payloadProfile = Get-OSDAppOfficePayloadProfile -Path $configPath
    if ($payloadProfile.Architecture) { $Architecture = $payloadProfile.Architecture }
    $compatibilityReasons = @()
    if ($cacheHasPayload) {
        $compatibility = Test-OSDAppOfficeCacheCompatibility -OfficeRoot $cacheRoot -ConfigurationPath $configPath
        $cacheHasPayload = $compatibility.Compatible
        $compatibilityReasons = @($compatibility.Reasons)
        if ($cacheHasPayload) {
            # Preserve deployment intent; copy only payload and its provenance.
            foreach ($name in @('setup.exe','Office')) {
                Copy-Item -LiteralPath (Join-Path $cacheRoot $name) -Destination $destinationBuiltIn -Recurse -Force
            }
            $cacheInfo | Add-Member -NotePropertyName PayloadProfile -NotePropertyValue $compatibility.CachedProfile -Force
            $cacheInfo | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $destinationBuiltIn 'CacheInfo.json') -Encoding UTF8
        }
        else {
            Write-Warning ('Office cache does not match the requested configuration. Online acquisition is required. ' + ($compatibilityReasons -join ' '))
        }
        Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeCacheCompatibility' -Message 'Office cache compared with deployment configuration.' -Data @{ Compatible=$cacheHasPayload; Reasons=($compatibilityReasons -join ' ') }
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='1.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Apps=@() }
    }

    $manifestApp = [pscustomobject]@{
        Source = 'BuiltIn'
        Id = 'Microsoft365Apps'
        DisplayName = 'Microsoft 365 Apps'
        Type = 'OfficeDeploymentTool'
        Configuration = 'BuiltIn\Microsoft365Apps\configuration.xml'
        Setup = 'BuiltIn\Microsoft365Apps\setup.exe'
        Offline = $true
        Architecture = $Architecture
        Channel = $payloadProfile.Channel
        ProductId = @($payloadProfile.Products)[0]
        Language = @($payloadProfile.Languages | Select-Object -Unique)
        AcceptEula = $AcceptEula
        SharedComputerLicensing = $SharedComputerLicensing
        DeviceBasedLicensing = $DeviceBasedLicensing
        UpdatesEnabled = $UpdatesEnabled
        IncludeVisio = 'visioproretail' -in $payloadProfile.Products
        IncludeProject = 'projectproretail' -in $payloadProfile.Products
        ExcludeApp = @($ExcludeApp)
        ConfigurationSource = if ($ConfigurationXml) { 'CustomXml' } elseif ($usedCachedConfiguration) { 'Cache' } else { 'Generated' }
        OfficeDeploymentToolUri = $OfficeDeploymentToolUri
        CachePreferred = [bool]$CachePath
    }

    $deviceManifest = Set-OSDAppManifestApp -Manifest $deviceManifest -App $manifestApp
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'StageTarget' -Message 'Microsoft 365 Apps deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeStageComplete' -Message 'Microsoft 365 Apps deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath }

    [pscustomobject]@{
        PSTypeName='OSDApps.StagedApp'
        Name='Microsoft365Apps'
        CachePath=$CachePath
        WindowsPath=$WindowsPath
        StagedPath=$destinationBuiltIn
        Source='BuiltIn'
        CacheAvailable=$cacheHasPayload
        CacheCompatibilityReasons=@($compatibilityReasons)
    }
}
