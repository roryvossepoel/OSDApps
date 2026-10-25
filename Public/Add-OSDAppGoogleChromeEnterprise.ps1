function Add-OSDAppGoogleChromeEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [string]$PackageUri,

        [ValidateRange(1,120)]
        [int]$InstallTimeoutMinutes = 10,

        [string]$WindowsPath
    )

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' }
            'x86' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi' }
        }
    }

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
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Source' -Message 'Google Chrome Enterprise will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'
    if ($cachePath) {
        $existingCache = Test-OSDAppBuiltInPayload -Root (Join-Path $cachePath (Join-Path 'BuiltIn\GoogleChromeEnterprise' $Architecture)) -ExpectedExtension '.msi'
        $message = if ($existingCache) { 'Existing cache found; cached MSI will be staged as fallback and refreshed during SetupComplete' } else { 'No existing cache found; cache will be created during SetupComplete' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level $(if ($existingCache) { 'Success' } else { 'Info' }) -Component 'GoogleChromeEnterprise' -Message $message }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'GoogleChromeEnterprise' -Message 'Staging deployment intent to the OS disk' }

    $result = Add-OSDAppGoogleChromeEnterpriseInternal -CachePath $cachePath -WindowsPath $resolvedWindowsPath -Architecture $Architecture -PackageUri $PackageUri -InstallTimeoutMinutes $InstallTimeoutMinutes -StagedRelativePath $stagedRelativePath -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'GoogleChromeEnterprise' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Summary' -Message ("App=GoogleChromeEnterprise; Architecture=$Architecture; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}
