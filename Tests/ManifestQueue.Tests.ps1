Describe 'DeviceManifest app queue' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'appends apps in Add order' {
        InModuleScope OSDApps {
            $manifest = [pscustomobject]@{}
            $manifest = Set-OSDAppManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='First'; Source='Repository' })
            $manifest = Set-OSDAppManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='Second'; Source='BuiltIn' })

            @($manifest.Apps.Id) | Should -Be @('First','Second')
        }
    }

    It 'moves a re-added app to the end without duplication' {
        InModuleScope OSDApps {
            $manifest = [pscustomobject]@{
                Apps = @(
                    [pscustomobject]@{ Id='First'; Source='Repository' },
                    [pscustomobject]@{ Id='Second'; Source='BuiltIn' }
                )
            }

            $manifest = Set-OSDAppManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='First'; Source='Repository'; Version='2.0' })

            @($manifest.Apps.Id) | Should -Be @('Second','First')
            @($manifest.Apps | Where-Object Id -eq 'First').Count | Should -Be 1
            ($manifest.Apps | Where-Object Id -eq 'First').Version | Should -Be '2.0'
        }
    }

    It 'removes legacy queue properties' {
        InModuleScope OSDApps {
            $manifest = [pscustomobject]@{
                Packages = @()
                BuiltInApps = @()
                InstallOrder = @()
            }

            $manifest = Set-OSDAppManifestApp -Manifest $manifest -App ([pscustomobject]@{ Id='App'; Source='Repository' })

            $manifest.PSObject.Properties.Name | Should -Not -Contain 'Packages'
            $manifest.PSObject.Properties.Name | Should -Not -Contain 'BuiltInApps'
            $manifest.PSObject.Properties.Name | Should -Not -Contain 'InstallOrder'
        }
    }
}
