function Get-OSDAppCacheHealth {
    [CmdletBinding(DefaultParameterSetName = 'Automatic')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$CachePath,

        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [Parameter(ParameterSetName = 'Automatic')]
        [switch]$Offline,

        [string[]]$PinnedId
    )

    $resolvedCachePath = $null
    if ($PSBoundParameters.ContainsKey('CachePath')) {
        $resolvedCachePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CachePath))
    }
    else {
        try { $resolvedCachePath = Get-OSDAppCachePath }
        catch { Write-Verbose "No OSDCloud cache volume is available: $($_.Exception.Message)" }
    }

    if (-not $resolvedCachePath -or -not (Test-Path -LiteralPath $resolvedCachePath -PathType Container)) {
        return [pscustomobject]@{
            PSTypeName            = 'OSDApps.CacheHealth'
            CachePath             = $resolvedCachePath
            CacheAvailable        = $false
            DesiredStateAvailable = $false
            CatalogSource         = $null
            CatalogError          = $null
            CacheCatalogError     = $null
            EntryCount            = 0
            ActiveCount           = 0
            PinnedCount           = 0
            ObsoleteCount         = 0
            OrphanedCount         = 0
            RenamedCount          = 0
            IncompleteCount       = 0
            CorruptCount          = 0
            RemovableSizeMB       = 0
            Entries               = @()
            Healthy               = $false
        }
    }

    $desiredPackages = @()
    $desiredStateAvailable = $false
    $catalogSource = $null
    $catalogError = $null

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Uri') {
            $catalogSource = $CatalogUri.AbsoluteUri
            $sourceCatalog = Get-OSDAppCatalogPackages -CatalogUri $CatalogUri
            $desiredStateAvailable = $true
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Path') {
            $catalogSource = [Environment]::ExpandEnvironmentVariables($CatalogPath)
            $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
            $sourceCatalog = Get-OSDAppCatalogPackages -CatalogPath $resolvedCatalogPath
            $catalogSource = $resolvedCatalogPath
            $desiredStateAvailable = $true
        }
        elseif (-not $Offline) {
            $configuredUri = (Get-OSDAppConfiguration).CatalogUri
            if ($configuredUri) {
                $catalogSource = $configuredUri.AbsoluteUri
                $sourceCatalog = Get-OSDAppCatalogPackages -CatalogUri $configuredUri
                $desiredStateAvailable = $true
            }
        }

        if ($desiredStateAvailable) {
            $desiredPackages = @(
                Resolve-OSDAppCatalogPackageVariant `
                    -Package @($sourceCatalog.Packages) `
                    -Architecture (Get-OSDAppHostArchitecture)
            )
        }
    }
    catch {
        $catalogError = $_.Exception.Message
        $desiredStateAvailable = $false
        Write-Warning "Desired cache state could not be resolved: $catalogError"
    }

    Get-OSDAppCacheHealthState `
        -CachePath $resolvedCachePath `
        -DesiredPackage $desiredPackages `
        -DesiredStateAvailable:$desiredStateAvailable `
        -CatalogSource $catalogSource `
        -CatalogError $catalogError `
        -PinnedId $PinnedId
}
