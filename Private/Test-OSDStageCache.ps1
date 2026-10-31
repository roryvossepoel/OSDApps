function Test-OSDStageRepositoryCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,
        [string[]]$Name
    )

    $manifestPath = Join-Path $CachePath 'CacheCatalog.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Cache catalog not found: $manifestPath" }

    $manifest = Get-OSDStageManifest -Path $manifestPath
    $packages = @($manifest.Packages)
    if ($Name) { $packages = $packages | Where-Object { $_.Id -in $Name } }

    foreach ($package in $packages) {
        $archivePath = Join-Path $CachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))
        $valid = Test-OSDStageFileHash -Path $archivePath -ExpectedSha256 $package.Payload.Sha256

        if ($valid -and [string]$package.PackageType -eq 'Certificate') {
            if ([string]$package.CertificateStore -notin @('Root','CA')) { $valid=$false }
            else { $valid=(Test-OSDStagePackage -PackagePath $archivePath -PackageType Certificate -CertificateStore ([string]$package.CertificateStore)).Valid }
        }

        [pscustomobject]@{
            Id      = $package.Id
            Version = $package.Version
            Architecture = $package.Architecture
            Path    = $archivePath
            Valid   = $valid
        }
    }
}
