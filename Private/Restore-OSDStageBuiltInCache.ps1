function Restore-OSDStageBuiltInCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Id,
        [string]$LogPath
    )

    $recovery = Restore-OSDStageCacheGeneration -Root $Root -Validate {
        param($candidate)
        Assert-OSDStageRecoverableBuiltInGeneration -Root $candidate -Id $Id -SignatureValidator {
            param($appId, $file)
            Assert-OSDStageBuiltInSignature -Id $appId -FilePath $file | Out-Null
        } -OfficeValidator {
            param($officeRoot, $version, $architecture)
            Test-OSDStageOfficeCacheGeneration -OfficeRoot $officeRoot -ExpectedVersion $version -Architecture $architecture | Out-Null
        } -TeamsVersionReader {
            param($file)
            Get-OSDStageMicrosoftTeamsPackageVersion -Path $file
        }
    }
    if ($recovery -and $LogPath) {
        Write-OSDStageLog -LogPath $LogPath -Component $Id -Event 'CacheGenerationRecovered' -Message 'Validated previous cache generation restored after an interrupted directory swap.' -Data @{Path=$Root;PreviousPath=$recovery.PreviousPath}
    }
}
