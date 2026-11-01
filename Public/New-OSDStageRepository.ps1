function New-OSDStageRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Path
    )

    $appsPath = Join-Path $Path 'Packages'
    $catalogPath = Join-Path $Path 'catalog.json'

    if ($PSCmdlet.ShouldProcess($Path, 'Create OSDStage repository structure')) {
        New-Item -ItemType Directory -Path $appsPath -Force | Out-Null

        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            [ordered]@{
                SchemaVersion = 2
                GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
                Packages  = @()
            } |
                ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $catalogPath -Encoding UTF8
        }
    }

    [pscustomobject]@{
        PSTypeName = 'OSDStage.Repository'
        Path       = $Path
        Catalog    = $catalogPath
        PackagesPath   = $appsPath
    }
}
