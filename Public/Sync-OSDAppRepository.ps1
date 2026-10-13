function Sync-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Name,

        [switch]$Prune,

        [string[]]$PinnedId
    )

    if ($Prune -and $Name) {
        throw 'Prune requires a complete catalog synchronization. Do not combine Prune with Name.'
    }
    if ($PinnedId -and -not $Prune) {
        throw 'PinnedId is only valid together with Prune.'
    }

    $sourceUri = (Get-OSDAppConfiguration).CatalogUri

    if (-not $sourceUri) {
        throw 'No OSD App Catalog is configured. Set CatalogUri with Set-OSDAppConfiguration first.'
    }

    $cachePath = Get-OSDAppCachePath

    $action = if ($Prune) {
        'Reconcile the complete repository catalog and prune stale cache content'
    }
    else {
        "Synchronize repository cache$(if ($Name) { ': ' + ($Name -join ', ') } else { '' })"
    }
    if (-not $PSCmdlet.ShouldProcess($cachePath, $action)) { return }

    Sync-OSDAppCache `
        -CatalogUri $sourceUri `
        -CachePath $cachePath `
        -Name $Name `
        -Prune:$Prune `
        -PinnedId $PinnedId `
        -WhatIf:$false `
        -Confirm:$false
}
