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

        [ValidateSet('App','Script','Font','Certificate')]
        [string]$PackageType,

        [ValidateSet('Root','CA')][string]$CertificateStore,

        [int[]]$SuccessCodes = @(0,3010),

        [string[]]$Alias
    )

    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Id -match '\.\.') {
        throw "Invalid package Id '$Id'."
    }
    $targetFolder = Join-Path $RepositoryPath (Join-Path 'Apps' (Join-Path $Id (Join-Path $Version $Architecture)))
    $targetPackage = Join-Path $targetFolder 'Package.zip'
    $targetManifest = Join-Path $targetFolder 'manifest.json'

    $catalog = Get-OSDAppRepositoryManifest -RepositoryPath $RepositoryPath
    $existingApp = @($catalog.Apps | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
    if ($PSBoundParameters.ContainsKey('PackageType')) {
        $PackageType = if ($PackageType -ieq 'Script') { 'Script' } elseif ($PackageType -ieq 'Font') { 'Font' } elseif ($PackageType -ieq 'Certificate') { 'Certificate' } else { 'App' }
    }
    elseif (Test-Path -LiteralPath $targetManifest -PathType Leaf) {
        $existingPackageManifest = Get-OSDAppManifest -Path $targetManifest
        $existingPackageType = if ($existingPackageManifest.PSObject.Properties.Name -contains 'PackageType' -and
            -not [string]::IsNullOrWhiteSpace([string]$existingPackageManifest.PackageType)) {
            [string]$existingPackageManifest.PackageType
        }
        else {
            'App'
        }
        if ($existingPackageType -notin @('App','Script','Font','Certificate')) {
            throw "Existing package '$Id' has unsupported PackageType '$existingPackageType'."
        }
        $PackageType = if ($existingPackageType -ieq 'Script') { 'Script' } elseif ($existingPackageType -ieq 'Font') { 'Font' } elseif ($existingPackageType -ieq 'Certificate') { 'Certificate' } else { 'App' }
    }
    else {
        $PackageType = 'App'
    }

    $testParameters=@{PackagePath=$PackagePath;PackageType=$PackageType}
    if ($PackageType -eq 'Certificate') {
        if (-not $PSBoundParameters.ContainsKey('CertificateStore') -and (Test-Path -LiteralPath $targetManifest -PathType Leaf)) {
            $existingCertificateManifest=Get-OSDAppManifest -Path $targetManifest
            if ([string]$existingCertificateManifest.PackageType -eq 'Certificate') { $CertificateStore=[string]$existingCertificateManifest.CertificateStore }
        }
        if ($CertificateStore -notin @('Root','CA')) { throw 'Certificate packages require CertificateStore Root or CA; no store is selected automatically.' }
        $CertificateStore=if($CertificateStore -ieq 'Root'){'Root'}else{'CA'}
        $testParameters.CertificateStore=$CertificateStore
    }
    elseif ($PSBoundParameters.ContainsKey('CertificateStore')) { throw 'CertificateStore is only valid for Certificate packages.' }
    $packageTest = Test-OSDAppPackage @testParameters
    if (-not $packageTest.Valid) {
        if ($PackageType -eq 'Certificate') { throw ('Certificate package validation failed: '+$packageTest.Error) }
        if ($PackageType -eq 'Font') {
            throw 'Font package validation failed. Package.zip must contain Package/ with at least one .ttf or .otf file.'
        }
        throw 'Package validation failed. Package.zip must contain Package/Install.ps1.'
    }

    $effectiveAliases = if ($PSBoundParameters.ContainsKey('Alias')) {
        @($Alias | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    }
    elseif ($existingApp.Count -gt 0 -and
        $existingApp[0].PSObject.Properties.Name -contains 'Aliases') {
        @($existingApp[0].Aliases)
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

    foreach ($app in @($catalog.Apps | Where-Object { $_.Id -ne $Id })) {
        if ([string]$app.Id -ieq $Id) { continue }
        if ([string]$app.Id -in $effectiveAliases) {
            throw "Alias '$($app.Id)' for '$Id' conflicts with an existing canonical app Id."
        }
        $otherAliases = @(
            if ($app.PSObject.Properties.Name -contains 'Aliases') {
                @($app.Aliases)
            }
        )
        if ($Id -in $otherAliases) {
            throw "Canonical Id '$Id' is already an alias of '$($app.Id)'."
        }
        $conflicts = @($effectiveAliases | Where-Object { $_ -in $otherAliases })
        if ($conflicts.Count -gt 0) {
            throw "Alias '$($conflicts[0])' is already assigned to '$($app.Id)'."
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

    if ($PackageType -eq 'Certificate') { $packageManifest['CertificateStore']=$CertificateStore }

    # Vendor is optional descriptive metadata, not an installer parameter.
    # Older repositories remain compatible when it is absent.
    if (-not [string]::IsNullOrWhiteSpace($Vendor)) {
        $packageManifest['Vendor'] = $Vendor.Trim()
    }

    $packageManifest |
        ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $targetManifest -Encoding UTF8

    if ($existingApp.Count -gt 0) {
        $appPackages = @(
            $existingApp[0].Packages |
                Where-Object {
                    ([string]$_.Architecture).ToLowerInvariant() -ne $Architecture.ToLowerInvariant()
                }
        )
    }
    else {
        $appPackages = @()
    }

    $manifestRelativePath = "Apps/$Id/$Version/$Architecture/manifest.json"
    $packageReference = [pscustomobject]@{
        Architecture = $Architecture
        Manifest     = $manifestRelativePath
    }

    $appEntryData = [ordered]@{
        Id       = $Id
        Packages = @($appPackages) + $packageReference
    }
    if ($effectiveAliases.Count -gt 0) {
        $appEntryData['Aliases'] = @($effectiveAliases)
    }
    $appEntry = [pscustomobject]$appEntryData

    $catalog.Apps = @(
        @($catalog.Apps | Where-Object { $_.Id -ne $Id }) +
        $appEntry
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
        CertificateStore = if($PackageType -eq 'Certificate'){$CertificateStore}else{$null}
        SuccessCodes = @($SuccessCodes)
        Aliases      = @($effectiveAliases)
        ManifestPath = $manifestRelativePath
        Archive      = [pscustomobject]$packageManifest.Archive
    }
}
