function New-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Path
    )

    $appsPath = Join-Path $Path 'Apps'
    $catalogPath = Join-Path $Path 'catalog.json'

    if ($PSCmdlet.ShouldProcess($Path, 'Create OSD Apps repository structure')) {
        New-Item -ItemType Directory -Path $appsPath -Force | Out-Null

        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            [ordered]@{
                SchemaVersion = 1
                GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
                Apps  = @()
            } |
                ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $catalogPath -Encoding UTF8
        }
    }

    [pscustomobject]@{
        PSTypeName = 'OSDApps.Repository'
        Path       = $Path
        Catalog    = $catalogPath
        AppsPath   = $appsPath
    }
}
