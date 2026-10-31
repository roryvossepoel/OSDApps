Describe 'DeviceManifest app queue' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'appends apps in Add order' {
        InModuleScope OSDStage {
            $manifest = [pscustomobject]@{}
            $manifest = Set-OSDStageManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='First'; Source='Repository' })
            $manifest = Set-OSDStageManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='Second'; Source='BuiltIn' })

            @($manifest.Packages.Id) | Should -Be @('First','Second')
        }
    }

    It 'moves a re-added app to the end without duplication' {
        InModuleScope OSDStage {
            $manifest = [pscustomobject]@{
                Packages = @(
                    [pscustomobject]@{ Id='First'; Source='Repository' },
                    [pscustomobject]@{ Id='Second'; Source='BuiltIn' }
                )
            }

            $manifest = Set-OSDStageManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='First'; Source='Repository'; Version='2.0' })

            @($manifest.Packages.Id) | Should -Be @('Second','First')
            @($manifest.Packages | Where-Object Id -eq 'First').Count | Should -Be 1
            ($manifest.Packages | Where-Object Id -eq 'First').Version | Should -Be '2.0'
        }
    }

}
