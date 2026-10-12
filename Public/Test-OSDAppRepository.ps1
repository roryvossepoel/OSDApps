function Test-OSDAppRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$RepositoryPath
    )

    $resolvedRepository = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
    $catalog = Get-OSDAppRepositoryManifest -RepositoryPath $resolvedRepository

    $driveRoot = [IO.Path]::GetPathRoot($resolvedRepository)
    $repositoryFreeSpaceGB = $null
    try {
        $drive = Get-PSDrive -Name $driveRoot.TrimEnd('\').TrimEnd(':') -ErrorAction Stop
        $repositoryFreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    }
    catch {
        # Capacity is optional reporting data, not a package validity requirement.
        Write-Verbose "Repository free space could not be determined for '$resolvedRepository': $($_.Exception.Message)"
    }

    $allRefs = @()
    foreach ($application in @($catalog.Applications)) {
        foreach ($packageRef in @($application.Packages)) {
            $allRefs += [pscustomobject]@{
                Id = [string]$application.Id
                Architecture = [string]$packageRef.Architecture
                Manifest = [string]$packageRef.Manifest
            }
        }
    }

    $duplicateKeys = @(
        $allRefs |
            Group-Object { "$($_.Id.ToLowerInvariant())|$($_.Architecture.ToLowerInvariant())" } |
            Where-Object Count -gt 1 |
            Select-Object -ExpandProperty Name
    )

    $referencedManifestPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($application in @($catalog.Applications)) {
        foreach ($packageRef in @($application.Packages)) {
            $manifestPath = Join-Path $resolvedRepository ($packageRef.Manifest -replace '/', [IO.Path]::DirectorySeparatorChar)
            $fullManifestPath = [IO.Path]::GetFullPath($manifestPath)
            [void]$referencedManifestPaths.Add($fullManifestPath)

            $manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
            $duplicateReference = ("$(([string]$application.Id).ToLowerInvariant())|$(([string]$packageRef.Architecture).ToLowerInvariant())") -in $duplicateKeys

            if (-not $manifestExists) {
                [pscustomobject]@{
                    PSTypeName            = 'OSDApps.RepositoryValidation'
                    Id                    = $application.Id
                    Version               = $null
                    Architecture          = $packageRef.Architecture
                    ManifestExists        = $false
                    PackageExists         = $false
                    HashValid             = $false
                    PackageValid          = $false
                    ArchitectureValid     = $false
                    IdValid               = $false
                    SuccessCodesValid     = $false
                    ArchiveDefinitionValid= $false
                    DuplicateReference    = $duplicateReference
                    Orphaned              = $false
                    SizeMB                = $null
                    RepositoryFreeSpaceGB = $repositoryFreeSpaceGB
                    Valid                 = $false
                }
                continue
            }

            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $packagePath = Join-Path (Split-Path -Path $manifestPath -Parent) 'Package.zip'
            $exists = Test-Path -LiteralPath $packagePath -PathType Leaf
            $hashValid = $false
            $packageValid = $false
            $sizeMB = $null

            $archiveDefinitionValid = (
                $manifest.Archive -and
                [string]$manifest.Archive.FileName -eq 'Package.zip' -and
                [string]$manifest.Archive.Sha256 -match '^[A-Fa-f0-9]{64}$'
            )

            if ($exists) {
                $sizeMB = [math]::Round((Get-Item -LiteralPath $packagePath).Length / 1MB, 1)
                if ($archiveDefinitionValid) {
                    $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
                    $hashValid = $actualHash.Equals([string]$manifest.Archive.Sha256, [System.StringComparison]::OrdinalIgnoreCase)
                }
                $packageValid = (Test-OSDAppPackage -PackagePath $packagePath).Valid
            }

            $architectureValid = (
                ([string]$manifest.Architecture).ToLowerInvariant() -in @('x64','arm64','any') -and
                ([string]$manifest.Architecture).ToLowerInvariant() -eq ([string]$packageRef.Architecture).ToLowerInvariant()
            )
            $idValid = [string]$manifest.Id -eq [string]$application.Id
            $successCodes = @($manifest.SuccessCodes)
            $successCodesValid = (
                $successCodes.Count -gt 0 -and
                @($successCodes | Where-Object { $null -eq ($_ -as [int]) }).Count -eq 0
            )

            [pscustomobject]@{
                PSTypeName             = 'OSDApps.RepositoryValidation'
                Id                     = $manifest.Id
                Version                = $manifest.Version
                Architecture           = $manifest.Architecture
                ManifestExists         = $true
                PackageExists          = $exists
                HashValid              = $hashValid
                PackageValid           = $packageValid
                ArchitectureValid      = $architectureValid
                IdValid                = $idValid
                SuccessCodesValid      = $successCodesValid
                ArchiveDefinitionValid = $archiveDefinitionValid
                DuplicateReference     = $duplicateReference
                Orphaned               = $false
                SizeMB                 = $sizeMB
                RepositoryFreeSpaceGB  = $repositoryFreeSpaceGB
                Valid                  = (
                    $exists -and
                    $hashValid -and
                    $packageValid -and
                    $architectureValid -and
                    $idValid -and
                    $successCodesValid -and
                    $archiveDefinitionValid -and
                    -not $duplicateReference
                )
            }
        }
    }

    $appsRoot = Join-Path $resolvedRepository 'Apps'
    if (Test-Path -LiteralPath $appsRoot -PathType Container) {
        foreach ($manifestFile in @(Get-ChildItem -LiteralPath $appsRoot -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            $fullPath = [IO.Path]::GetFullPath($manifestFile.FullName)
            if (-not $referencedManifestPaths.Contains($fullPath)) {
                $orphanManifest = $null
                try { $orphanManifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
                catch {
                    # Keep reporting the orphan as invalid, even when its JSON is unreadable.
                    Write-Verbose "Orphan manifest could not be read from '$($manifestFile.FullName)': $($_.Exception.Message)"
                }
                $orphanPackage = Join-Path $manifestFile.DirectoryName 'Package.zip'

                [pscustomobject]@{
                    PSTypeName             = 'OSDApps.RepositoryValidation'
                    Id                     = if ($orphanManifest) { $orphanManifest.Id } else { $null }
                    Version                = if ($orphanManifest) { $orphanManifest.Version } else { $null }
                    Architecture           = if ($orphanManifest) { $orphanManifest.Architecture } else { $null }
                    ManifestExists         = $true
                    PackageExists          = Test-Path -LiteralPath $orphanPackage -PathType Leaf
                    HashValid              = $false
                    PackageValid           = $false
                    ArchitectureValid      = $false
                    IdValid                = $false
                    SuccessCodesValid      = $false
                    ArchiveDefinitionValid = $false
                    DuplicateReference     = $false
                    Orphaned               = $true
                    SizeMB                 = if (Test-Path -LiteralPath $orphanPackage -PathType Leaf) { [math]::Round((Get-Item -LiteralPath $orphanPackage).Length / 1MB, 1) } else { $null }
                    RepositoryFreeSpaceGB  = $repositoryFreeSpaceGB
                    Valid                  = $false
                }
            }
        }
    }
}
