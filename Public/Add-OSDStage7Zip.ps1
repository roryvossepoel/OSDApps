function Add-OSDStage7Zip {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86','arm64')]
        [string]$Architecture = 'x64',

        [ValidateRange(1,120)]
        [int]$InstallTimeoutMinutes = 10,

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
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Source' -Message '7Zip will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDStage'
    if ($cachePath) {
        $existingCache = Test-OSDStageBuiltInPayload -Root (Join-Path $cachePath (Join-Path 'BuiltIn\7Zip' $Architecture)) -ExpectedExtension '.exe'
        $message = if ($existingCache) { 'Existing cache found; cached EXE will be staged as fallback and refreshed during SetupComplete' } else { 'No existing cache found; cache will be created during SetupComplete' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level $(if ($existingCache) { 'Success' } else { 'Info' }) -Component '7Zip' -Message $message }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component '7Zip' -Message 'Staging deployment intent to the OS disk' }

    if (-not $PSCmdlet.ShouldProcess($resolvedWindowsPath, 'Stage 7Zip and integrate SetupComplete')) { return }

    $result = Add-OSDStage7ZipInternal -CachePath $cachePath -WindowsPath $resolvedWindowsPath -Architecture $Architecture -InstallTimeoutMinutes $InstallTimeoutMinutes -StagedRelativePath $stagedRelativePath -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDStageSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component '7Zip' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Summary' -Message ("App=7Zip; Architecture=$Architecture; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDStageCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDStageCacheMediaWarningShown = $true
    }

    $result
}
