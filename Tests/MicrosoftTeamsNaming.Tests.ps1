BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'MicrosoftTeams canonical naming' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:moduleRoot 'OSDApps.psd1') -Force
        $script:metadata = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'metadata\builtins.json') -Raw | ConvertFrom-Json
    }

    It 'exports the new public command names and no old Teams commands' {
        $exports = @(Get-Command -Module OSDApps -CommandType Function | Select-Object -ExpandProperty Name)
        $exports | Should -Contain 'Add-OSDAppMicrosoftTeams'
        $exports | Should -Contain 'Sync-OSDAppMicrosoftTeams'
        $exports | Should -Not -Contain 'Add-OSDAppTeams'
        $exports | Should -Not -Contain 'Sync-OSDAppTeams'
    }

    It 'publishes only the canonical MicrosoftTeams identity' {
        $ids = @($script:metadata.Apps.Id)
        $ids | Should -Contain 'MicrosoftTeams'
        $ids | Should -Not -Contain 'Teams'
        $app = @($script:metadata.Apps | Where-Object Id -eq 'MicrosoftTeams')[0]
        $app.DisplayName | Should -Be 'Microsoft Teams'
        $app.AddCommand | Should -Be 'Add-OSDAppMicrosoftTeams'
        $app.SyncCommand | Should -Be 'Sync-OSDAppMicrosoftTeams'
        $app.Acquisition | Should -Be 'MicrosoftTeamsBootstrapper'
        $app.CachePath | Should -Be 'BuiltIn/MicrosoftTeams'
        $app.PSObject.Properties.Name | Should -Not -Contain 'Aliases'
        $app.IconUrl | Should -Match '/metadata/icons/microsoftteams\.svg$'
        (Test-Path -LiteralPath (Join-Path $script:moduleRoot 'metadata\icons\microsoftteams.svg') -PathType Leaf) | Should -BeTrue
    }

    It 'copies an existing MicrosoftTeams USB cache to its exact manifest paths' {
        InModuleScope OSDApps {
            $usb = Join-Path $TestDrive 'TeamsUsb'
            $windows = Join-Path $TestDrive 'TeamsWindows'
            $sourceRoot = Join-Path $usb 'BuiltIn\MicrosoftTeams'
            New-Item -ItemType Directory -Path $windows,$sourceRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sourceRoot 'teamsbootstrapper.exe') -Value 'bootstrapper fixture' -Encoding Ascii
            Set-Content -LiteralPath (Join-Path $sourceRoot 'MSTeams-x64.msix') -Value 'msix fixture' -Encoding Ascii
            Set-OSDAppsTestPayloadInfo -Path (Join-Path $sourceRoot 'MSTeams-x64.msix') -Id MicrosoftTeams

            $result = Add-OSDAppMicrosoftTeamsInternal -CachePath $usb -WindowsPath $windows -Architecture x64 -Confirm:$false
            $stage = Join-Path $windows 'Windows\Temp\OSDApps'
            $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Apps | Where-Object Id -eq 'MicrosoftTeams')[0]

            $result.CacheAvailable | Should -BeTrue
            $result.Name | Should -Be 'MicrosoftTeams'
            $result.StagedPath | Should -Be (Join-Path $stage 'BuiltIn\MicrosoftTeams')
            $app.Type | Should -Be 'MicrosoftTeamsBootstrapper'
            $app.Setup | Should -Be 'BuiltIn\MicrosoftTeams\teamsbootstrapper.exe'
            $app.OfflinePackage | Should -Be 'BuiltIn\MicrosoftTeams\MSTeams-x64.msix'
            foreach ($filename in @('teamsbootstrapper.exe','MSTeams-x64.msix')) {
                $source = Join-Path $sourceRoot $filename
                $destination = Join-Path $result.StagedPath $filename
                (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
            (Test-Path -LiteralPath (Join-Path $stage 'BuiltIn\Teams') -PathType Container) | Should -BeFalse
        }
    }

    It 'recognizes and validates the new built-in CacheInfo identity' {
        InModuleScope OSDApps {
            $usb = Join-Path $TestDrive 'CacheUsb'
            $folder = Join-Path $usb 'BuiltIn\MicrosoftTeams'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $folder 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding Ascii
            Set-Content -LiteralPath (Join-Path $folder 'MSTeams-x64.msix') -Value 'msix' -Encoding Ascii
            @{Id='MicrosoftTeams';Version='1.2.3.4';Architecture='x64';SyncedAt='2026-10-09T00:00:00Z'} |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'CacheInfo.json') -Encoding UTF8

            Set-OSDAppsTestPayloadInfo -Path (Join-Path $folder 'MSTeams-x64.msix') -Id MicrosoftTeams -Metadata @{Version='1.2.3.4';SyncedAt='2026-10-09T00:00:00Z'}
            Mock Get-OSDAppCachePath { Join-Path $TestDrive 'CacheUsb' }
            $entries = @(Get-OSDAppCache -Name 'MicrosoftTeams')
            $entries.Count | Should -Be 1
            $entries[0].Id | Should -Be 'MicrosoftTeams'
            $entries[0].Valid | Should -BeTrue
            $entries[0].CachePath | Should -Be $folder
        }
    }

    It 'uses only the new ID, type and paths in standalone runtime dispatch' {
        $preinstall = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1') -Raw

        $preinstall.Contains("'MicrosoftTeams' {") | Should -BeTrue
        $preinstall.Contains('BuiltIn\MicrosoftTeams') | Should -BeTrue
        $preinstall.Contains("'Teams' {") | Should -BeFalse
        $preinstall.Contains('function Remove-LegacyMicrosoftTeamsCache') | Should -BeFalse
        $preinstall.Contains('BuiltIn\Teams') | Should -BeFalse
        $runner.Contains("'MicrosoftTeamsBootstrapper' {") | Should -BeTrue
        $runner.Contains("'TeamsBootstrapper' {") | Should -BeFalse
        $runner.Contains('BuiltIn\Teams') | Should -BeFalse
    }
}
