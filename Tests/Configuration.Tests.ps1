Describe 'OSDApps configuration' {
    BeforeEach {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'is silent by default when setting configuration' {
        @(Set-OSDAppConfiguration -CleanupMode Never).Count | Should -Be 0
    }

    It 'returns the effective configuration with PassThru' {
        $result = Set-OSDAppConfiguration -CleanupMode Never -CacheVolumeLabel TestCache -ResultPath 'C:\OSDApps\Latest.json' -PassThru
        $result.CleanupMode | Should -Be 'Never'
        $result.CacheVolumeLabel | Should -Be 'TestCache'
        $result.ResultPath | Should -Be 'C:\OSDApps\Latest.json'
    }

    It 'preserves values that were not changed' {
        Set-OSDAppConfiguration -CacheVolumeLabel TestCache
        Set-OSDAppConfiguration -CleanupMode Never
        $result = Get-OSDAppConfiguration
        $result.CacheVolumeLabel | Should -Be 'TestCache'
        $result.CleanupMode | Should -Be 'Never'
    }

    It 'rejects non-http catalog schemes' {
        { Set-OSDAppConfiguration -CatalogUri 'file:///C:/catalog.json' } | Should -Throw '*HTTP or HTTPS*'
    }

    It 'adds and preserves one deployment identity with complete runtime settings' {
        InModuleScope OSDApps {
            $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})
            $deploymentId = [guid]::Empty
            [guid]::TryParse([string]$manifest.DeploymentId, [ref]$deploymentId) | Should -BeTrue
            $manifest.Runtime.ResultPath | Should -Be '%ProgramData%\OSDApps\Results\Latest.json'

            $second = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
            $second.DeploymentId | Should -Be $deploymentId.Guid
        }
    }
}
