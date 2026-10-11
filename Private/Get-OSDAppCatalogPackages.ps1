function Get-OSDAppCatalogPackages {
    [CmdletBinding(DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [string[]]$Name
    )

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $catalog = Get-OSDAppManifest -Uri $CatalogUri
        $catalogBaseUri = [uri]::new($CatalogUri, '.')
        $catalogRoot = $null
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $catalog = Get-OSDAppManifest -Path $resolvedCatalogPath
        $catalogBaseUri = $null
        $catalogRoot = Split-Path -Path $resolvedCatalogPath -Parent
    }

    if (-not ($catalog.PSObject.Properties.Name -contains 'Applications')) {
        throw 'Invalid OSD Apps catalog. Root catalog must contain Applications.'
    }

    $applications = @($catalog.Applications)
    if ($Name) {
        $applications = @($applications | Where-Object { $_.Id -in $Name })
        $missing = @($Name | Where-Object { $_ -notin @($applications.Id) })
        if ($missing.Count -gt 0) {
            throw "Requested application(s) not found in catalog: $($missing -join ', ')"
        }
    }

    $packages = [System.Collections.Generic.List[object]]::new()

    foreach ($application in $applications) {
        if (-not $application.Id) {
            throw 'Catalog application entry must contain Id.'
        }

        foreach ($packageRef in @($application.Packages)) {
            if (-not $packageRef.Architecture -or -not $packageRef.Manifest) {
                throw "Catalog package reference for '$($application.Id)' must contain Architecture and Manifest."
            }

            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $packageManifestUri = [uri]::new($catalogBaseUri, ([string]$packageRef.Manifest).Replace('\','/'))
                $packageManifest = Get-OSDAppManifest -Uri $packageManifestUri
                $packageBaseUri = [uri]::new($packageManifestUri, '.')
            }
            else {
                $packageManifestPath = Join-Path $catalogRoot (([string]$packageRef.Manifest) -replace '/', [IO.Path]::DirectorySeparatorChar)
                $packageManifest = Get-OSDAppManifest -Path $packageManifestPath
                $packageRoot = Split-Path -Path $packageManifestPath -Parent
            }

            if ([string]$packageManifest.Id -ne [string]$application.Id) {
                throw "Package manifest Id '$($packageManifest.Id)' does not match catalog Id '$($application.Id)'."
            }

            if (([string]$packageManifest.Architecture).ToLowerInvariant() -ne ([string]$packageRef.Architecture).ToLowerInvariant()) {
                throw "Package manifest architecture '$($packageManifest.Architecture)' does not match catalog architecture '$($packageRef.Architecture)' for '$($application.Id)'."
            }

            $fileName = if ($packageManifest.Archive.FileName) { [string]$packageManifest.Archive.FileName } else { 'Package.zip' }
            if ($fileName -ne 'Package.zip') {
                throw "Package '$($application.Id)' must use the fixed archive name Package.zip."
            }

            $archive = [ordered]@{
                FileName = $fileName
                Sha256   = [string]$packageManifest.Archive.Sha256
            }

            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $archive.Uri = ([uri]::new($packageBaseUri, $fileName)).AbsoluteUri
            }
            else {
                $archive.SourcePath = Join-Path $packageRoot $fileName
            }

            $packages.Add([pscustomobject]@{
                Id           = [string]$packageManifest.Id
                DisplayName  = if ($packageManifest.DisplayName) { [string]$packageManifest.DisplayName } else { [string]$packageManifest.Id }
                Vendor       = if ($packageManifest.Vendor) { ([string]$packageManifest.Vendor).Trim() } else { $null }
                Version      = [string]$packageManifest.Version
                Architecture = [string]$packageManifest.Architecture
                SuccessCodes = @($packageManifest.SuccessCodes)
                Archive      = [pscustomobject]$archive
            })
        }
    }

    [pscustomobject]@{
        SchemaVersion = $catalog.SchemaVersion
        GeneratedAt   = $catalog.GeneratedAt
        Packages      = @($packages)
    }
}
