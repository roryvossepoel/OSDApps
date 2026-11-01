function Add-OSDStageCiscoWebex {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [bool]$AutoStartWithWindows = $false,
        [bool]$AcceptEula = $true,
        [bool]$PreventPreLoginUpdates = $false,
        [Nullable[bool]]$EnableOutlookIntegration,
        [ValidateSet('Light','Dark')][string]$DefaultTheme,
        [string]$EmailHint,
        [string[]]$AdditionalMsiProperties,
        [string]$PackageUri,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi' }
            'arm64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Windows' -Message 'Resolving offline Windows installation' }
    $resolvedWindowsPath = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'Windows' -Message ("Windows installation found at {0}" -f $resolvedWindowsPath) }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Cache' -Message 'Detecting configured cache volume' }
    $cachePath = $null
    try {
        $cachePath = Get-OSDStageCachePath
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'Cache' -Message ("OSDCloud cache found at {0}" -f $cachePath) }
    }
    catch {
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Cache' -Message 'No OSDCloud cache volume found' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Source' -Message 'Cisco Webex will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDStage'
    if ($cachePath) {
        $existingCache = Test-OSDStageBuiltInPayload -Root (Join-Path $cachePath (Join-Path 'BuiltIn\CiscoWebex' $Architecture)) -ExpectedExtension '.msi'
        $message = if ($existingCache) { 'Existing cached MSI will be staged to the OS disk and refreshed during SetupComplete' } else { 'No cached MSI found; cache will be populated during SetupComplete' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level $(if ($existingCache) { 'Success' } else { 'Info' }) -Component 'CiscoWebex' -Message $message }
    }

    $addParams = @{
        CachePath = $cachePath
        WindowsPath = $resolvedWindowsPath
        Architecture = $Architecture
        PackageUri = $PackageUri
        AutoStartWithWindows = $AutoStartWithWindows
        AcceptEula = $AcceptEula
        PreventPreLoginUpdates = $PreventPreLoginUpdates
        EnableOutlookIntegration = $EnableOutlookIntegration
        DefaultTheme = $DefaultTheme
        EmailHint = $EmailHint
        AdditionalMsiProperties = $AdditionalMsiProperties
        InstallTimeoutMinutes = $InstallTimeoutMinutes
        StagedRelativePath = $stagedRelativePath
        Confirm = $false
    }
    if (-not $DefaultTheme) { $addParams.Remove('DefaultTheme') | Out-Null }
    $result = Add-OSDStageCiscoWebexInternal @addParams

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDStageSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'CiscoWebex' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Summary' -Message ("App=CiscoWebex; Architecture=$Architecture; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDStageCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDStageCacheMediaWarningShown = $true
    }
    $result
}
