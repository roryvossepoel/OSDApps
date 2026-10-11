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

        [int[]]$SuccessCodes = @(0,3010)
    )

    $packageTest = Test-OSDAppPackage -PackagePath $PackagePath
    if (-not $packageTest.Valid) {
        throw 'Package validation failed. Package.zip must contain Package/Install.ps1.'
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryPath 'catalog.json') -PathType Leaf)) {
        New-OSDAppRepository -Path $RepositoryPath -Confirm:$false | Out-Null
    }

    $targetFolder = Join-Path $RepositoryPath (Join-Path 'Apps' (Join-Path $Id (Join-Path $Version $Architecture)))
    $targetPackage = Join-Path $targetFolder 'Package.zip'
    $targetManifest = Join-Path $targetFolder 'manifest.json'

    if ($PSCmdlet.ShouldProcess($targetFolder, "Publish $Id $Version ($Architecture)")) {
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
        Copy-Item -LiteralPath $PackagePath -Destination $targetPackage -Force
    }

    $hash = (Get-FileHash -LiteralPath $targetPackage -Algorithm SHA256).Hash

    $packageManifest = [ordered]@{
        SchemaVersion = 1
        Id            = $Id
        DisplayName   = $DisplayName
        Version       = $Version
        Architecture  = $Architecture
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

    if ($PSCmdlet.ShouldProcess($targetManifest, 'Write package manifest')) {
        $packageManifest |
            ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $targetManifest -Encoding UTF8
    }

    $catalog = Get-OSDAppRepositoryManifest -RepositoryPath $RepositoryPath
    $existingApplication = @($catalog.Applications | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)

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

    $applicationEntry = [pscustomobject]@{
        Id       = $Id
        Packages = @($applicationPackages) + $packageReference
    }

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
        SuccessCodes = @($SuccessCodes)
        ManifestPath = $manifestRelativePath
        Archive      = [pscustomobject]$packageManifest.Archive
    }
}
