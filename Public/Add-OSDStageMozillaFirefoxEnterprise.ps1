function Add-OSDStageMozillaFirefoxEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Rapid','ESR')]
        [string]$Channel = 'Rapid',

        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @(
                'en-US','en-GB','nl','de','fr','es-ES','es-MX','it',
                'pt-PT','pt-BR','pl','sv-SE','da','nb-NO','fi','cs',
                'sk','hu','ro','tr','uk','ru','ja','ko','zh-CN','zh-TW'
            ) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        })]
        [ValidatePattern('^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$')]
        [string]$Language = 'en-US',

        [string]$PackageUri,

        [ValidateRange(1,120)]
        [int]$InstallTimeoutMinutes = 10,

        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn

    if (-not $PackageUri) {
        $product = if ($Channel -eq 'ESR') { 'firefox-esr-msi-latest-ssl' } else { 'firefox-msi-latest-ssl' }
        $os = if ($Architecture -eq 'x64') { 'win64' } else { 'win' }
        $PackageUri = "https://download.mozilla.org/?product=$product&os=$os&lang=$Language"
    }

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
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Source' -Message 'Mozilla Firefox Enterprise will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDStage'
    $relativeRoot = Join-Path 'BuiltIn\MozillaFirefoxEnterprise' (Join-Path $Channel (Join-Path $Architecture $Language))

    if ($cachePath) {
        $existingCache = Test-OSDStageBuiltInPayload -Root (Join-Path $cachePath $relativeRoot) -ExpectedExtension '.msi'
        $message = if ($existingCache) { 'Existing cache found; cached MSI will be staged as fallback and refreshed during SetupComplete' } else { 'No existing cache found; cache will be created during SetupComplete' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level $(if ($existingCache) { 'Success' } else { 'Info' }) -Component 'MozillaFirefoxEnterprise' -Message $message }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'MozillaFirefoxEnterprise' -Message 'Staging deployment intent to the OS disk' }

    $result = Add-OSDStageMozillaFirefoxEnterpriseInternal -CachePath $cachePath -WindowsPath $resolvedWindowsPath -Channel $Channel -Architecture $Architecture -Language $Language -PackageUri $PackageUri -InstallTimeoutMinutes $InstallTimeoutMinutes -StagedRelativePath $stagedRelativePath -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDStageSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Success -Component 'MozillaFirefoxEnterprise' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDStageConsole -Level Info -Component 'Summary' -Message ("App=MozillaFirefoxEnterprise; Channel=$Channel; Architecture=$Architecture; Language=$Language; Timeout=$InstallTimeoutMinutes min; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDStageCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB flash drive connected until OOBE is displayed.'
        $script:OSDStageCacheMediaWarningShown = $true
    }

    $result
}
