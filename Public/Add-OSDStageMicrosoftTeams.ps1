function Add-OSDStageMicrosoftTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x86','x64','arm64')][string]$Architecture = 'x64',
        [bool]$InstallMeetingAddin = $false,
        [string]$MicrosoftTeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Windows' -Message 'Resolving offline Windows installation' }
    $resolvedWindowsPath = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'Windows' -Message ("Windows installation found at {0}" -f $resolvedWindowsPath) }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Cache' -Message "Detecting configured cache volume" }
    $cachePath = $null
    try {
        $cachePath = Get-OSDStageCachePath
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'Cache' -Message ("OSDCloud cache found at {0}" -f $cachePath) }
    }
    catch {
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Cache' -Message 'No OSDCloud cache volume found' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Source' -Message 'Built-in content will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDStage'

    if ($cachePath) {
        $existingMicrosoftTeamsCache = (
            (Test-OSDStageBuiltInPayload -Root (Join-Path $cachePath 'BuiltIn\MicrosoftTeams') -ExpectedExtension '.msix') -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\MicrosoftTeams\teamsbootstrapper.exe') -PathType Leaf)
        )

        if ($existingMicrosoftTeamsCache) {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'MicrosoftTeams' -Message 'Existing cache found; cached payload will be staged as fallback and refreshed during SetupComplete' }
        }
        else {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'MicrosoftTeams' -Message 'No existing cache found; cache will be created during SetupComplete' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'MicrosoftTeams' -Message 'Staging deployment intent to the OS disk' }
    $result = Add-OSDStageMicrosoftTeamsInternal `
        -CachePath $cachePath `
        -WindowsPath $resolvedWindowsPath `
        -Architecture $Architecture `
        -InstallMeetingAddin $InstallMeetingAddin `
        -MicrosoftTeamsBootstrapperUri $MicrosoftTeamsBootstrapperUri `
        -StagedRelativePath $stagedRelativePath `
        -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDStageSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'MicrosoftTeams' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Summary' -Message ("App=MicrosoftTeams; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDStageCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDStageCacheMediaWarningShown = $true
    }

    $result
}
