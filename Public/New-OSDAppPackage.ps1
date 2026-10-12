function New-OSDAppPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $installScript = Join-Path $resolvedSource 'Install.ps1'

    if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
        throw "Install.ps1 must exist at the root of the source folder: $resolvedSource"
    }

    $packagePath = Join-Path $OutputPath 'Package.zip'
    if (-not $PSCmdlet.ShouldProcess($packagePath, "Create OSD Apps package $Id $Version")) {
        return
    }

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    if (Test-Path -LiteralPath $packagePath) {
        Remove-Item -LiteralPath $packagePath -Force
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OSDApps-" + [guid]::NewGuid().Guid)
    $tempPackage = Join-Path $tempRoot 'Package'

    try {
        New-Item -ItemType Directory -Path $tempPackage -Force | Out-Null
        Copy-Item -Path (Join-Path $resolvedSource '*') -Destination $tempPackage -Recurse -Force

        Compress-Archive -Path $tempPackage -DestinationPath $packagePath -CompressionLevel Optimal

        [pscustomobject]@{
            PSTypeName = 'OSDApps.Package'
            Id          = $Id
            Version     = $Version
            PackagePath = $packagePath
            Sha256      = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
