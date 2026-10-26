function Add-OSDAppMicrosoft365Apps {
    [CmdletBinding(SupportsShouldProcess)]
    param(
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
        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',
        [string]$WindowsPath
    )

    Assert-OSDAppSourceEnabled -Source BuiltIn

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Windows' -Message 'Resolving offline Windows installation' }
    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Windows' -Message ("Windows installation found at {0}" -f $resolvedWindowsPath) }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message "Detecting configured cache volume" }
    $cachePath = $null
    try {
        $cachePath = Get-OSDAppCachePath
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Cache' -Message ("OSDCloud cache found at {0}" -f $cachePath) }
    }
    catch {
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message 'No OSDCloud cache volume found' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Source' -Message 'Built-in content will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'
    $configurationParameters = @('Channel','Architecture','ProductId','Language','AcceptEula','SharedComputerLicensing','DeviceBasedLicensing','UpdatesEnabled','IncludeVisio','IncludeProject','ExcludeApp','ConfigurationXml')
    $configurationOverridden = @($configurationParameters | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0

    $params = @{
        CachePath=$cachePath; WindowsPath=$resolvedWindowsPath; Channel=$Channel; Architecture=$Architecture;
        ProductId=$ProductId; Language=$Language; AcceptEula=$AcceptEula;
        SharedComputerLicensing=$SharedComputerLicensing; DeviceBasedLicensing=$DeviceBasedLicensing; UpdatesEnabled=$UpdatesEnabled; IncludeVisio=$IncludeVisio; IncludeProject=$IncludeProject;
        OfficeDeploymentToolUri=$OfficeDeploymentToolUri; UseCachedConfiguration=(-not $configurationOverridden); StagedRelativePath=$stagedRelativePath; Confirm=$false
    }
    if ($ExcludeApp) { $params.ExcludeApp = $ExcludeApp }
    if ($ConfigurationXml) { $params.ConfigurationXml = $ConfigurationXml }

    if ($cachePath) {
        $existingOfficeCache = (
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\Office\Data') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\setup.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\configuration.xml') -PathType Leaf)
        )

        if ($existingOfficeCache) {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Microsoft365Apps' -Message 'Existing cache found; configuration compatibility will be checked before staging fallback content' }
        }
        else {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Microsoft365Apps' -Message 'No existing cache found; cache will be created during SetupComplete' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Microsoft365Apps' -Message 'Staging deployment intent to the OS disk' }
    $result = Add-OSDAppMicrosoft365AppsInternal @params

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Microsoft365Apps' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Summary' -Message ("App=Microsoft365Apps; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}