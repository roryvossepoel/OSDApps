function Get-OSDStageUIStagedApps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)

    $manifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDStage\DeviceManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $manifest -or -not ($manifest.PSObject.Properties.Name -contains 'Packages')) {
        throw "Invalid DeviceManifest.json: Packages property is missing: $manifestPath"
    }
    foreach ($app in @($manifest.Packages)) {
        if ($null -ne $app -and -not [string]::IsNullOrWhiteSpace([string]$app.Id)) {
            $app
        }
    }
}

function Get-OSDStageUIStagedIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)

    foreach ($app in @(Get-OSDStageUIStagedApps -WindowsPath $WindowsPath)) {
        [string]$app.Id
    }
}

function Get-OSDStageUITestWindowsPath {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw 'TEMP is unavailable.'
    }
    [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'OSDStage-GUI-Staging-Test'))
}

function Format-OSDStageUIStagedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$App,
        [string]$Vendor
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Vendor -and $Vendor -ne '-') { $lines.Add("Vendor: $Vendor") }
    # Whitelist descriptive manifest fields; do not display arbitrary scripts,
    # custom arguments, installer command lines or authenticated download URLs.
    foreach ($key in @(
        'DisplayName','Id','Source','PackageType','Type','Version','Architecture','Channel',
        'Language','ProductId','SharedComputerLicensing','DeviceBasedLicensing',
        'UpdatesEnabled','InstallMeetingAddin','IncludeVisio','IncludeProject',
        'ExcludeApp','SelectedPackages','DiagnoseOnly','AutoStartWithWindows','PreventPreLoginUpdates',
        'EnableOutlookIntegration','DefaultTheme','InstallTimeoutMinutes'
    )) {
        $property = $App.PSObject.Properties[$key]
        if ($null -eq $property -or $null -eq $property.Value) { continue }
        $value = if ($property.Value -is [array]) {
            @($property.Value) -join ', '
        } else {
            [string]$property.Value
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $lines.Add(('{0}: {1}' -f $key,$value))
        }
    }
    $lines.Add('')
    $lines.Add('Staged for SetupComplete. This does not confirm the app was installed.')
    $lines -join [Environment]::NewLine
}

function Get-OSDStageUIReadOnlySnapshot {
    [CmdletBinding()]
    param(
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$SkipSignatureVerification
    )

    # Only reads files, disk metadata and (optionally) catalog contents.
    # No SetupComplete, DeviceManifest, cache, or configuration mutations.
    $staged = @()
    $manifestPath = $null
    $setupCompletePath = $null
    if ($WindowsPath) {
        $manifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDStage\DeviceManifest.json'
        $setupCompletePath = Join-Path $WindowsPath 'Windows\Setup\Scripts\SetupComplete.cmd'
        $staged = @(Get-OSDStageUIStagedApps -WindowsPath $WindowsPath)
    }

    $catalog = @(Get-OSDStage -Offline:$Offline -ErrorAction Stop)
    # On full Windows inspect any legacy built-in cache with Version=Current
    # without writing metadata or downloading anything. WinPE uses CacheInfo.json.
    $fullWindows = -not (Test-OSDStageWinPE)
    $cache = @(Get-OSDStageCache -ResolveVersions:$fullWindows -VerifySignatures:(-not $SkipSignatureVerification) -ErrorAction Stop)
    $cachePath = $null
    try { $cachePath = Get-OSDStageCachePath } catch { }

    $logFiles = [System.Collections.Generic.List[object]]::new()
    if ($cachePath) {
        foreach ($name in @('Client.log','Runtime.log')) {
            $file = Join-Path $cachePath (Join-Path 'Logs' $name)
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $logFiles.Add([pscustomobject]@{ Label="USB cache: $name"; Path=$file })
            }
        }
    }
    if ($WindowsPath) {
        foreach ($definition in @(
            @{ Label='Device: Runtime.log'; Relative='ProgramData\OSDStage\Logs\Runtime.log' },
            @{ Label='Device: Client.log'; Relative='ProgramData\OSDStage\Logs\Client.log' }
        )) {
            $file = Join-Path $WindowsPath $definition.Relative
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $logFiles.Add([pscustomobject]@{ Label=$definition.Label; Path=$file })
            }
        }
    }

    [pscustomobject]@{
        WindowsPath = $WindowsPath
        ManifestPath = $manifestPath
        ManifestExists = [bool]($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf))
        SetupCompleteExists = [bool]($setupCompletePath -and (Test-Path -LiteralPath $setupCompletePath -PathType Leaf))
        StagedApps = @($staged)
        CatalogApps = @($catalog)
        CacheEntries = @($cache)
        CachePath = $cachePath
        Logs = @($logFiles)
    }
}
