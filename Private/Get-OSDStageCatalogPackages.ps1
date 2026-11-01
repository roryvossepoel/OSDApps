function Get-OSDStageCatalogPackages {
    [CmdletBinding(DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [string[]]$Name
    )

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $catalog = Get-OSDStageManifest -Uri $CatalogUri
        $catalogBaseUri = [uri]::new($CatalogUri, '.')
        $catalogRoot = $null
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $catalog = Get-OSDStageManifest -Path $resolvedCatalogPath
        $catalogBaseUri = $null
        $catalogRoot = Split-Path -Path $resolvedCatalogPath -Parent
    }

    Assert-OSDStageCatalog -Catalog $catalog

    $apps = @($catalog.Packages)
    $canonicalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $aliasOwners = @{}

    # App Ids and aliases become cache directory names. Validate the
    # complete identity graph before resolving a subset or reading manifests.
    foreach ($app in $apps) {
        $appId = [string]$app.Id
        if ([string]::IsNullOrWhiteSpace($appId) -or
            $appId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $appId -match '\.\.') {
            throw "Invalid app Id '$appId' in repository catalog."
        }
        if (-not $canonicalIds.Add($appId)) {
            throw "Duplicate app Id '$appId' in repository catalog."
        }
    }

    foreach ($app in $apps) {
        $appId = [string]$app.Id
        $aliases = @(
            if ($app.PSObject.Properties.Name -contains 'Aliases') {
                @($app.Aliases)
            }
        )
        foreach ($aliasValue in $aliases) {
            $alias = ([string]$aliasValue).Trim()
            if ([string]::IsNullOrWhiteSpace($alias) -or
                $alias -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
                $alias -match '\.\.') {
                throw "Invalid alias '$alias' for '$appId' in repository catalog."
            }
            if ($canonicalIds.Contains($alias)) {
                throw "Alias '$alias' for '$appId' conflicts with a canonical app Id."
            }
            $aliasKey = $alias.ToLowerInvariant()
            if ($aliasOwners.ContainsKey($aliasKey)) {
                throw "Alias '$alias' is assigned to both '$($aliasOwners[$aliasKey])' and '$appId'."
            }
            $aliasOwners[$aliasKey] = $appId
        }
    }

    if ($Name) {
        $resolvedNames = @(
            foreach ($requestedName in $Name) {
                $requestedKey = ([string]$requestedName).ToLowerInvariant()
                if ($aliasOwners.ContainsKey($requestedKey)) {
                    [string]$aliasOwners[$requestedKey]
                }
                else {
                    [string]$requestedName
                }
            }
        )
        $apps = @($apps | Where-Object { $_.Id -in $resolvedNames })
        $missing = @($resolvedNames | Where-Object { $_ -notin @($apps.Id) })
        if ($missing.Count -gt 0) {
            throw "Requested app(s) not found in catalog: $($missing -join ', ')"
        }
    }

    $packages = [System.Collections.Generic.List[object]]::new()

    foreach ($app in $apps) {
        if (-not $app.Id) {
            throw 'Catalog app entry must contain Id.'
        }

        foreach ($packageRef in @($app.Architectures)) {
            if (-not $packageRef.Architecture -or -not $packageRef.Manifest) {
                throw "Catalog package reference for '$($app.Id)' must contain Architecture and Manifest."
            }

            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $packageManifestUri = [uri]::new($catalogBaseUri, ([string]$packageRef.Manifest).Replace('\','/'))
                $packageManifest = Get-OSDStageManifest -Uri $packageManifestUri
                $packageBaseUri = [uri]::new($packageManifestUri, '.')
            }
            else {
                $packageManifestPath = Join-Path $catalogRoot (([string]$packageRef.Manifest) -replace '/', [IO.Path]::DirectorySeparatorChar)
                $packageManifest = Get-OSDStageManifest -Path $packageManifestPath
                $packageRoot = Split-Path -Path $packageManifestPath -Parent
            }

            if ([string]$packageManifest.SchemaVersion -ne '2') {
                throw "Package manifest for '$($app.Id)' must use SchemaVersion 2."
            }

            if ([string]$packageManifest.Id -ne [string]$app.Id) {
                throw "Package manifest Id '$($packageManifest.Id)' does not match catalog Id '$($app.Id)'."
            }

            if (([string]$packageManifest.Architecture).ToLowerInvariant() -ne ([string]$packageRef.Architecture).ToLowerInvariant()) {
                throw "Package manifest architecture '$($packageManifest.Architecture)' does not match catalog architecture '$($packageRef.Architecture)' for '$($app.Id)'."
            }

            if ([string]::IsNullOrWhiteSpace([string]$packageManifest.Version)) {
                throw "Package manifest for '$($app.Id)' must contain Version."
            }

            $packageType = if ($packageManifest.PSObject.Properties.Name -contains 'PackageType' -and
                -not [string]::IsNullOrWhiteSpace([string]$packageManifest.PackageType)) {
                [string]$packageManifest.PackageType
            }
            else {
                'App'
            }
            if ($packageType -notin @('App','Script','Font','Certificate','Driver')) {
                throw "Package '$($app.Id)' has unsupported PackageType '$packageType'. Expected App, Script, Font, Certificate or Driver."
            }
            $packageType = if ($packageType -ieq 'Script') { 'Script' } elseif ($packageType -ieq 'Font') { 'Font' } elseif ($packageType -ieq 'Certificate') { 'Certificate' } elseif ($packageType -ieq 'Driver') { 'Driver' } else { 'App' }

            if ($packageType -eq 'Certificate' -and [string]$packageManifest.CertificateStore -notin @('Root','CA')) {
                throw "Certificate package '$($app.Id)' requires CertificateStore Root or CA."
            }

            if (-not $packageManifest.Payload -or
                [string]$packageManifest.Payload.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
                throw "Package '$($app.Id)' has an invalid SHA-256 archive definition."
            }

            $fileName = if ($packageManifest.Payload.FileName) { [string]$packageManifest.Payload.FileName } else { 'Package.zip' }
            if ($fileName -ne 'Package.zip') {
                throw "Package '$($app.Id)' must use the fixed archive name Package.zip."
            }

            $archive = [ordered]@{
                FileName = $fileName
                Sha256   = [string]$packageManifest.Payload.Sha256
            }

            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $archive.Uri = ([uri]::new($packageBaseUri, $fileName)).AbsoluteUri
            }
            else {
                $archive.SourcePath = Join-Path $packageRoot $fileName
            }

            $packages.Add([pscustomobject]@{
                Id           = [string]$packageManifest.Id
                Aliases      = @(
                    if ($app.PSObject.Properties.Name -contains 'Aliases') {
                        @($app.Aliases | ForEach-Object { ([string]$_).Trim() })
                    }
                )
                DisplayName  = if ($packageManifest.DisplayName) { [string]$packageManifest.DisplayName } else { [string]$packageManifest.Id }
                Vendor       = if ($packageManifest.Vendor) { ([string]$packageManifest.Vendor).Trim() } else { $null }
                Version      = [string]$packageManifest.Version
                Architecture = [string]$packageManifest.Architecture
                PackageType  = $packageType
                CertificateStore = if($packageType -eq 'Certificate'){[string]$packageManifest.CertificateStore}else{$null}
                SuccessCodes = @($packageManifest.SuccessCodes)
                Payload      = [pscustomobject]$archive
            })
        }
    }

    [pscustomobject]@{
        SchemaVersion = $catalog.SchemaVersion
        GeneratedAt   = $catalog.GeneratedAt
        Packages      = @($packages)
    }
}
