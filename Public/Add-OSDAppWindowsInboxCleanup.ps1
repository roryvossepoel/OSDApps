function Add-OSDAppWindowsInboxCleanup {
    [CmdletBinding(DefaultParameterSetName='Explicit',SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,ParameterSetName='Explicit')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Remove,

        [Parameter(Mandatory,ParameterSetName='Preset')]
        [ValidateSet('Tested13')]
        [string]$Preset,

        [switch]$DiagnoseOnly,

        [string]$WindowsPath
    )

    # Explicit opt-in. No removals are selected simply by importing OSDApps.
    $selected = if ($PSCmdlet.ParameterSetName -eq 'Preset') {
        @(
            'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.BingWeather',
            'Microsoft.BingNews',
            'Microsoft.BingSearch',
            'Microsoft.Xbox.TCUI',
            'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.MicrosoftOfficeHub',
            'Microsoft.OutlookForWindows',
            'Microsoft.WindowsAlarms',
            'Microsoft.WindowsTerminal',
            'Microsoft.GamingApp'
        )
    }
    else { @($Remove) }

    $selected = @($selected | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or
            $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $_.Contains('..')) {
            throw ('Invalid Windows package name: {0}' -f $_)
        }
        [string]$_
    } | Select-Object -Unique)

    if ($selected.Count -eq 0) { throw 'Specify at least one package to remove.' }

    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $scriptSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppWindowsInboxCleanup.ps1'
    if (-not (Test-Path -LiteralPath $scriptSource -PathType Leaf)) {
        throw ('Built-in cleanup script was not packaged: {0}' -f $scriptSource)
    }

    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stageRoot = Join-Path $target 'Windows\Temp\OSDApps'
    $builtInRoot = Join-Path $stageRoot 'BuiltIn'
    $payloadRoot = Join-Path $builtInRoot 'WindowsInboxCleanup'
    $manifestPath = Join-Path $stageRoot 'DeviceManifest.json'
    $configRelative = 'BuiltIn\WindowsInboxCleanup\config.json'
    $scriptRelative = 'BuiltIn\WindowsInboxCleanup\Install.ps1'

    # Read/validate any existing manifest before writing or replacing the payload.
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $existing = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $existing -or -not ($existing.PSObject.Properties.Name -contains 'Apps')) {
            throw 'Existing OSDApps DeviceManifest.json is invalid.'
        }
        $existing
    }
    else {
        [pscustomobject]@{ SchemaVersion=1; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Apps=@() }
    }

    if (-not $PSCmdlet.ShouldProcess($payloadRoot, ('Stage optional inbox cleanup for {0} selected packages' -f $selected.Count))) {
        return
    }

    New-Item -ItemType Directory -Path $builtInRoot -Force -ErrorAction Stop | Out-Null
    $temporaryRoot = Join-Path $builtInRoot ('.WindowsInboxCleanup-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force -ErrorAction Stop | Out-Null
        $stagedScript = Join-Path $temporaryRoot 'Install.ps1'
        $stagedConfig = Join-Path $temporaryRoot 'config.json'
        Copy-Item -LiteralPath $scriptSource -Destination $stagedScript -ErrorAction Stop
        [ordered]@{ Remove=@($selected) } |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $stagedConfig -Encoding UTF8 -ErrorAction Stop

        $scriptHash = (Get-FileHash -LiteralPath $stagedScript -Algorithm SHA256 -ErrorAction Stop).Hash
        $configHash = (Get-FileHash -LiteralPath $stagedConfig -Algorithm SHA256 -ErrorAction Stop).Hash

        if (Test-Path -LiteralPath $payloadRoot) {
            Remove-Item -LiteralPath $payloadRoot -Recurse -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $temporaryRoot -Destination $payloadRoot -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $app = [pscustomobject]@{
        Id                  = 'WindowsInboxCleanup'
        DisplayName         = 'Windows Inbox App Cleanup'
        Source              = 'BuiltIn'
        PackageType         = 'Script'
        Type                = 'WindowsInboxCleanupScript'
        Version             = '1.0.0'
        Architecture        = 'any'
        Script              = $scriptRelative
        Configuration       = $configRelative
        ScriptSha256        = $scriptHash
        ConfigurationSha256 = $configHash
        DiagnoseOnly        = [bool]$DiagnoseOnly
        SelectedPackages    = @($selected)
    }

    $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop

    Add-OSDAppSetupComplete -WindowsPath $target -Confirm:$false -ErrorAction Stop | Out-Null

    [pscustomobject]@{
        PSTypeName = 'OSDApps.StagedApp'
        Name = 'WindowsInboxCleanup'
        PackageType = 'Script'
        Source = 'BuiltIn'
        WindowsPath = $target
        StagedPath = $payloadRoot
        Version = '1.0.0'
        SelectedCount = $selected.Count
        DiagnoseOnly = [bool]$DiagnoseOnly
    }
}
