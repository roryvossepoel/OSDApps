function Add-OSDAppPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$Vendor,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][string]$RepositoryPath,

        [ValidateSet('x64','arm64','any')]
        [string]$Architecture = 'x64',

        [ValidateSet('Application','Script')]
        [string]$PackageType,

        [int[]]$SuccessCodes = @(0,3010),

        [string[]]$Alias
    )

    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Id -match '\.\.') {
        throw "Invalid package Id '$Id'."
    }
    $packageTest = Test-OSDAppPackage -PackagePath $PackagePath
    if (-not $packageTest.Valid) {
        throw 'Package validation failed. Package.zip must contain Package/Install.ps1.'
    }

    $targetFolder = Join-Path $RepositoryPath (Join-Path 'Apps' (Join-Path $Id (Join-Path $Version $Architecture)))
    $targetPackage = Join-Path $targetFolder 'Package.zip'
    $targetManifest = Join-Path $targetFolder 'manifest.json'

    $catalog = Get-OSDAppRepositoryManifest -RepositoryPath $RepositoryPath
    $existingApplication = @($catalog.Applications | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
    if ($PSBoundParameters.ContainsKey('PackageType')) {
        $PackageType = if ($PackageType -ieq 'Script') { 'Script' } else { 'Application' }
    }
    elseif (Test-Path -LiteralPath $targetManifest -PathType Leaf) {
        $existingPackageManifest = Get-OSDAppManifest -Path $targetManifest
        $existingPackageType = if ($existingPackageManifest.PSObject.Properties.Name -contains 'PackageType' -and
            -not [string]::IsNullOrWhiteSpace([string]$existingPackageManifest.PackageType)) {
            [string]$existingPackageManifest.PackageType
        }
        else {
            'Application'
        }
        if ($existingPackageType -notin @('Application','Script')) {
            throw "Existing package '$Id' has unsupported PackageType '$existingPackageType'."
        }
        $PackageType = if ($existingPackageType -ieq 'Script') { 'Script' } else { 'Application' }
    }
    else {
        $PackageType = 'Application'
    }
    $effectiveAliases = if ($PSBoundParameters.ContainsKey('Alias')) {
        @($Alias | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    }
    elseif ($existingApplication.Count -gt 0 -and
        $existingApplication[0].PSObject.Properties.Name -contains 'Aliases') {
        @($existingApplication[0].Aliases)
    }
    else {
        @()
    }

    foreach ($aliasValue in $effectiveAliases) {
        $aliasId = [string]$aliasValue
        if ([string]::IsNullOrWhiteSpace($aliasId) -or
            $aliasId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $aliasId -match '\.\.') {
            throw "Invalid alias '$aliasId' for '$Id'."
        }
        if ($aliasId -ieq $Id) {
            throw "Alias '$aliasId' cannot be the same as canonical Id '$Id'."
        }
    }

    foreach ($application in @($catalog.Applications | Where-Object { $_.Id -ne $Id })) {
        if ([string]$application.Id -ieq $Id) { continue }
        if ([string]$application.Id -in $effectiveAliases) {
            throw "Alias '$($application.Id)' for '$Id' conflicts with an existing canonical application Id."
        }
        $otherAliases = @(
            if ($application.PSObject.Properties.Name -contains 'Aliases') {
                @($application.Aliases)
            }
        )
        if ($Id -in $otherAliases) {
            throw "Canonical Id '$Id' is already an alias of '$($application.Id)'."
        }
        $conflicts = @($effectiveAliases | Where-Object { $_ -in $otherAliases })
        if ($conflicts.Count -gt 0) {
            throw "Alias '$($conflicts[0])' is already assigned to '$($application.Id)'."
        }
    }

    if (-not $PSCmdlet.ShouldProcess($targetFolder, "Publish $Id $Version ($Architecture)")) {
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryPath 'catalog.json') -PathType Leaf)) {
        New-OSDAppRepository -Path $RepositoryPath -Confirm:$false | Out-Null
    }

    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    Copy-Item -LiteralPath $PackagePath -Destination $targetPackage -Force

    $hash = (Get-FileHash -LiteralPath $targetPackage -Algorithm SHA256).Hash

    $packageManifest = [ordered]@{
        SchemaVersion = 1
        Id            = $Id
        DisplayName   = $DisplayName
        Version       = $Version
        Architecture  = $Architecture
        PackageType   = $PackageType
        SuccessCodes  = @($SuccessCodes)
        Archive       = [ordered]@{
            FileName = 'Package.zip'
            Sha256   = $hash
        }
    }

    # Vendor is optional descriptive metadata, not an installer parameter.
    # Older repositories remain compatible when it is absent.
    if (-not [string]::IsNullOrWhiteSpace($Vendor)) {
        $packageManifest['Vendor'] = $Vendor.Trim()
    }

    $packageManifest |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $targetManifest -Encoding UTF8

    if ($existingApplication.Count -gt 0) {
        $applicationPackages = @(
            $existingApplication[0].Packages |
                Where-Object {
                    ([string]$_.Architecture).ToLowerInvariant() -ne $Architecture.ToLowerInvariant()
                }
        )
    }
    else {
        $applicationPackages = @()
    }

    $manifestRelativePath = "Apps/$Id/$Version/$Architecture/manifest.json"
    $packageReference = [pscustomobject]@{
        Architecture = $Architecture
        Manifest     = $manifestRelativePath
    }

    $applicationEntryData = [ordered]@{
        Id       = $Id
        Packages = @($applicationPackages) + $packageReference
    }
    if ($effectiveAliases.Count -gt 0) {
        $applicationEntryData['Aliases'] = @($effectiveAliases)
    }
    $applicationEntry = [pscustomobject]$applicationEntryData

    $catalog.Applications = @(
        @($catalog.Applications | Where-Object { $_.Id -ne $Id }) +
        $applicationEntry
    )

    Save-OSDAppRepositoryManifest -Manifest $catalog -RepositoryPath $RepositoryPath | Out-Null

    [pscustomobject]@{
        PSTypeName   = 'OSDApps.RepositoryPackage'
        Id           = $Id
        DisplayName  = $DisplayName
        Vendor       = if ($Vendor) { $Vendor.Trim() } else { $null }
        Version      = $Version
        Architecture = $Architecture
        PackageType  = $PackageType
        SuccessCodes = @($SuccessCodes)
        Aliases      = @($effectiveAliases)
        ManifestPath = $manifestRelativePath
        Archive      = [pscustomobject]$packageManifest.Archive
    }
}
