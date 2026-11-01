function Set-OSDStageManifestApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$App
    )

    if (-not $App.Id) {
        throw 'Manifest app entry must contain Id.'
    }

    $apps = @()
    if ($Manifest.PSObject.Properties.Name -contains 'Packages' -and $Manifest.Packages) {
        $apps = @(
            $Manifest.Packages |
                Where-Object { [string]$_.Id -ne [string]$App.Id }
        )
    }

    $apps += $App

    if ($Manifest.PSObject.Properties.Name -contains 'Packages') {
        $Manifest.Packages = @($apps)
    }
    else {
        $Manifest | Add-Member -NotePropertyName Packages -NotePropertyValue @($apps)
    }

    $Manifest
}
