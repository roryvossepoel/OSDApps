Describe 'Show-OSDAppUI MVP - staging adapter' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'does not query the configured remote repository when Get-OSDApp -Offline is used' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration {
                [pscustomobject]@{ CatalogUri = [uri]'https://example.org/catalog.json' }
            }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Get-OSDAppCatalogPackages { throw 'Online repository was queried unexpectedly' }

            $apps = @(Get-OSDApp -Offline -ErrorAction Stop)
            @($apps | Where-Object Source -eq 'BuiltIn').Count | Should -Be 6
            Should -Invoke Get-OSDAppCatalogPackages -Exactly 0
            (Get-OSDAppConfiguration).CatalogUri.AbsoluteUri | Should -Be 'https://example.org/catalog.json'
        }
    }

    It 'queries the configured repository when offline mode is not requested' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration {
                [pscustomobject]@{ CatalogUri = [uri]'https://example.org/catalog.json' }
            }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Get-OSDAppCatalogPackages { [pscustomobject]@{ Packages = @() } }

            Get-OSDApp -ErrorAction Stop | Out-Null
            Should -Invoke Get-OSDAppCatalogPackages -Exactly 1
        }
    }

    It 'exports the public UI command but does not load GUI assemblies at module import' {
        Get-Command Show-OSDAppUI -Module OSDApps | Should -Not -BeNullOrEmpty
    }

    It 'stages repository apps as a single P1 transaction with offline refresh disabled' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDApp {}
            Mock Get-OSDAppUIStagedIds { 'AppA'; 'AppB' }

            $apps = @(
                [pscustomobject]@{ Id='AppA';Source='Repository' },
                [pscustomobject]@{ Id='AppB';Source='Repository' }
            )
            $result = Invoke-OSDAppUIStage -Applications $apps -WindowsPath 'C:\OfflineWindows' -Offline

            @($result.Requested) | Should -Be @('AppA','AppB')
            $result.Offline | Should -BeTrue
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter {
                @($Name).Count -eq 2 -and 'AppA' -in $Name -and 'AppB' -in $Name -and
                [bool]$SkipCacheRefresh -and $WindowsPath -eq 'C:\OfflineWindows'
            }
        }
    }

    It 'invokes built-in cmdlets and stages the repository batch after them' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDAppMicrosoftTeams {}
            Mock Add-OSDApp {}
            Mock Get-OSDAppUIStagedIds { 'MicrosoftTeams'; 'AppA' }

            $apps = @(
                [pscustomobject]@{ Id='MicrosoftTeams';Source='BuiltIn' },
                [pscustomobject]@{ Id='AppA';Source='Repository' }
            )
            Invoke-OSDAppUIStage -Applications $apps -WindowsPath 'C:\OfflineWindows' | Out-Null

            Should -Invoke Add-OSDAppMicrosoftTeams -Exactly 1
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter { @($Name).Count -eq 1 -and $Name[0] -eq 'AppA' }
        }
    }

    It 'rejects unsupported or duplicate application IDs before staging' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDApp {}
            $duplicate = @(
                [pscustomobject]@{ Id='AppA';Source='Repository' },
                [pscustomobject]@{ Id='appa';Source='Repository' }
            )
            { Invoke-OSDAppUIStage -Applications $duplicate -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*selected multiple times*'

            $traversal = @([pscustomobject]@{ Id='../escape'; Source='Repository' })
            { Invoke-OSDAppUIStage -Applications $traversal -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*Invalid application ID*'

            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'requires explicit -TestMode for staging on full Windows' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            Mock Add-OSDApp {}
            { Invoke-OSDAppUIStage -Applications @([pscustomobject]@{Id='AppA';Source='Repository'}) -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*requires -TestMode*'
            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'refuses a Windows 11 staging target outside the designated TEMP folder' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppUITestWindowsPath { 'C:\SafeUIStaging' }
            Mock Add-OSDApp {}
            { Invoke-OSDAppUIStage -Applications @([pscustomobject]@{Id='AppA';Source='Repository'}) -WindowsPath 'C:\' -TestMode } |
                Should -Throw '*only permitted under the isolated test target*'
            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'stages two apps to a safe Windows 11 test root when TestMode is explicit' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppUITestWindowsPath { 'C:\SafeUIStaging' }
            Mock Resolve-OSDAppWindowsPath { 'C:\SafeUIStaging' }
            Mock Add-OSDApp {}
            Mock Get-OSDAppUIStagedIds { 'AppA'; 'AppB' }
            $apps = @(
                [pscustomobject]@{ Id='AppA';Source='Repository' },
                [pscustomobject]@{ Id='AppB';Source='Repository' }
            )
            $result = Invoke-OSDAppUIStage -Applications $apps -WindowsPath 'C:\SafeUIStaging' -Offline -TestMode
            $result.WindowsPath | Should -Be 'C:\SafeUIStaging'
            $result.Staged.Count | Should -Be 2
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter {
                $WindowsPath -eq 'C:\SafeUIStaging' -and [bool]$SkipCacheRefresh
            }
        }
    }

    It 'reads an existing manifest queue without mutating it' {
        InModuleScope OSDApps {
            $windows = Join-Path $TestDrive 'WindowsDisk'
            $folder = Join-Path $windows 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $manifestPath = Join-Path $folder 'DeviceManifest.json'
            '{"Apps":[{"Id":"AppA"},{"Id":"MicrosoftTeams"}]}' |
                Set-Content -LiteralPath $manifestPath -Encoding UTF8

            @(Get-OSDAppUIStagedIds -WindowsPath $windows) | Should -Be @('AppA','MicrosoftTeams')
            (Get-Content -LiteralPath $manifestPath -Raw) | Should -Match '"MicrosoftTeams"'
        }
    }
    It 'creates DeviceManifest and SetupComplete in a real isolated Windows staging test root' {
        InModuleScope OSDApps {
            $testRoot = Join-Path $TestDrive 'OSDApps-GUI-Staging-Test'
            $cacheRoot = Join-Path $TestDrive 'Cache'
            $pkgDir = Join-Path $cacheRoot 'Packages\AppA'
            New-Item -ItemType Directory -Path $testRoot,$pkgDir -Force | Out-Null
            $archive = Join-Path $pkgDir 'Package.zip'
            Set-Content -LiteralPath $archive -Encoding ASCII -Value 'test repository payload'
            $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash

            @{
                SchemaVersion = 1
                Packages = @(
                    @{ Id='AppA'; DisplayName='App A'; Architecture='any'; Version='1.0'
                       Archive=@{ FileName='Package.zip'; Sha256=$hash }; SuccessCodes=@(0) }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8

            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppUITestWindowsPath { Join-Path $TestDrive 'OSDApps-GUI-Staging-Test' }
            Mock Get-OSDAppCachePath { Join-Path $TestDrive 'Cache' }

            $app = [pscustomobject]@{ Id='AppA';Source='Repository' }
            Invoke-OSDAppUIStage -Applications @($app) -WindowsPath $testRoot -TestMode -Offline | Out-Null
            Invoke-OSDAppUIStage -Applications @($app) -WindowsPath $testRoot -TestMode -Offline | Out-Null

            $stageDir = Join-Path $testRoot 'Windows\Temp\OSDApps'
            $manifestFile = Join-Path $stageDir 'DeviceManifest.json'
            $setupFile = Join-Path $testRoot 'Windows\Setup\Scripts\SetupComplete.cmd'
            $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 1
            @($manifest.Apps.Id) | Should -Be @('AppA')
            (Get-FileHash -LiteralPath (Join-Path $stageDir 'Packages\AppA\Package.zip') -Algorithm SHA256).Hash |
                Should -Be $hash
            $setup = Get-Content -LiteralPath $setupFile -Raw
            ([regex]::Matches($setup, '(?m)^:: OSDApps Begin\r?$')).Count | Should -Be 1
            ([regex]::Matches($setup, '(?m)^:: OSDApps End\r?$')).Count | Should -Be 1
        }
    }

}
