function Set-OSDAppManifestApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$App
    )

    if (-not $App.Id) {
        throw 'Manifest app entry must contain Id.'
    }

    $apps = @()
    if ($Manifest.PSObject.Properties.Name -contains 'Apps' -and $Manifest.Apps) {
        $apps = @(
            $Manifest.Apps |
                Where-Object { [string]$_.Id -ne [string]$App.Id }
        )
    }

    $apps += $App

    if ($Manifest.PSObject.Properties.Name -contains 'Apps') {
        $Manifest.Apps = @($apps)
    }
    else {
        $Manifest | Add-Member -NotePropertyName Apps -NotePropertyValue @($apps)
    }

    # DeviceManifest v2 uses Apps as the single ordered app queue.
    foreach ($legacyProperty in @('Packages','BuiltInApps','InstallOrder')) {
        if ($Manifest.PSObject.Properties.Name -contains $legacyProperty) {
            $Manifest.PSObject.Properties.Remove($legacyProperty)
        }
    }

    $Manifest
}
