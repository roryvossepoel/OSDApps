function Restore-OSDAppBuiltInCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id,
        [string]$LogPath
    )

    $recovery = Restore-OSDAppCacheGeneration -Root $Root -Validate {
        param($candidate)
        Assert-OSDAppRecoverableBuiltInGeneration -Root $candidate -Id $Id -SignatureValidator {
            param($appId, $file)
            Assert-OSDAppBuiltInSignature -Id $appId -FilePath $file | Out-Null
        } -OfficeValidator {
            param($officeRoot, $version, $architecture)
            Test-OSDAppOfficeCacheGeneration -OfficeRoot $officeRoot -ExpectedVersion $version -Architecture $architecture | Out-Null
        } -TeamsVersionReader {
            param($file)
            Get-OSDAppMicrosoftTeamsPackageVersion -Path $file
        }
    }
    if ($recovery -and $LogPath) {
        Write-OSDAppLog -LogPath $LogPath -Component $Id -Event 'CacheGenerationRecovered' -Message 'Validated previous cache generation restored after an interrupted directory swap.' -Data @{Path=$Root;PreviousPath=$recovery.PreviousPath}
    }
}
