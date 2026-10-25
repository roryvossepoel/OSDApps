function Get-OSDAppCatalog {
    [CmdletBinding()]
    param()

    $catalogUri = (Get-OSDAppConfiguration).CatalogUri

    if (-not $catalogUri) {
        return [pscustomobject]@{
            PSTypeName       = 'OSDApps.CatalogStatus'
            Uri              = $null
            Scope            = 'Session'
            Available        = $false
            AppCount = 0
            SchemaVersion    = $null
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $catalogUri -UseBasicParsing -ErrorAction Stop
        $catalog = $response.Content | ConvertFrom-Json -ErrorAction Stop

        [pscustomobject]@{
            PSTypeName       = 'OSDApps.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Available        = $true
            AppCount = @($catalog.Apps).Count
            SchemaVersion    = $catalog.SchemaVersion
        }
    }
    catch {
        [pscustomobject]@{
            PSTypeName       = 'OSDApps.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Available        = $false
            AppCount = 0
            SchemaVersion    = $null
        }
    }
}
