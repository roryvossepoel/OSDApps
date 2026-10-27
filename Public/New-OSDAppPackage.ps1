function New-OSDAppPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputPath,

        [ValidateSet('App','Script','Font','Certificate','Driver','Image')]
        [string]$PackageType = 'App'
    )

    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $installScript = Join-Path $resolvedSource 'Install.ps1'

    if ($PackageType -eq 'Image') {
        Get-OSDAppImageFile -PayloadRoot $resolvedSource | Out-Null
    }
    elseif ($PackageType -eq 'Driver') {
        Get-OSDAppDriverInfFiles -PayloadRoot $resolvedSource | Out-Null
    }
    elseif ($PackageType -eq 'Certificate') {
        Get-OSDAppCertificatePackageOperations -PayloadRoot $resolvedSource -Store CA | Out-Null
    }
    elseif ($PackageType -eq 'Font') {
        $fontFiles = @(
            Get-ChildItem -LiteralPath $resolvedSource -File -Recurse -ErrorAction Stop |
                Where-Object { $_.Extension.ToLowerInvariant() -in @('.ttf','.otf') }
        )
        if ($fontFiles.Count -eq 0) {
            throw "Font packages must contain at least one .ttf or .otf file: $resolvedSource"
        }
    }
    elseif (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
        throw "Install.ps1 must exist at the root of the source folder for App and Script packages: $resolvedSource"
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

        if ($PackageType -in @('Driver','Image')) {
            # Compress-Archive skips hidden files. Driver payloads must preserve
            # every vendor support file, including hidden siblings.
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            [IO.Compression.ZipFile]::CreateFromDirectory($tempPackage, $packagePath, [IO.Compression.CompressionLevel]::Optimal, $true)
        }
        else {
            Compress-Archive -Path $tempPackage -DestinationPath $packagePath -CompressionLevel Optimal
        }

        [pscustomobject]@{
            PSTypeName = 'OSDApps.Package'
            Id          = $Id
            Version     = $Version
            PackageType = $PackageType
            PackagePath = $packagePath
            Sha256      = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
