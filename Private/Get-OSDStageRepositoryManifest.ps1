function Get-OSDStageRepositoryManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )

    $catalogPath = Join-Path $RepositoryPath 'catalog.json'

    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        return [pscustomobject]@{
            SchemaVersion = 2
            GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
            Packages  = @()
        }
    }

    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-OSDStageCatalog -Catalog $catalog
    $catalog
}
