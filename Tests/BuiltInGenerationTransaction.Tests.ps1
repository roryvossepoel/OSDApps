Describe 'Built-in cache generation transactions' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'keeps the active generation unchanged when candidate validation fails' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'BuiltIn\Example\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Package.msi') -Value 'old-generation' -Encoding ASCII
            $before = (Get-FileHash -LiteralPath (Join-Path $root 'Package.msi') -Algorithm SHA256).Hash

            {
                Invoke-OSDAppBuiltInCacheTransaction -Root $root -Build {
                    param($candidate)
                    Set-Content -LiteralPath (Join-Path $candidate 'Package.msi') -Value 'new-generation' -Encoding ASCII
                } -Validate { throw 'simulated candidate validation failure' }
            } | Should -Throw '*simulated candidate validation failure*'

            (Get-FileHash -LiteralPath (Join-Path $root 'Package.msi') -Algorithm SHA256).Hash | Should -Be $before
            @((Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Directory | Where-Object Name -Like 'x64.osdapps-*')).Count | Should -Be 0
        }
    }

    It 'promotes one validated generation and removes transaction residue' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'BuiltIn\Example\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Package.msi') -Value 'old-generation' -Encoding ASCII
            New-Item -ItemType Directory -Path "$root.osdapps-new-stale" -Force | Out-Null
            New-Item -ItemType Directory -Path "$root.osdapps-old-stale" -Force | Out-Null

            Invoke-OSDAppBuiltInCacheTransaction -Root $root -Build {
                param($candidate)
                Set-Content -LiteralPath (Join-Path $candidate 'Package.msi') -Value 'new-generation' -Encoding ASCII
            } -Validate {
                param($candidate)
                if ((Get-Content -LiteralPath (Join-Path $candidate 'Package.msi') -Raw).Trim() -ne 'new-generation') { throw 'invalid candidate' }
            } | Out-Null

            (Get-Content -LiteralPath (Join-Path $root 'Package.msi') -Raw).Trim() | Should -Be 'new-generation'
            @((Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Directory | Where-Object Name -Like 'x64.osdapps-*')).Count | Should -Be 0
        }
    }

    It 'wires all non-Office public synchronizers through complete generation validation' {
        $ids = @('MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')
        foreach ($id in $ids) {
            $source = Get-Content -LiteralPath (Join-Path $moduleRoot "Public\Sync-OSDApp$id.ps1") -Raw
            $source | Should -Match 'Invoke-OSDAppBuiltInCacheTransaction|Sync-OSDAppVendorBuiltInCache'
        }
    }

    It 'uses sibling transactions in every SetupComplete non-Office refresh path' {
        $runtime = Get-Content -LiteralPath (Join-Path $moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw
        @([regex]::Matches($runtime,'\.osdapps-new-')).Count | Should -BeGreaterOrEqual 4
        $runtime | Should -Match 'candidate generation is incomplete'
        $runtime | Should -Match 'Adobe candidate metadata is inconsistent'
        $runtime | Should -Match 'candidateBootstrapper=Join-Path \$transactionRoot ''teamsbootstrapper.exe'''
    }
}
