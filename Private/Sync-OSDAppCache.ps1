function Sync-OSDAppCache {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [string[]]$Name,

        [switch]$Prune,

        [string[]]$PinnedId,

        [ValidateSet('x64','arm64')]
        [string]$Architecture
    )

    $logPath = Join-Path $CachePath 'Logs\\Client.log'

    if ($Prune -and $Name) {
        throw 'Prune requires a complete catalog synchronization. Do not combine Prune with Name.'
    }
    if ($PinnedId -and -not $Prune) {
        throw 'PinnedId is only valid together with Prune.'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $sourceCatalog = Get-OSDAppCatalogPackages -CatalogUri $CatalogUri -Name $Name
        $catalogSourceDescription = $CatalogUri.AbsoluteUri
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $sourceCatalog = Get-OSDAppCatalogPackages -CatalogPath $resolvedCatalogPath -Name $Name
        $catalogSourceDescription = $resolvedCatalogPath
    }

    $hostArchitecture = Get-OSDAppHostArchitecture
    $targetArchitecture = if ($Architecture) { $Architecture } else { $hostArchitecture }
    $allPackages = @($sourceCatalog.Packages)
    $packages = @(Resolve-OSDAppCatalogPackageVariant -Package $allPackages -Architecture $targetArchitecture)


    $packagesRoot = Join-Path $CachePath 'Packages'
    $cacheCatalogPath = Join-Path $CachePath 'CacheCatalog.json'
    $stagingRoot = Join-Path $CachePath '.staging'

    # Validate ALL entries before touching the persistent cache.
    # IDs are directory names, so arbitrary paths and traversal are forbidden.
    foreach ($package in $packages) {
        if (-not $package.Id -or -not $package.Archive -or -not $package.Archive.Sha256) {
            throw "Package '$($package.Id)' has an incomplete Archive definition."
        }
        if ([string]$package.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            [string]$package.Id -match '\.\.') {
            throw "Invalid package Id '$($package.Id)' in repository catalog."
        }
        if ($package.Archive.FileName -and $package.Archive.FileName -ne 'Package.zip') {
            throw "Package '$($package.Id)' must use the fixed archive name Package.zip."
        }
        if ([string]$package.Archive.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw "Package '$($package.Id)' has an invalid SHA-256 hash."
        }
        foreach ($aliasValue in @($package.Aliases)) {
            $alias = [string]$aliasValue
            if ($alias -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $alias -match '\.\.') {
                throw "Package '$($package.Id)' has invalid alias '$alias'."
            }
        }
    }

    $desiredIds = @($packages.Id)
    $aliasIds = @($packages | ForEach-Object { @($_.Aliases) } | Select-Object -Unique)
    $pins = @($PinnedId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    foreach ($pin in $pins) {
        if ([string]$pin -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]$pin -match '\.\.') {
            throw "Invalid pinned cache Id '$pin'."
        }
        if ($pin -in $aliasIds) {
            throw "Pinned cache Id '$pin' is a declared alias. Pin the canonical Id instead."
        }
    }

    # Reject pins that cannot exist in a new cache before creating its lock
    # file. Existing-catalog identities are still validated under the lock.
    if ($Prune -and -not (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf)) {
        $unknownPins = @($pins | Where-Object { $_ -notin $desiredIds })
        if ($unknownPins.Count -gt 0) {
            throw "Pinned cache Id(s) are not present in desired or existing cache state: $($unknownPins -join ', ')."
        }
    }

    $action = if ($Prune) {
        "Reconcile $($packages.Count) desired application(s) and prune stale cache folders as a single transaction"
    }
    else { "Synchronize $($packages.Count) application(s) as a single cache transaction" }
    if (-not $PSCmdlet.ShouldProcess($CachePath, $action)) { return }

    $cacheLock = Enter-OSDAppCacheLock -CachePath $CachePath -Operation 'repository cache synchronization'
    try {
    # Never discard existing cache entries because a catalog is unreadable.
    $existingPackages = @()
    if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
        try {
            $existingCatalog = Get-OSDAppManifest -Path $cacheCatalogPath
            if ($null -eq $existingCatalog -or
                -not ($existingCatalog.PSObject.Properties.Name -contains 'Packages')) {
                throw 'Cache catalog is missing Packages.'
            }
            $existingPackages = @($existingCatalog.Packages)
        }
        catch {
            throw "Existing cache catalog '$cacheCatalogPath' cannot be read safely: $($_.Exception.Message)"
        }
    }

    $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($package in $existingPackages) {
        $existingId = [string]$package.Id
        if ([string]::IsNullOrWhiteSpace($existingId) -or
            $existingId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $existingId -match '\.\.') {
            throw "Existing cache catalog contains invalid package Id '$existingId'."
        }
        if (-not $existingIds.Add($existingId)) {
            throw "Existing cache catalog contains duplicate package Id '$existingId'."
        }
        if (-not $package.Archive -or
            [string]$package.Archive.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw "Existing cache catalog package '$existingId' has an invalid SHA-256 archive definition."
        }
    }

    $existingAliasOwners = @{}
    foreach ($package in $existingPackages) {
        $existingId = [string]$package.Id
        $existingAliases = if ($package.PSObject.Properties.Name -contains 'Aliases') {
            @($package.Aliases)
        }
        else { @() }
        foreach ($aliasValue in $existingAliases) {
            $alias = ([string]$aliasValue).Trim()
            if ([string]::IsNullOrWhiteSpace($alias) -or
                $alias -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
                $alias -match '\.\.') {
                throw "Existing cache catalog package '$existingId' has invalid alias '$alias'."
            }
            if ($existingIds.Contains($alias)) {
                throw "Existing cache catalog alias '$alias' for '$existingId' conflicts with a canonical package Id."
            }
            $aliasKey = $alias.ToLowerInvariant()
            if ($existingAliasOwners.ContainsKey($aliasKey)) {
                throw "Existing cache catalog alias '$alias' is assigned to both '$($existingAliasOwners[$aliasKey])' and '$existingId'."
            }
            $existingAliasOwners[$aliasKey] = $existingId
        }
    }

    if ($Prune) {
        $knownIds = @($desiredIds) + @($existingPackages.Id)
        $unknownPins = @($pins | Where-Object { $_ -notin $knownIds })
        if ($unknownPins.Count -gt 0) {
            throw "Pinned cache Id(s) are not present in desired or existing cache state: $($unknownPins -join ', ')."
        }

        foreach ($pin in @($pins | Where-Object { $_ -notin $desiredIds })) {
            $pinnedPackage = @($existingPackages | Where-Object { $_.Id -ieq $pin })[0]
            $pinnedArchive = Join-Path $packagesRoot (Join-Path $pinnedPackage.Id 'Package.zip')
            if (-not (Test-OSDAppFileHash -Path $pinnedArchive -ExpectedSha256 $pinnedPackage.Archive.Sha256)) {
                throw "Pinned cache package '$pin' is missing or corrupt. Refresh it or remove the pin before pruning."
            }
            $pinnedAliases = if ($pinnedPackage.PSObject.Properties.Name -contains 'Aliases') {
                @($pinnedPackage.Aliases)
            }
            else { @() }
            $identityConflicts = @(
                $pinnedAliases |
                    Where-Object { $_ -in $desiredIds -or $_ -in $aliasIds }
            )
            if ($identityConflicts.Count -gt 0) {
                throw "Pinned cache package '$pin' has alias '$($identityConflicts[0])' that conflicts with desired catalog identity."
            }
        }
    }

    $updatedIds = @($packages.Id)
    $retainedExistingPackages = [System.Collections.Generic.List[object]]::new()
    foreach ($existingPackage in @($existingPackages | Where-Object { $_.Id -notin $updatedIds })) {
        $existingAliases = if ($existingPackage.PSObject.Properties.Name -contains 'Aliases') {
            @($existingPackage.Aliases)
        }
        else { @() }
        $conflictingIdentity = @(
            @([string]$existingPackage.Id) + $existingAliases |
                Where-Object { $_ -in $aliasIds -or $_ -in $desiredIds }
        ) | Select-Object -First 1
        if ($conflictingIdentity) {
            Write-Verbose "Retiring cached metadata for '$($existingPackage.Id)' because identity '$conflictingIdentity' is owned by the desired catalog. Physical content is retained unless Prune is used."
            continue
        }
        $retainedExistingPackages.Add($existingPackage)
    }

    $mergedPackages = if ($Prune) {
        @(
            @($retainedExistingPackages | Where-Object { $_.Id -in $pins }) +
            @($packages)
        )
    }
    else {
        @(
            @($retainedExistingPackages) +
            @($packages)
        )
    }
    $selectedCatalog = [ordered]@{
        SchemaVersion = $sourceCatalog.SchemaVersion
        GeneratedAt = $sourceCatalog.GeneratedAt
        SourceCatalog = $catalogSourceDescription
        Packages = @($mergedPackages)
    }

    $toAcquire = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $packages) {
        $targetRoot = Join-Path $packagesRoot $package.Id
        $targetArchive = Join-Path $targetRoot 'Package.zip'
        if (Test-OSDAppFileHash -Path $targetArchive -ExpectedSha256 $package.Archive.Sha256) {
            Write-Verbose "$($package.Id) is current."
        }
        else {
            $toAcquire.Add([pscustomobject]@{
                Package = $package
                TargetRoot = $targetRoot
            })
        }
    }

    $toRemove = [System.Collections.Generic.List[object]]::new()
    if ($Prune -and (Test-Path -LiteralPath $packagesRoot -PathType Container)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($directory.Name -in $desiredIds -or $directory.Name -in $pins) {
                continue
            }
            $classification = if ($directory.Name -in $aliasIds) { 'Renamed' } elseif ($directory.Name -in @($existingPackages.Id)) { 'Obsolete' } else { 'Orphaned' }
            $toRemove.Add([pscustomobject]@{
                Id = $directory.Name
                Path = $directory.FullName
                Classification = $classification
            })
        }
    }

    # Budget the complete prepared batch. Old packages remain on disk until
    # commit; pruning cannot be used to finance downloads before validation.
    [double]$remainingBytes = 0
    foreach ($entry in $toAcquire) {
        $estimate = Get-OSDAppArchiveSpaceEstimate -Archive $entry.Package.Archive -ExistingPath $entry.TargetRoot
        $entry | Add-Member -NotePropertyName EstimatedBytes -NotePropertyValue $estimate
        $remainingBytes += $estimate
    }
    Assert-OSDAppTransactionSpace -Path $CachePath -ExpectedBytes $remainingBytes -Operation 'repository cache batch preparation' | Out-Null

    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncStart' -Message 'Starting transactional repository synchronization.' -Data @{ CachePath = $CachePath; RequestedCount = $packages.Count; AcquireCount = $toAcquire.Count; Prune = [bool]$Prune; PruneCount = $toRemove.Count; PinnedIds = $pins }
    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'ArchitectureResolved' -Message 'Resolved package variants.' -Data @{ HostArchitecture = $hostArchitecture; TargetArchitecture = $targetArchitecture; Packages = @($packages | ForEach-Object { "$($_.Id):$($_.Architecture)" }) }

    # Everything is downloaded and hash-validated BEFORE an existing package is replaced.
    # All backups live on the same cache volume and are retained if rollback fails.
    $transactionRoot = Join-Path $stagingRoot ("Sync-{0}" -f [guid]::NewGuid().ToString('N'))
    $preparedRoot = Join-Path $transactionRoot 'Prepared'
    $backupRoot = Join-Path $transactionRoot 'Backup'
    $replacedBackupRoot = Join-Path $backupRoot 'Replaced'
    $removedBackupRoot = Join-Path $backupRoot 'Removed'
    $catalogPrepared = Join-Path $transactionRoot 'CacheCatalog.json.new'
    $catalogBackup = Join-Path $transactionRoot 'CacheCatalog.json.old'
    $promoted = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[object]]::new()
    $keepRecoveryFiles = $false
    $catalogExisted = Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf
    $catalogCommitAttempted = $false
    $committed = $false

    try {
        New-Item -ItemType Directory -Path $packagesRoot,$preparedRoot,$replacedBackupRoot,$removedBackupRoot -Force -ErrorAction Stop | Out-Null

        foreach ($entry in $toAcquire) {
            # Recheck remaining work: another process may have consumed space
            # while earlier packages were downloading.
            Assert-OSDAppTransactionSpace -Path $CachePath -ExpectedBytes $remainingBytes -Operation 'repository cache package acquisition' | Out-Null
            $package = $entry.Package
            $packageTemp = Join-Path $preparedRoot $package.Id
            New-Item -ItemType Directory -Path $packageTemp -Force -ErrorAction Stop | Out-Null
            $tempArchive = Join-Path $packageTemp 'Package.zip'

            if ($package.Archive.Uri) {
                Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Downloading package archive.' -Data @{ Id = $package.Id; Source = $package.Archive.Uri }
                Invoke-WebRequest -Uri $package.Archive.Uri -OutFile $tempArchive -UseBasicParsing -ErrorAction Stop
            }
            elseif ($package.Archive.SourcePath) {
                $sourceArchive = [string]$package.Archive.SourcePath
                if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
                    throw "Source archive not found: $sourceArchive"
                }
                Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Copying package archive.' -Data @{ Id = $package.Id; Source = $sourceArchive }
                Copy-Item -LiteralPath $sourceArchive -Destination $tempArchive -Force -ErrorAction Stop
            }
            else {
                throw "Package '$($package.Id)' archive has neither Uri nor SourcePath."
            }

            if (-not (Test-OSDAppFileHash -Path $tempArchive -ExpectedSha256 $package.Archive.Sha256)) {
                throw "SHA-256 validation failed for '$($package.Id)/Package.zip'."
            }
            $remainingBytes -= $entry.EstimatedBytes
            Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'PackagePrepared' -Message 'Package is downloaded and SHA-256 validated.' -Data @{ Id = $package.Id; Version = $package.Version }
        }

        # Stage the new catalog and save the old one before any package promotion.
        $selectedCatalog | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $catalogPrepared -Encoding UTF8 -ErrorAction Stop
        if ($catalogExisted) {
            Copy-Item -LiteralPath $cacheCatalogPath -Destination $catalogBackup -Force -ErrorAction Stop
        }

        # Stale content is moved, not deleted, until the new catalog commits.
        foreach ($entry in $toRemove) {
            $backupPath = Join-Path $removedBackupRoot $entry.Id
            Move-Item -LiteralPath $entry.Path -Destination $backupPath -ErrorAction Stop
            $removed.Add([pscustomobject]@{
                Id = $entry.Id
                TargetRoot = $entry.Path
                BackupPath = $backupPath
                Classification = $entry.Classification
            })
        }

        foreach ($entry in $toAcquire) {
            $id = [string]$entry.Package.Id
            $targetRoot = [string]$entry.TargetRoot
            $backupPath = Join-Path $replacedBackupRoot $id
            $sourcePath = Join-Path $preparedRoot $id
            $hadPrevious = Test-Path -LiteralPath $targetRoot

            if ($hadPrevious) {
                Move-Item -LiteralPath $targetRoot -Destination $backupPath -ErrorAction Stop
            }
            # Record before promoting: the second move itself could fail.
            $promoted.Add([pscustomobject]@{
                Id = $id
                TargetRoot = $targetRoot
                BackupPath = $backupPath
                HadPrevious = $hadPrevious
            })
            Move-Item -LiteralPath $sourcePath -Destination $targetRoot -ErrorAction Stop
        }

        # This is the commit point: the manifest must describe the new files.
        $catalogCommitAttempted = $true
        Publish-OSDAppCacheCatalog -SourcePath $catalogPrepared -DestinationPath $cacheCatalogPath
        $committed = $true
    }
    catch {
        $syncError = $_.Exception.Message
        $recoveryErrors = [System.Collections.Generic.List[string]]::new()
        if (-not $committed) {
            # Roll back in reverse order, restoring the exact prior directories.
            for ($i = $promoted.Count - 1; $i -ge 0; $i--) {
                $entry = $promoted[$i]
                try {
                    if (Test-Path -LiteralPath $entry.TargetRoot) {
                        Remove-Item -LiteralPath $entry.TargetRoot -Recurse -Force -ErrorAction Stop
                    }
                    if ($entry.HadPrevious) {
                        Move-Item -LiteralPath $entry.BackupPath -Destination $entry.TargetRoot -ErrorAction Stop
                    }
                }
                catch {
                    $recoveryErrors.Add("$($entry.Id): $($_.Exception.Message)")
                }
            }

            for ($i = $removed.Count - 1; $i -ge 0; $i--) {
                $entry = $removed[$i]
                try {
                    if (Test-Path -LiteralPath $entry.TargetRoot) {
                        Remove-Item -LiteralPath $entry.TargetRoot -Recurse -Force -ErrorAction Stop
                    }
                    Move-Item -LiteralPath $entry.BackupPath -Destination $entry.TargetRoot -ErrorAction Stop
                }
                catch {
                    $recoveryErrors.Add("$($entry.Id): $($_.Exception.Message)")
                }
            }

            if ($catalogCommitAttempted) {
                try {
                    if ($catalogExisted) {
                        Copy-Item -LiteralPath $catalogBackup -Destination $cacheCatalogPath -Force -ErrorAction Stop
                    }
                    elseif (Test-Path -LiteralPath $cacheCatalogPath) {
                        Remove-Item -LiteralPath $cacheCatalogPath -Force -ErrorAction Stop
                    }
                }
                catch {
                    $recoveryErrors.Add("CacheCatalog.json: $($_.Exception.Message)")
                }
            }
        }
        $keepRecoveryFiles = $recoveryErrors.Count -gt 0
        Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncFailed' -Level 'Error' -Message 'Cache transaction failed.' -Data @{
            Error = $syncError
            RollbackErrors = ($recoveryErrors -join ' | ')
            RecoveryPath = if ($keepRecoveryFiles) { $transactionRoot } else { '' }
        }
        if ($keepRecoveryFiles) {
            throw "Cache transaction failed: $syncError. Rollback incomplete ($($recoveryErrors -join '; ')). Preserve recovery data at '$transactionRoot'."
        }
        throw "Cache transaction failed: $syncError. Previous cache preserved."
    }
    finally {
        if (-not $keepRecoveryFiles -and (Test-Path -LiteralPath $transactionRoot)) {
            Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($entry in $toAcquire) {
        Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'PackageUpdated' -Message 'Package transaction committed and SHA-256 validated.' -Data @{ Id = $entry.Package.Id; Version = $entry.Package.Version; Sha256 = $entry.Package.Archive.Sha256 }
    }
    foreach ($entry in $toRemove) {
        Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'PackagePruned' -Message 'Stale cache package was removed after replacement validation and catalog commit.' -Data @{ Id = $entry.Id; Classification = $entry.Classification }
    }
    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncComplete' -Message 'Repository synchronization committed.' -Data @{
        Catalog = $cacheCatalogPath
        SyncedPackageCount = $packages.Count
        UpdatedPackageCount = $toAcquire.Count
        CachedPackageCount = @($mergedPackages).Count
        PrunedPackageCount = $toRemove.Count
        PinnedPackageCount = $pins.Count
    }

    Get-Item -LiteralPath $cacheCatalogPath
    }
    finally { $cacheLock.Dispose() }
}
