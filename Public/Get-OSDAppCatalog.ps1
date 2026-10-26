function Get-OSDAppCatalog {
    [CmdletBinding()]
    param()

    $configuration = Get-OSDAppConfiguration
    $catalogUri = $configuration.CatalogUri

    if (-not (Test-OSDAppSourceEnabled -Source Repository -Configuration $configuration)) {
        return [pscustomobject]@{
            PSTypeName    = 'OSDApps.CatalogStatus'
            Uri           = $catalogUri
            Scope         = 'Session'
            Enabled       = $false
            Available     = $false
            AppCount      = 0
            SchemaVersion = $null
        }
    }

    if (-not $catalogUri) {
        return [pscustomobject]@{
            PSTypeName       = 'OSDApps.CatalogStatus'
            Uri              = $null
            Scope            = 'Session'
            Enabled          = $true
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
            Enabled          = $true
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
            Enabled          = $true
            Available        = $false
            AppCount = 0
            SchemaVersion    = $null
        }
    }
}
