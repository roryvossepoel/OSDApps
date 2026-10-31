Describe 'Repository staging without OSDCloud USB' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'uses offline Windows cache when USB cache resolution fails' {
        InModuleScope OSDStage {
            $root = Join-Path $TestDrive 'WindowsVolume'
            $stage = Join-Path $root 'Windows\Temp\OSDStage'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $manifest = [pscustomobject]@{ SchemaVersion='2.0'; StagedAt=''; Packages=@() }
            $manifest | ConvertTo-Json | Set-Content (Join-Path $stage 'DeviceManifest.json')

            Mock Get-OSDStageCachePath { throw "No volume with label 'OSDCloud' was found." }
            Mock Resolve-OSDStageWindowsPath { return $root }
            Mock Get-OSDStageConfiguration { return [pscustomobject]@{ CatalogUri='https://example.org/catalog.json' } }
            Mock Sync-OSDStageCache {}
            Mock Copy-OSDStageContent {}
            Mock Set-OSDStageManifestRuntimeConfiguration { param($Manifest) return $Manifest }
            Mock Add-OSDStageSetupComplete {}

            $result = Add-OSDStage -Name 'NotepadPlusPlus' -WindowsPath $root
            $result.CachePath | Should -Be (Join-Path $root 'Windows\Temp\OSDStage\RepositoryCache')
            Should -Invoke Sync-OSDStageCache -Exactly 1 -ParameterFilter {
                $CachePath -eq (Join-Path $root 'Windows\Temp\OSDStage\RepositoryCache')
            }
            Should -Invoke Copy-OSDStageContent -Exactly 1
        }
    }

    It 'returns no entries rather than throwing when the USB cache is missing' {
        InModuleScope OSDStage {
            Mock Get-OSDStageCachePath { throw "No volume with label 'OSDCloud' was found." }
            { @(Get-OSDStageCache) } | Should -Not -Throw
            @(Get-OSDStageCache).Count | Should -Be 0
        }
    }
}
