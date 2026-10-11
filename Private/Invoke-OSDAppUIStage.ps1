function Get-OSDAppUIStagedApps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)

    $manifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDApps\DeviceManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $manifest -or -not ($manifest.PSObject.Properties.Name -contains 'Apps')) {
        throw "Invalid DeviceManifest.json: Apps property is missing: $manifestPath"
    }
    foreach ($app in @($manifest.Apps)) {
        if ($null -ne $app -and -not [string]::IsNullOrWhiteSpace([string]$app.Id)) {
            $app
        }
    }
}

function Get-OSDAppUIStagedIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)

    foreach ($app in @(Get-OSDAppUIStagedApps -WindowsPath $WindowsPath)) {
        [string]$app.Id
    }
}

function Get-OSDAppUITestWindowsPath {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw 'TEMP is unavailable.'
    }
    [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'OSDApps-GUI-Staging-Test'))
}

function Format-OSDAppUIStagedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Application,
        [string]$Vendor
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Vendor -and $Vendor -ne '-') { $lines.Add("Vendor: $Vendor") }
    # Whitelist descriptive manifest fields; do not display arbitrary scripts,
    # custom arguments, installer command lines or authenticated download URLs.
    foreach ($key in @(
        'DisplayName','Id','Source','Type','Version','Architecture','Channel',
        'Language','ProductId','SharedComputerLicensing','DeviceBasedLicensing',
        'UpdatesEnabled','InstallMeetingAddin','IncludeVisio','IncludeProject',
        'ExcludeApp','AutoStartWithWindows','PreventPreLoginUpdates',
        'EnableOutlookIntegration','DefaultTheme','InstallTimeoutMinutes'
    )) {
        $property = $Application.PSObject.Properties[$key]
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
    $lines.Add('Staged for SetupComplete. This does not confirm the application was installed.')
    $lines -join [Environment]::NewLine
}

function Get-OSDAppUIReadOnlySnapshot {
    [CmdletBinding()]
    param(
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$VerifySignatures
    )

    # Only reads files, disk metadata and (optionally) catalog contents.
    # No SetupComplete, DeviceManifest, cache, or configuration mutations.
    $staged = @()
    $manifestPath = $null
    $setupCompletePath = $null
    if ($WindowsPath) {
        $manifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDApps\DeviceManifest.json'
        $setupCompletePath = Join-Path $WindowsPath 'Windows\Setup\Scripts\SetupComplete.cmd'
        $staged = @(Get-OSDAppUIStagedApps -WindowsPath $WindowsPath)
    }

    $catalog = @(Get-OSDApp -Offline:$Offline -ErrorAction Stop)
    # On full Windows inspect any legacy built-in cache with Version=Current
    # without writing metadata or downloading anything. WinPE uses CacheInfo.json.
    $cache = @(Get-OSDAppCache -ResolveVersions:(-not (Test-OSDAppWinPE)) -VerifySignatures:$VerifySignatures -ErrorAction Stop)
    $cachePath = $null
    try { $cachePath = Get-OSDAppCachePath } catch { }

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
            @{ Label='Device: Runtime.log'; Relative='ProgramData\OSDApps\Logs\Runtime.log' },
            @{ Label='Device: Client.log'; Relative='ProgramData\OSDApps\Logs\Client.log' }
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
