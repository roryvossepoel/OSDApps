function Get-OSDStageCatalog {
    [CmdletBinding()]
    param()

    $configuration = Get-OSDStageConfiguration
    $catalogUri = $configuration.CatalogUri

    if (-not (Test-OSDStageSourceEnabled -Source Repository -Configuration $configuration)) {
        return [pscustomobject]@{
            PSTypeName    = 'OSDStage.CatalogStatus'
            Uri           = $catalogUri
            Scope         = 'Session'
            Enabled       = $false
            Available     = $false
            PackageCount      = 0
            SchemaVersion = $null
        }
    }

    if (-not $catalogUri) {
        return [pscustomobject]@{
            PSTypeName       = 'OSDStage.CatalogStatus'
            Uri              = $null
            Scope            = 'Session'
            Enabled          = $true
            Available        = $false
            PackageCount = 0
            SchemaVersion    = $null
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $catalogUri -UseBasicParsing -ErrorAction Stop
        $catalog = $response.Content | ConvertFrom-Json -ErrorAction Stop

        [pscustomobject]@{
            PSTypeName       = 'OSDStage.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Enabled          = $true
            Available        = $true
            PackageCount = @($catalog.Packages).Count
            SchemaVersion    = $catalog.SchemaVersion
        }
    }
    catch {
        [pscustomobject]@{
            PSTypeName       = 'OSDStage.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Enabled          = $true
            Available        = $false
            PackageCount = 0
            SchemaVersion    = $null
        }
    }
}
