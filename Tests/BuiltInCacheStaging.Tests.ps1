BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Built-in cache staging aligns with DeviceManifest runtime paths' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'stages Adobe x64 at the exact manifest path and copies the original bytes' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'AdobeUsb'
            $windows = Join-Path $TestDrive 'AdobeWindows'
            $source = Join-Path $usb 'BuiltIn\AdobeAcrobatUnified\x64\Acrobat_DC_Web_x64_WWMUI.zip'
            New-Item -ItemType Directory -Path (Split-Path $source -Parent),$windows -Force | Out-Null
            Set-Content -LiteralPath $source -Value 'Adobe-x64-test-package' -Encoding Ascii
            Set-OSDStageTestPayloadInfo -Path $source -Id AdobeAcrobatUnified

            $result = Add-OSDStageAdobeAcrobatUnifiedInternal -CachePath $usb -WindowsPath $windows -Architecture x64 -PackageUri 'https://example.invalid/Adobe.zip' -Confirm:$false

            $stage = Join-Path $windows 'Windows\Temp\OSDStage'
            $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'AdobeAcrobatUnified')[0]
            $destination = Join-Path $stage $app.Package

            $app.Package | Should -Be 'BuiltIn\AdobeAcrobatUnified\x64\Acrobat_DC_Web_x64_WWMUI.zip'
            $app.CachePreferred | Should -BeTrue
            $result.CacheAvailable | Should -BeTrue
            $result.StagedPath | Should -Be (Split-Path $destination -Parent)
            (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            (Test-Path -LiteralPath (Join-Path $stage 'BuiltIn\AdobeAcrobatUnified\Acrobat_DC_Web_x64_WWMUI.zip')) | Should -BeFalse
        }
    }

    It 'stages both Adobe architectures independently without deleting the other variant' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'AdobeDualUsb'
            $windows = Join-Path $TestDrive 'AdobeDualWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            foreach ($arch in @('x86','x64')) {
                $source = Join-Path $usb "BuiltIn\AdobeAcrobatUnified\$arch\Acrobat_DC_Web_x64_WWMUI.zip"
                New-Item -ItemType Directory -Path (Split-Path $source -Parent) -Force | Out-Null
                Set-Content -LiteralPath $source -Value "Adobe-$arch-test-package" -Encoding Ascii
                Set-OSDStageTestPayloadInfo -Path $source -Id AdobeAcrobatUnified -Architecture $arch
                Add-OSDStageAdobeAcrobatUnifiedInternal -CachePath $usb -WindowsPath $windows -Architecture $arch -PackageUri 'https://example.invalid/Adobe.zip' -Confirm:$false | Out-Null

                $stage = Join-Path $windows 'Windows\Temp\OSDStage'
                $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
                $app = @($manifest.Packages | Where-Object Id -eq 'AdobeAcrobatUnified')[0]
                $app.Package | Should -Be "BuiltIn\AdobeAcrobatUnified\$arch\Acrobat_DC_Web_x64_WWMUI.zip"
                (Test-Path -LiteralPath (Join-Path $stage $app.Package) -PathType Leaf) | Should -BeTrue
            }
            foreach ($arch in @('x86','x64')) {
                $file = Join-Path $windows "Windows\Temp\OSDStage\BuiltIn\AdobeAcrobatUnified\$arch\Acrobat_DC_Web_x64_WWMUI.zip"
                (Test-Path -LiteralPath $file -PathType Leaf) | Should -BeTrue
                (Get-Content -LiteralPath $file -Raw) | Should -Match "Adobe-$arch-test-package"
            }
        }
    }

    It 'keeps the correct Adobe download intent when the USB cache is empty' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'AdobeEmptyWindows'
            $usb = Join-Path $TestDrive 'AdobeEmptyUsb'
            New-Item -ItemType Directory -Path $windows,$usb -Force | Out-Null
            $result = Add-OSDStageAdobeAcrobatUnifiedInternal -CachePath $usb -WindowsPath $windows -PackageUri 'https://example.invalid/Adobe.zip' -Confirm:$false
            $stage = Join-Path $windows 'Windows\Temp\OSDStage'
            $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'AdobeAcrobatUnified')[0]

            $result.CacheAvailable | Should -BeFalse
            $app.Package | Should -BeNullOrEmpty
            $app.PayloadRoot | Should -Be 'BuiltIn\AdobeAcrobatUnified\x64'
            $app.PayloadExtension | Should -Be '.zip'
            (Test-Path -LiteralPath (Join-Path $stage 'BuiltIn\AdobeAcrobatUnified\x64') -PathType Container) | Should -BeTrue
        }
    }

    It 'stages Chrome and Firefox MSI files at their manifest paths' {
        InModuleScope OSDStage {
            foreach ($case in @(
                @{ Id='GoogleChromeEnterprise'; Command='Add-OSDStageGoogleChromeEnterpriseInternal'; Relative='BuiltIn\GoogleChromeEnterprise\x64' },
                @{ Id='MozillaFirefoxEnterprise'; Command='Add-OSDStageMozillaFirefoxEnterpriseInternal'; Relative='BuiltIn\MozillaFirefoxEnterprise\Rapid\x64\en-US' }
            )) {
                $usb = Join-Path $TestDrive "$($case.Id)Usb"
                $windows = Join-Path $TestDrive "$($case.Id)Windows"
                $source = Join-Path $usb (Join-Path $case.Relative 'vendor-installer.msi')
                New-Item -ItemType Directory -Path (Split-Path $source -Parent),$windows -Force | Out-Null
                Set-Content -LiteralPath $source -Value $case.Id -Encoding Ascii
                Set-OSDStageTestPayloadInfo -Path $source -Id $case.Id
                $params = @{
                    CachePath = $usb
                    WindowsPath = $windows
                    PackageUri = 'https://example.invalid/vendor-installer.msi'
                    Architecture = 'x64'
                    Confirm = $false
                }
                & $case.Command @params | Out-Null

                $stage = Join-Path $windows 'Windows\Temp\OSDStage'
                $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
                $app = @($manifest.Packages | Where-Object Id -eq $case.Id)[0]
                $app.Package | Should -Be (Join-Path $case.Relative 'vendor-installer.msi')
                $destination = Join-Path $stage $app.Package
                (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
    }

    It 'stages Office and Teams cache files exactly where the runner expects them' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'MicrosoftUsb'
            $windows = Join-Path $TestDrive 'MicrosoftWindows'
            $office = Join-Path $usb 'BuiltIn\Microsoft365Apps'
            $teams = Join-Path $usb 'BuiltIn\MicrosoftTeams'
            $officeVersion = '16.0.20430.20146'
            $officeData = Join-Path $office 'Office\Data'
            $officeVersionRoot = Join-Path $officeData $officeVersion
            New-Item -ItemType Directory -Path $windows,$office,$teams,$officeVersionRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $office 'setup.exe') -Value 'setup' -Encoding Ascii
            New-OSDStageOfficeConfiguration -Path (Join-Path $office 'configuration.xml')
            $officeProfile = Get-OSDStageOfficePayloadProfile -Path (Join-Path $office 'configuration.xml')
            Set-Content -LiteralPath (Join-Path $officeVersionRoot 'stream.x64.x-none.dat') -Value 'payload' -Encoding Ascii
            Set-Content -LiteralPath (Join-Path $officeData 'v64.cab') -Value 'matching-cab' -Encoding Ascii
            Set-Content -LiteralPath (Join-Path $officeData "v64_$officeVersion.cab") -Value 'matching-cab' -Encoding Ascii
            [pscustomobject]@{
                Id = 'Microsoft365Apps'
                Version = $officeVersion
                Architecture = 'x64'
                PayloadProfile = $officeProfile
            } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $office 'CacheInfo.json') -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $teams 'MSTeams-x64.msix') -Value 'msix' -Encoding Ascii
            Set-OSDStageTestPayloadInfo -Path (Join-Path $teams 'MSTeams-x64.msix') -Id MicrosoftTeams
            Set-Content -LiteralPath (Join-Path $teams 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding Ascii
            Add-OSDStageMicrosoft365AppsInternal -CachePath $usb -WindowsPath $windows -Confirm:$false | Out-Null
            Add-OSDStageMicrosoftTeamsInternal -CachePath $usb -WindowsPath $windows -Confirm:$false | Out-Null

            $stage = Join-Path $windows 'Windows\Temp\OSDStage'
            $manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages).Count | Should -Be 2
            $officeApp = @($manifest.Packages | Where-Object Id -eq 'Microsoft365Apps')[0]
            $microsoftTeamsApp = @($manifest.Packages | Where-Object Id -eq 'MicrosoftTeams')[0]
            $microsoftTeamsApp.Type | Should -Be 'MicrosoftTeamsBootstrapper'
            $microsoftTeamsApp.Setup | Should -Be 'BuiltIn\MicrosoftTeams\teamsbootstrapper.exe'
            $microsoftTeamsApp.OfflinePackage | Should -Be 'BuiltIn\MicrosoftTeams\MSTeams-x64.msix'
            foreach ($path in @($officeApp.Setup,$officeApp.Configuration,$microsoftTeamsApp.Setup,$microsoftTeamsApp.OfflinePackage)) {
                (Test-Path -LiteralPath (Join-Path $stage $path) -PathType Leaf) | Should -BeTrue
            }
            (Test-Path -LiteralPath (Join-Path $stage 'BuiltIn\Microsoft365Apps\Office\Data') -PathType Container) | Should -BeTrue
        }
    }
}
