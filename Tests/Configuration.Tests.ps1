Describe 'OSDStage configuration' {
    BeforeEach {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'is silent by default when setting configuration' {
        @(Set-OSDStageConfiguration -CleanupMode Never).Count | Should -Be 0
    }

    It 'returns the effective configuration with PassThru' {
        $result = Set-OSDStageConfiguration -CleanupMode Never -CacheVolumeLabel TestCache -ResultPath 'C:\OSDStage\Latest.json' -PassThru
        $result.CleanupMode | Should -Be 'Never'
        $result.CacheVolumeLabel | Should -Be 'TestCache'
        $result.ResultPath | Should -Be 'C:\OSDStage\Latest.json'
    }

    It 'preserves values that were not changed' {
        Set-OSDStageConfiguration -CacheVolumeLabel TestCache
        Set-OSDStageConfiguration -CleanupMode Never
        $result = Get-OSDStageConfiguration
        $result.CacheVolumeLabel | Should -Be 'TestCache'
        $result.CleanupMode | Should -Be 'Never'
    }

    It 'rejects non-http catalog schemes' {
        { Set-OSDStageConfiguration -CatalogUri 'file:///C:/catalog.json' } | Should -Throw '*HTTP or HTTPS*'
    }

    It 'adds and preserves one deployment identity with complete runtime settings' {
        InModuleScope OSDStage {
            $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})
            $deploymentId = [guid]::Empty
            [guid]::TryParse([string]$manifest.DeploymentId, [ref]$deploymentId) | Should -BeTrue
            $manifest.Runtime.ResultPath | Should -Be '%ProgramData%\OSDStage\Results\Latest.json'

            $second = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
            $second.DeploymentId | Should -Be $deploymentId.Guid
        }
    }
}
