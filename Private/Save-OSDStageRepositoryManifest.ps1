function Save-OSDStageRepositoryManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RepositoryPath
    )

    New-Item -ItemType Directory -Path $RepositoryPath -Force | Out-Null
    $Manifest.GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')

    $catalogPath = Join-Path $RepositoryPath 'catalog.json'
    $Manifest |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $catalogPath -Encoding UTF8

    Get-Item -LiteralPath $catalogPath
}
