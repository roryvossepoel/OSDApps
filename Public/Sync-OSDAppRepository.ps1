function Sync-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Name,

        [switch]$Prune,

        [string[]]$PinnedId,

        [ValidateSet('x64','arm64')]
        [string]$Architecture
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
    if ($Architecture) { $action += " for $Architecture" }
    if (-not $PSCmdlet.ShouldProcess($cachePath, $action)) { return }

    $variantParameters = @{}
    if ($PSBoundParameters.ContainsKey('Architecture')) { $variantParameters.Architecture = $Architecture }

    Sync-OSDAppCache @variantParameters `
        -CatalogUri $sourceUri `
        -CachePath $cachePath `
        -Name $Name `
        -Prune:$Prune `
        -PinnedId $PinnedId `
        -WhatIf:$false `
        -Confirm:$false
}
