function Add-OSDAppZoomWorkplace {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [switch]$NoDesktopShortcut,
        [string]$SsoHost,
        [hashtable]$ZConfig,
        [hashtable]$ZRecommend,
        [string]$PackageUri,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64' }
            'arm64' { 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=winarm64' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Windows' -Message 'Resolving offline Windows installation' }
    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Windows' -Message ("Windows installation found at {0}" -f $resolvedWindowsPath) }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message 'Detecting configured cache volume' }
    $cachePath = $null
    try {
        $cachePath = Get-OSDAppCachePath
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Cache' -Message ("OSDCloud cache found at {0}" -f $cachePath) }
    }
    catch {
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message 'No OSDCloud cache volume found' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Source' -Message 'Zoom Workplace will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'
    if ($cachePath) {
        $existingCache = Test-Path -LiteralPath (Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $cachePath (Join-Path 'BuiltIn\ZoomWorkplace' (Join-Path $Architecture 'Package.msi')))) -PathType Leaf
        $message = if ($existingCache) { 'Existing cached MSI will be staged to the OS disk and refreshed during SetupComplete' } else { 'No cached MSI found; cache will be populated during SetupComplete' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level $(if ($existingCache) { 'Success' } else { 'Info' }) -Component 'ZoomWorkplace' -Message $message }
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedWindowsPath, 'Stage Zoom Workplace and integrate SetupComplete')) { return }

    $addParams = @{
        CachePath = $cachePath
        WindowsPath = $resolvedWindowsPath
        Architecture = $Architecture
        PackageUri = $PackageUri
        NoDesktopShortcut = $NoDesktopShortcut
        SsoHost = $SsoHost
        ZConfig = $ZConfig
        ZRecommend = $ZRecommend
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        StagedRelativePath = $stagedRelativePath
        Confirm = $false
    }
    $result = Add-OSDAppZoomWorkplaceInternal @addParams

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'ZoomWorkplace' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Summary' -Message ("Application=ZoomWorkplace; Architecture=$Architecture; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }
    $result
}
