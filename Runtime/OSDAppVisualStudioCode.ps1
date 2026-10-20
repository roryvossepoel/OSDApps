# Shared by the module, PreInstall and Runner. Loading this file performs no I/O.
function Get-OSDAppVisualStudioCodePackageUri {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture
    )
    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Commit -notmatch '^[a-f0-9]{40}$') {
        throw 'Visual Studio Code stable release version or commit is invalid.'
    }
    "https://vscode.download.prss.microsoft.com/dbazure/download/stable/$Commit/VSCodeSetup-$Architecture-$Version.exe"
}

function Get-OSDAppVisualStudioCodeRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture)
    # These platforms select the system installer, never the per-user installer or ZIP.
    $release = Invoke-RestMethod -Uri "https://update.code.visualstudio.com/api/update/win32-$Architecture/stable/latest" -TimeoutSec 60 -ErrorAction Stop
    $version = [string]$release.productVersion
    $commit = [string]$release.version
    $expectedUri = Get-OSDAppVisualStudioCodePackageUri -Version $version -Commit $commit -Architecture $Architecture
    if ([string]$release.url -cne $expectedUri -or [string]$release.sha256hash -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Visual Studio Code release has an unexpected system-installer URL or missing SHA-256.'
    }
    [pscustomobject]@{ Version=$version; Commit=$commit; Architecture=$Architecture; PackageUri=$expectedUri; Sha256=[string]$release.sha256hash }
}

function Assert-OSDAppVisualStudioCodeGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture,
        [psobject]$Release,
        [switch]$VerifyPublisher
    )
    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $expectedUri = Get-OSDAppVisualStudioCodePackageUri -Version ([string]$info.Version) -Commit ([string]$info.Commit) -Architecture $Architecture
    if ([string]$info.Id -ne 'VisualStudioCode' -or [string]$info.Architecture -ne $Architecture -or
        [string]$info.PackageUri -cne $expectedUri -or [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        [long]$info.Size -le 0) { throw 'Visual Studio Code cache metadata is invalid or incompatible.' }
    if ($Release -and ([string]$info.Version -ne [string]$Release.Version -or
        [string]$info.Commit -ne [string]$Release.Commit -or [string]$info.Sha256 -ne [string]$Release.Sha256 -or
        [string]$info.PackageUri -cne [string]$Release.PackageUri)) { throw 'Visual Studio Code cache does not match the current official release.' }
    $package = Join-Path $Root 'Package.exe'
    if ((Get-Item -LiteralPath $package -ErrorAction Stop).Length -ne [long]$info.Size -or
        (Get-FileHash -LiteralPath $package -Algorithm SHA256 -ErrorAction Stop).Hash -ne [string]$info.Sha256) {
        throw 'Visual Studio Code package size or SHA-256 does not match the recorded release.'
    }
    # Inno Setup's bootstrapper architecture need not equal its payload architecture.
    # The exact official platform URL and release digest identify the intended payload.
    if ($VerifyPublisher) {
        $signature = Get-AuthenticodeSignature -LiteralPath $package -ErrorAction Stop
        if ([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
            [string]$signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=(?:Microsoft Corporation|"Microsoft Corporation")(?=,|$)') {
            throw 'Visual Studio Code installer must have a valid Microsoft Corporation Authenticode signature.'
        }
    }
    $info
}

function Sync-OSDAppVisualStudioCodeGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture,
        [Parameter(Mandatory)][scriptblock]$Download,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    $downloadAction = $Download
    Restore-OSDAppCacheGeneration -Root $Root -Validate {
        param($candidate)
        Assert-OSDAppVisualStudioCodeGeneration -Root $candidate -Architecture $Architecture -VerifyPublisher
    } | Out-Null
    $release = Get-OSDAppVisualStudioCodeRelease -Architecture $Architecture
    $current = $false
    try { Assert-OSDAppVisualStudioCodeGeneration -Root $Root -Architecture $Architecture -Release $release -VerifyPublisher | Out-Null; $current = $true }
    catch { Write-Verbose "Visual Studio Code cache requires acquisition: $($_.Exception.Message)" }
    if (-not $current) {
        # The update API publishes a SHA-256, but no byte count. Preserve the normal
        # free-space reserve; record actual length and validate the digest after download.
        Invoke-OSDAppBuiltInCacheTransaction -Root $Root -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
            param($candidate)
            $package = Join-Path $candidate 'Package.exe'
            & $downloadAction $release.PackageUri $package | Out-Null
            [ordered]@{
                Id='VisualStudioCode'; Cached=$true; Version=$release.Version; Commit=$release.Commit;
                VersionSource='MicrosoftUpdateService'; Architecture=$Architecture;
                PackageUri=$release.PackageUri; Sha256=$release.Sha256; Size=(Get-Item -LiteralPath $package -ErrorAction Stop).Length;
                SourcePolicy='Evergreen'; SyncMethod='ReleaseSha256'; SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8
        } -Validate {
            param($candidate)
            Assert-OSDAppVisualStudioCodeGeneration -Root $candidate -Architecture $Architecture -Release $release -VerifyPublisher
        } | Out-Null
    }
    [pscustomobject]@{ Id='VisualStudioCode'; Version=$release.Version; Architecture=$Architecture; Root=$Root; Updated=(-not $current) }
}
