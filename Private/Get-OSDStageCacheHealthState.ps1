function Get-OSDStageCacheHealthState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [object[]]$DesiredPackage,

        [bool]$DesiredStateAvailable,

        [string]$CatalogSource,

        [string]$CatalogError,

        [string[]]$PinnedId
    )

    function Get-CacheItemSizeMB {
        param([Parameter(Mandatory)][string]$Path)

        if (-not (Test-Path -LiteralPath $Path)) { return 0.0 }
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if (-not $item) { return 0.0 }
        $bytes = if ($item.PSIsContainer) {
            (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        }
        else {
            $item.Length
        }
        if ($null -eq $bytes) { $bytes = 0 }
        [math]::Round([double]$bytes / 1MB, 1)
    }

    function New-CacheHealthEntry {
        param(
            [string]$Id,
            [string]$CanonicalId,
            [string]$DisplayName,
            [string]$Source,
            [string]$Version,
            [string]$Architecture,
            [string]$State,
            [string]$Integrity,
            [string]$Action,
            [string]$Reason,
            [string]$Path,
            [bool]$Desired,
            [bool]$Pinned
        )

        [pscustomobject]@{
            PSTypeName   = 'OSDStage.CacheHealthEntry'
            Id           = $Id
            CanonicalId  = if ($CanonicalId) { $CanonicalId } else { $Id }
            DisplayName  = if ($DisplayName) { $DisplayName } else { $Id }
            Source       = $Source
            Version      = $Version
            Architecture = $Architecture
            State        = $State
            Integrity    = $Integrity
            Action       = $Action
            Reason       = $Reason
            Desired      = $Desired
            Pinned       = $Pinned
            SizeMB       = Get-CacheItemSizeMB -Path $Path
            CachePath    = $Path
        }
    }

    $pins = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pin in @($PinnedId)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pin)) {
            [void]$pins.Add(([string]$pin).Trim())
        }
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $packagesRoot = Join-Path $CachePath 'Packages'
    $cacheCatalogPath = Join-Path $CachePath 'CacheCatalog.json'
    $existingPackages = @()
    $cacheCatalogErrors = [System.Collections.Generic.List[string]]::new()
    $invalidExistingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
        try {
            $existingCatalog = Get-OSDStageManifest -Path $cacheCatalogPath
            if (-not ($existingCatalog.PSObject.Properties.Name -contains 'Packages')) {
                throw 'Cache catalog is missing Packages.'
            }
            $existingPackages = @($existingCatalog.Packages)
        }
        catch {
            $cacheCatalogErrors.Add($_.Exception.Message)
        }
    }

    $safeExistingPackages = [System.Collections.Generic.List[object]]::new()
    $existingCanonicalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($package in $existingPackages) {
        $existingId = [string]$package.Id
        if ([string]::IsNullOrWhiteSpace($existingId) -or
            $existingId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $existingId -match '\.\.') {
            $cacheCatalogErrors.Add("Invalid package Id '$existingId'.")
            continue
        }
        [void]$existingCanonicalIds.Add($existingId)
        if (-not $package.Payload -or
            [string]$package.Payload.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            [void]$invalidExistingIds.Add($existingId)
            $cacheCatalogErrors.Add("Package '$existingId' has an invalid SHA-256 archive definition.")
        }
        $safeExistingPackages.Add($package)
    }
    $existingPackages = @($safeExistingPackages)

    $existingAliasOwners = @{}
    foreach ($package in $existingPackages) {
        $packageAliases = if ($package.PSObject.Properties.Name -contains 'Aliases') {
            @($package.Aliases)
        }
        else { @() }
        foreach ($aliasValue in $packageAliases) {
            $alias = ([string]$aliasValue).Trim()
            $owner = [string]$package.Id
            if ([string]::IsNullOrWhiteSpace($alias) -or
                $alias -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
                $alias -match '\.\.') {
                $cacheCatalogErrors.Add("Package '$owner' has invalid alias '$alias'.")
                [void]$invalidExistingIds.Add($owner)
                continue
            }
            if ($existingCanonicalIds.Contains($alias)) {
                $cacheCatalogErrors.Add("Alias '$alias' for '$owner' conflicts with a cached canonical Id.")
                [void]$invalidExistingIds.Add($owner)
                continue
            }
            $aliasKey = $alias.ToLowerInvariant()
            if ($existingAliasOwners.ContainsKey($aliasKey) -and
                [string]$existingAliasOwners[$aliasKey] -ine $owner) {
                $cacheCatalogErrors.Add("Alias '$alias' has multiple cached owners.")
                [void]$invalidExistingIds.Add($owner)
                [void]$invalidExistingIds.Add([string]$existingAliasOwners[$aliasKey])
                continue
            }
            $existingAliasOwners[$aliasKey] = $owner
        }
    }

    $cacheCatalogError = if ($cacheCatalogErrors.Count -gt 0) {
        @($cacheCatalogErrors | Select-Object -Unique) -join ' '
    }
    else { $null }

    if ($cacheCatalogError) {
        $entries.Add((New-CacheHealthEntry `
            -Id 'CacheCatalog.json' -CanonicalId 'CacheCatalog.json' `
            -DisplayName 'Repository cache catalog' -Source 'Repository' `
            -State 'Corrupt' -Integrity 'Corrupt' -Action 'Repair' `
            -Reason "CacheCatalog.json cannot be read safely: $cacheCatalogError" `
            -Path $cacheCatalogPath -Desired:$false -Pinned:$false))
    }

    $desiredById = @{}
    $repositoryAliasOwners = @{}
    foreach ($package in @($DesiredPackage)) {
        $desiredById[([string]$package.Id).ToLowerInvariant()] = $package
        $packageAliases = if ($package.PSObject.Properties.Name -contains 'Aliases') {
            @($package.Aliases)
        }
        else { @() }
        foreach ($aliasValue in $packageAliases) {
            $alias = ([string]$aliasValue).Trim()
            if ($alias) {
                $repositoryAliasOwners[$alias.ToLowerInvariant()] = [string]$package.Id
            }
        }
    }
    foreach ($aliasKey in $existingAliasOwners.Keys) {
        if (-not $repositoryAliasOwners.ContainsKey($aliasKey) -and
            -not $desiredById.ContainsKey($aliasKey)) {
            $repositoryAliasOwners[$aliasKey] = [string]$existingAliasOwners[$aliasKey]
        }
    }

    $existingById = @{}
    $duplicateExistingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($group in @($existingPackages | Group-Object Id)) {
        $existingById[$group.Name.ToLowerInvariant()] = $group.Group[0]
        if ($group.Count -gt 1) { [void]$duplicateExistingIds.Add($group.Name) }
    }

    $repositoryIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($package in @($DesiredPackage)) { [void]$repositoryIds.Add([string]$package.Id) }
    foreach ($package in @($existingPackages)) { [void]$repositoryIds.Add([string]$package.Id) }
    if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            [void]$repositoryIds.Add($directory.Name)
        }
    }

    foreach ($id in @($repositoryIds | Sort-Object)) {
        $key = $id.ToLowerInvariant()
        $desired = if ($desiredById.ContainsKey($key)) { $desiredById[$key] } else { $null }
        $existing = if ($existingById.ContainsKey($key)) { $existingById[$key] } else { $null }
        $canonicalId = if ($repositoryAliasOwners.ContainsKey($key)) { [string]$repositoryAliasOwners[$key] } else { $id }
        $isAlias = $repositoryAliasOwners.ContainsKey($key)
        $isPinned = $pins.Contains($id)
        $root = Join-Path $packagesRoot $id
        $archivePath = Join-Path $root 'Package.zip'
        $archiveExists = Test-Path -LiteralPath $archivePath -PathType Leaf
        $expectedHash = if ($desired -and $desired.Payload) {
            [string]$desired.Payload.Sha256
        }
        elseif ($existing -and $existing.Payload) {
            [string]$existing.Payload.Sha256
        }
        else { $null }
        $integrity = if (-not $archiveExists) {
            'Missing'
        }
        elseif ($expectedHash -match '^[A-Fa-f0-9]{64}$') {
            if (Test-OSDStageFileHash -Path $archivePath -ExpectedSha256 $expectedHash) { 'Valid' } else { 'Corrupt' }
        }
        else {
            'Unknown'
        }

        $state = $null
        $action = $null
        $reason = $null
        if ($duplicateExistingIds.Contains($id) -or $invalidExistingIds.Contains($id)) {
            $state = 'Corrupt'
            $action = if ($desired) { 'Synchronize' } else { 'Remove' }
            $reason = 'CacheCatalog.json contains duplicate or invalid metadata for this Id.'
        }
        elseif ($isAlias) {
            $state = 'Renamed'
            $action = 'RemoveAfterReplacement'
            $reason = "'$id' is an alias of canonical Id '$canonicalId'."
        }
        elseif ($desired) {
            $metadataCurrent = (
                $existing -and
                [string]$existing.Version -eq [string]$desired.Version -and
                [string]$existing.Architecture -eq [string]$desired.Architecture -and
                [string]$existing.Payload.Sha256 -eq [string]$desired.Payload.Sha256
            )
            if ($integrity -eq 'Missing') {
                $state = 'Incomplete'
                $action = 'Synchronize'
                $reason = 'The desired package archive is missing.'
            }
            elseif ($integrity -eq 'Corrupt') {
                $state = 'Corrupt'
                $action = 'Synchronize'
                $reason = 'The package archive does not match the desired SHA-256.'
            }
            elseif (-not $existing) {
                $state = 'Orphaned'
                $action = 'Adopt'
                $reason = 'The desired archive exists but CacheCatalog.json does not reference it.'
            }
            elseif (-not $metadataCurrent) {
                $state = 'Obsolete'
                $action = 'Synchronize'
                $reason = 'Cached metadata does not match the desired package version or variant.'
            }
            else {
                $state = 'Active'
                $action = 'None'
                $reason = 'The desired package and cache metadata are current.'
            }
        }
        elseif ($existing) {
            if ($integrity -eq 'Missing') {
                $state = 'Incomplete'
                $action = if ($isPinned) { 'Refresh' } elseif ($DesiredStateAvailable) { 'Remove' } else { 'Repair' }
                $reason = 'CacheCatalog.json references an archive that is missing.'
            }
            elseif ($integrity -eq 'Corrupt') {
                $state = 'Corrupt'
                $action = if ($isPinned) { 'Refresh' } elseif ($DesiredStateAvailable) { 'Remove' } else { 'Repair' }
                $reason = 'The cached archive does not match CacheCatalog.json.'
            }
            elseif ($isPinned) {
                $state = 'Pinned'
                $action = 'Keep'
                $reason = 'The package is outside desired state but explicitly pinned.'
            }
            elseif ($DesiredStateAvailable) {
                $state = 'Obsolete'
                $action = 'Remove'
                $reason = 'The package is no longer present in the desired catalog.'
            }
            else {
                $state = 'Active'
                $action = 'None'
                $reason = 'The locally cataloged package passes its recorded SHA-256; desired state was not requested.'
            }
        }
        else {
            $state = 'Orphaned'
            $action = if ($DesiredStateAvailable) { 'Remove' } else { 'Review' }
            $reason = 'A physical package folder exists without a CacheCatalog.json entry.'
        }

        $displayName = if ($desired -and $desired.DisplayName) { [string]$desired.DisplayName } elseif ($existing -and $existing.DisplayName) { [string]$existing.DisplayName } else { $id }
        $version = if ($desired) { [string]$desired.Version } elseif ($existing) { [string]$existing.Version } else { $null }
        $architecture = if ($desired) { [string]$desired.Architecture } elseif ($existing) { [string]$existing.Architecture } else { $null }
        $entries.Add((New-CacheHealthEntry `
            -Id $id -CanonicalId $canonicalId -DisplayName $displayName `
            -Source 'Repository' -Version $version -Architecture $architecture `
            -State $state -Integrity $integrity -Action $action -Reason $reason `
            -Path $root -Desired:([bool]$desired) -Pinned:$isPinned))
    }

    # Surface pins that do not map to any desired, cataloged or physical
    # repository entry. Sync rejects these; the read-only plan must not imply
    # that the same prune request would be healthy.
    foreach ($pin in @($pins | Sort-Object)) {
        if ($repositoryIds.Contains($pin)) { continue }
        $key = $pin.ToLowerInvariant()
        $isAliasPin = $repositoryAliasOwners.ContainsKey($key)
        $canonicalId = if ($isAliasPin) { [string]$repositoryAliasOwners[$key] } else { $pin }
        $state = if ($isAliasPin) { 'Renamed' } else { 'Incomplete' }
        $reason = if ($isAliasPin) {
            "Pinned Id '$pin' is a retired alias. Pin canonical Id '$canonicalId' instead."
        }
        else {
            "Pinned Id '$pin' is not present in desired or cached repository state."
        }
        $entries.Add((New-CacheHealthEntry `
            -Id $pin -CanonicalId $canonicalId -DisplayName $pin `
            -Source 'Repository' -State $state -Integrity 'Missing' -Action 'Review' `
            -Reason $reason -Path (Join-Path $packagesRoot $pin) `
            -Desired:$false -Pinned:$true))
    }

    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $builtInMetadataPath = Join-Path $moduleRoot 'metadata\builtins.json'
    $builtInCanonical = @{}
    $builtInAliasOwners = @{}
    if (Test-Path -LiteralPath $builtInMetadataPath -PathType Leaf) {
        $builtInMetadata = Get-Content -LiteralPath $builtInMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($app in @($builtInMetadata.Packages)) {
            $builtInCanonical[([string]$app.Id).ToLowerInvariant()] = $app
            foreach ($aliasValue in @($app.Aliases)) {
                $alias = ([string]$aliasValue).Trim()
                if ($alias) { $builtInAliasOwners[$alias.ToLowerInvariant()] = [string]$app.Id }
            }
        }
    }

    # CacheCatalog diagnostics are already represented above; suppress the
    # inventory command's duplicate warning while still collecting built-ins.
    $inventory = @(Get-OSDStageCache -CachePath $CachePath -WarningAction SilentlyContinue)
    $builtInInventory = @($inventory | Where-Object Source -eq 'BuiltIn')
    $builtInRoot = Join-Path $CachePath 'BuiltIn'
    $representedRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $builtInInventory) {
        $relative = ([string]$item.CachePath).Substring($builtInRoot.Length).TrimStart([char[]]@('\','/'))
        $topLevelId = @($relative -split '[\\/]')[0]
        [void]$representedRoots.Add($topLevelId)
        $key = $topLevelId.ToLowerInvariant()
        $metadataId = [string]$item.Id
        $metadataKey = $metadataId.ToLowerInvariant()
        $folderIsAlias = $builtInAliasOwners.ContainsKey($key)
        $folderIsCanonical = $builtInCanonical.ContainsKey($key)
        $metadataIsAlias = $builtInAliasOwners.ContainsKey($metadataKey)
        $canonicalId = if ($folderIsAlias) {
            [string]$builtInAliasOwners[$key]
        }
        elseif ($folderIsCanonical) {
            [string]$builtInCanonical[$key].Id
        }
        elseif ($metadataIsAlias) {
            [string]$builtInAliasOwners[$metadataKey]
        }
        else {
            $metadataId
        }
        $isPinned = $false
        $officeGenerationCorrupt = $false
        $officeGenerationReason = $null
        if ($canonicalId -eq 'Microsoft365Apps' -and $folderIsCanonical) {
            try {
                $officeGeneration = Test-OSDStageOfficeCacheGeneration `
                    -OfficeRoot $item.CachePath `
                    -ExpectedVersion ([string]$item.Version) `
                    -Architecture $(if ([string]$item.Architecture -eq 'x86') { 'x86' } else { 'x64' }) `
                    -PassThru
                if (-not $officeGeneration.Valid) {
                    $officeGenerationCorrupt = $true
                    $officeGenerationReason = @($officeGeneration.Errors) -join ' '
                }
            }
            catch {
                $officeGenerationCorrupt = $true
                $officeGenerationReason = $_.Exception.Message
            }
        }

        if ($folderIsAlias) {
            $state = 'Renamed'; $action = 'MigrateOrRemove'; $reason = "'$topLevelId' is an alias of canonical Id '$canonicalId'."
        }
        elseif (-not $folderIsCanonical) {
            $state = 'Orphaned'; $action = 'Remove'; $reason = 'The folder does not match a current built-in Id.'
        }
        elseif ($metadataIsAlias -and [string]$builtInAliasOwners[$metadataKey] -ieq $canonicalId) {
            $state = 'Renamed'; $action = 'Refresh'; $reason = "CacheInfo.json uses retired Id '$metadataId' for canonical folder '$canonicalId'."
        }
        elseif ($metadataId -ine $canonicalId) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = "CacheInfo.json Id '$metadataId' does not match canonical folder '$canonicalId'."
        }
        elseif ($officeGenerationCorrupt) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = "The Microsoft 365 Apps cache generation is inconsistent. $officeGenerationReason"
        }
        elseif ($item.PSObject.Properties['PayloadError'] -and $item.PayloadError) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = [string]$item.PayloadError
        }
        elseif ($canonicalId -in @('VisualCRedist','DotNetRuntime') -and -not $item.Valid) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = 'Runtime generation identity, size or hash validation failed.'
        }
        elseif ($canonicalId -eq 'VisualStudioCode' -and -not $item.Valid) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = 'The VisualStudioCode generation failed release metadata, SHA-256, size or platform validation.'
        }
        elseif ($canonicalId -eq '7Zip' -and -not $item.Valid) {
            $state = 'Corrupt'; $action = 'Refresh'; $reason = 'The 7Zip generation failed release metadata, SHA-256, size or architecture validation.'
        }
        elseif (-not $item.Valid) {
            $state = 'Incomplete'; $action = 'Refresh'; $reason = 'Required built-in payload files are missing.'
        }
        else {
            $state = 'Active'; $action = 'None'; $reason = 'The built-in cache entry uses a canonical Id and has its required files.'
        }

        $entries.Add((New-CacheHealthEntry `
            -Id $topLevelId -CanonicalId $canonicalId -DisplayName $item.DisplayName `
            -Source 'BuiltIn' -Version $item.Version -Architecture $item.Architecture `
            -State $state -Integrity $(if ($officeGenerationCorrupt -or ($item.PSObject.Properties['PayloadError'] -and $item.PayloadError)) { 'Corrupt' } elseif ($item.Valid) { 'Valid' } else { 'Missing' }) `
            -Action $action -Reason $reason -Path $item.CachePath `
            -Desired:$folderIsCanonical -Pinned:$isPinned))
    }

    if (Test-Path -LiteralPath $builtInRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $builtInRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($representedRoots.Contains($directory.Name)) { continue }
            $key = $directory.Name.ToLowerInvariant()
            $isPinned = $false
            $canonicalId = if ($builtInAliasOwners.ContainsKey($key)) { [string]$builtInAliasOwners[$key] } else { $directory.Name }
            if ($builtInAliasOwners.ContainsKey($key)) {
                $state = 'Renamed'; $action = 'Review'; $reason = "'$($directory.Name)' is an alias of canonical Id '$canonicalId', but its CacheInfo.json is missing or unreadable."
            }
            elseif ($builtInCanonical.ContainsKey($key)) {
                $state = 'Incomplete'; $action = 'Refresh'; $reason = 'The canonical built-in folder has no readable CacheInfo.json.'
            }
            else {
                $state = 'Orphaned'; $action = 'Remove'; $reason = 'The folder is not registered as a current built-in app.'
            }
            $entries.Add((New-CacheHealthEntry `
                -Id $directory.Name -CanonicalId $canonicalId -DisplayName $directory.Name `
                -Source 'BuiltIn' -State $state -Integrity 'Unknown' -Action $action `
                -Reason $reason -Path $directory.FullName `
                -Desired:($builtInCanonical.ContainsKey($canonicalId.ToLowerInvariant())) -Pinned:$isPinned))
        }
    }

    $stagingRoot = Join-Path $CachePath '.staging'
    if (Test-Path -LiteralPath $builtInRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $builtInRoot -File -Force -ErrorAction Stop)) {
            $requiresReview = ($file.Name -match '\.osdstage-') -or
                (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            $entries.Add((New-CacheHealthEntry `
                -Id $file.Name -CanonicalId $file.Name -DisplayName $file.Name -Source 'BuiltIn' `
                -State 'Orphaned' -Integrity 'Unknown' -Action $(if ($requiresReview) { 'Review' } else { 'Remove' }) `
                -Reason 'Loose files do not belong in the managed BuiltIn root; preserve links and recovery content for review.' `
                -Path $file.FullName -Desired:$false -Pinned:$false))
        }
    }

    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            $entries.Add((New-CacheHealthEntry `
                -Id $directory.Name -CanonicalId $directory.Name `
                -DisplayName 'Unfinished cache transaction' -Source 'Transaction' `
                -State 'Orphaned' -Integrity 'Unknown' -Action 'Review' `
                -Reason 'A cache transaction directory remains. Inspect its logs and recovery data before removing it.' `
                -Path $directory.FullName -Desired:$false -Pinned:$false))
        }
    }

    $allEntries = @($entries | Sort-Object Source, CanonicalId, Id, Architecture, CachePath)
    $actionableStates = @('Obsolete','Orphaned','Renamed','Incomplete','Corrupt')
    $removable = @($allEntries | Where-Object { $_.Action -in @('Remove','RemoveAfterReplacement','MigrateOrRemove') })

    [pscustomobject]@{
        PSTypeName            = 'OSDStage.CacheHealth'
        CachePath             = $CachePath
        CacheAvailable        = $true
        DesiredStateAvailable = $DesiredStateAvailable
        CatalogSource         = $CatalogSource
        CatalogError          = $CatalogError
        CacheCatalogError     = $cacheCatalogError
        EntryCount            = $allEntries.Count
        ActiveCount           = @($allEntries | Where-Object State -eq 'Active').Count
        PinnedCount           = @($allEntries | Where-Object { $_.Pinned -or $_.State -eq 'Pinned' }).Count
        ObsoleteCount         = @($allEntries | Where-Object State -eq 'Obsolete').Count
        OrphanedCount         = @($allEntries | Where-Object State -eq 'Orphaned').Count
        RenamedCount          = @($allEntries | Where-Object State -eq 'Renamed').Count
        IncompleteCount       = @($allEntries | Where-Object State -eq 'Incomplete').Count
        CorruptCount          = @($allEntries | Where-Object { $_.State -eq 'Corrupt' -or $_.Integrity -eq 'Corrupt' }).Count
        RemovableSizeMB       = [math]::Round([double](($removable | Measure-Object SizeMB -Sum).Sum), 1)
        Entries               = $allEntries
        Healthy               = (
            -not $CatalogError -and
            @($allEntries | Where-Object {
                ($_.State -in $actionableStates -and -not ($_.State -eq 'Obsolete' -and $_.Pinned)) -or
                $_.Integrity -in @('Missing','Corrupt','Unknown')
            }).Count -eq 0
        )
    }
}
