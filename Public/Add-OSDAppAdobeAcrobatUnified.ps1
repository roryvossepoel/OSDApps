function Add-OSDAppAdobeAcrobatUnified {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [string]$PackageUri,

        [ValidateRange(1,120)]
        [int]$InstallTimeoutMinutes = 15,

        [string]$WindowsPath
    )

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip' }
            'x86' { 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip' }
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
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Source' -Message 'Adobe Acrobat Unified will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'

    if ($cachePath) {
        $existingCache = Test-Path -LiteralPath (Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $cachePath (Join-Path 'BuiltIn\AdobeAcrobatUnified' (Join-Path $Architecture 'Package.zip')))) -PathType Leaf
        if ($existingCache) {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'AdobeAcrobatUnified' -Message 'Existing cache found; cached package will be staged as fallback and refreshed during SetupComplete' }
        }
        else {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'AdobeAcrobatUnified' -Message 'No existing cache found; cache will be created during SetupComplete' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'AdobeAcrobatUnified' -Message 'Staging deployment intent to the OS disk' }

    $result = Add-OSDAppAdobeAcrobatUnifiedInternal `
        -CachePath $cachePath `
        -WindowsPath $resolvedWindowsPath `
        -Architecture $Architecture `
        -PackageUri $PackageUri `
        -InstallTimeoutMinutes $InstallTimeoutMinutes `
        -StagedRelativePath $stagedRelativePath `
        -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'AdobeAcrobatUnified' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Summary' -Message ("App=AdobeAcrobatUnified; Architecture=$Architecture; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}
