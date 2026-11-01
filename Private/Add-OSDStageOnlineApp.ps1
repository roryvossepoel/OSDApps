function Add-OSDStageOnlineApp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('MicrosoftCompanyPortal','CMTraceOpen')][string]$Id,
        [ValidateSet('x64','arm64')][string]$Architecture='x64',
        [string]$WindowsPath,
        [bool]$DisableUpdateChecks=$true,
        [int]$InstallTimeoutMinutes=10
    )
    Assert-OSDStageSourceEnabled -Source BuiltIn
    $target = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $stage = Join-Path $target 'Windows\Temp\OSDStage'
    $relative = 'BuiltIn\' + $Id + '\' + $Architecture
    $destination = Join-Path $stage $relative
    $detectedCachePath = $null
    try { $detectedCachePath = Get-OSDStageCachePath } catch { Write-Verbose 'No cache volume; acquire directly during SetupComplete.' }
    $entry = $null
    if ($detectedCachePath) {
        try { $entry = Get-OSDStageOnlineAppCacheEntry -CachePath $detectedCachePath -Id $Id -Architecture $Architecture }
        catch { Write-Verbose 'Cache is unavailable or invalid; a validated download is required during SetupComplete.' }
    }
    $cached = $null -ne $entry
    if (-not $entry) {
        $entry = [pscustomobject]@{
            Id=$Id; DisplayName=$(if($Id -eq 'CMTraceOpen'){'CMTrace Open'}else{'Microsoft Company Portal'})
            Source='BuiltIn'; PackageType='App'
            Type=$(if($Id -eq 'CMTraceOpen'){'VendorMsi'}else{'CompanyPortalAppxBundle'})
            Architecture=$Architecture; AcquisitionPending=$true
        }
    }
    if ($Id -eq 'CMTraceOpen') {
        $entry | Add-Member MsiProperties @(if($DisableUpdateChecks){'DISABLEUPDATECHECKS=1'}) -Force
        $entry | Add-Member InstallTimeoutMinutes $InstallTimeoutMinutes -Force
    }
    if (-not $PSCmdlet.ShouldProcess($destination, "Stage $Id intent and available validated cache")) { return }
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop }
    New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
    if ($cached) {
        Copy-Item -Path (Join-Path (Join-Path $detectedCachePath $relative) '*') -Destination $destination -Recurse -Force -ErrorAction Stop
        Get-OSDStageOnlineAppCacheEntry -CachePath $stage -Id $Id -Architecture $Architecture | Out-Null
    }
    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath) {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else { [pscustomobject]@{SchemaVersion=2; StagedAt=$null; Packages=@()} }
    $manifest = Set-OSDStageManifestApp -Manifest $manifest -App $entry
    $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
    Add-OSDStageSetupComplete -WindowsPath $target -Confirm:$false | Out-Null
    [pscustomobject]@{
        PSTypeName='OSDStage.StagedApp'; Name=$Id; Source='BuiltIn'; PackageType='App'
        Version=$(if($cached){[string]$entry.Version}else{'Current'}); Architecture=$Architecture
        WindowsPath=$target; StagedPath=$destination; CacheAvailable=$cached
    }
}
