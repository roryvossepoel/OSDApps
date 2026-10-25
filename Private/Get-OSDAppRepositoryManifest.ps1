function Get-OSDAppRepositoryManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )

    $catalogPath = Join-Path $RepositoryPath 'catalog.json'

    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        return [pscustomobject]@{
            SchemaVersion = 1
            GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
            Apps  = @()
        }
    }

    Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
