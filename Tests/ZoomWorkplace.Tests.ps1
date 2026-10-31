BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Zoom Workplace built-in MSI integration' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force
        $script:metadata = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'metadata\builtins.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'exports the Add and Sync cmdlets with x64 default and only x64/arm64 values' {
        foreach ($name in @('Add-OSDStageZoomWorkplace','Sync-OSDStageZoomWorkplace')) {
            $cmd = Get-Command -Module OSDStage -Name $name
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Definition | Should -Match ([regex]::Escape('$Architecture') + "\s*=\s*'x64'")
            $validate = @($cmd.Parameters['Architecture'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            @($validate[0].ValidValues | Sort-Object) | Should -Be @('arm64','x64')
        }
    }

    It 'publishes metadata for the right commands, cache and brand icon' {
        $app = @($script:metadata.Packages | Where-Object Id -eq 'ZoomWorkplace')[0]
        $app.DisplayName | Should -Be 'Zoom Workplace'
        $app.Vendor | Should -Be 'Zoom'
        $app.Acquisition | Should -Be 'VendorMsi'
        $app.SyncPhase | Should -Be 'FullWindowsPreInstall'
        $app.AddCommand | Should -Be 'Add-OSDStageZoomWorkplace'
        $app.SyncCommand | Should -Be 'Sync-OSDStageZoomWorkplace'
        $app.CachePath | Should -Be 'BuiltIn/ZoomWorkplace/<architecture>'
        $app.IconUrl | Should -Match '/metadata/icons/zoom\.svg$'
        (Test-Path -LiteralPath (Join-Path $script:moduleRoot 'metadata\icons\zoom.svg') -PathType Leaf) | Should -BeTrue
    }

    It 'discovers the host Zoom cache and redirects generic Add to its built-in command' {
        InModuleScope OSDStage {
            $script:ZoomDiscoveryCache = Join-Path $TestDrive 'Discovery'
            $entry = Join-Path $script:ZoomDiscoveryCache 'BuiltIn/ZoomWorkplace/arm64'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            '{"Version":"7.2.1","Architecture":"arm64"}' | Set-Content -LiteralPath (Join-Path $entry 'CacheInfo.json')
            Mock Get-OSDStageCachePath { $script:ZoomDiscoveryCache }
            Mock Get-OSDStageHostArchitecture { 'arm64' }
            $app = @(Get-OSDStage -Offline | Where-Object Id -eq 'ZoomWorkplace')
            $app.Count | Should -Be 1
            $app[0].Availability | Should -Be 'Cached'
            $app[0].CachedVersion | Should -Be '7.2.1'
            $app[0].Architecture | Should -Be 'arm64'
            { Add-OSDStage -Name ZoomWorkplace } | Should -Throw '*Use Add-OSDStageZoomWorkplace instead*'
        }
    }

    It 'allows the public Add cmdlet to stage defaults without cached media' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'PublicAddWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            Mock Resolve-OSDStageWindowsPath { $WindowsPath }
            Mock Get-OSDStageCachePath { throw 'No USB cache' }
            Mock Add-OSDStageSetupComplete { }

            $result = Add-OSDStageZoomWorkplace -WindowsPath $windows -Confirm:$false
            $manifestPath = Join-Path $windows 'Windows\Temp\OSDStage\DeviceManifest.json'
            (Test-Path -LiteralPath $manifestPath -PathType Leaf) | Should -BeTrue
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'ZoomWorkplace')[0]
            $result.Name | Should -Be 'ZoomWorkplace'
            @($app.MsiProperties) | Should -Be @('ALLUSERS=1')
            Should -Invoke Add-OSDStageSetupComplete -Exactly -Times 1
        }
    }

    It 'copies real cached MSI bytes to exactly the x64 and arm64 manifest paths' {
        InModuleScope OSDStage {
            foreach ($arch in @('x64','arm64')) {
                $usb = Join-Path $TestDrive "$arch-Usb"
                $windows = Join-Path $TestDrive "$arch-Windows"
                $source = Join-Path $usb "BuiltIn\ZoomWorkplace\$arch\ZoomInstallerFull.msi"
                New-Item -ItemType Directory -Path (Split-Path -Parent $source),$windows -Force | Out-Null
                Set-Content -LiteralPath $source -Value "Zoom Workplace $arch MSI fixture" -Encoding Ascii
                Set-OSDStageTestPayloadInfo -Path $source -Id ZoomWorkplace -Architecture $arch

                $staged = Add-OSDStageZoomWorkplaceInternal -CachePath $usb -WindowsPath $windows -Architecture $arch -PackageUri 'https://example.invalid/ZoomInstallerFull.msi' -NoDesktopShortcut -Confirm:$false
                $stageRoot = Join-Path $windows 'Windows\Temp\OSDStage'
                $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $app = @($manifest.Packages | Where-Object Id -eq 'ZoomWorkplace')[0]
                $destination = Join-Path $stageRoot $app.Package

                $staged.Name | Should -Be 'ZoomWorkplace'
                $staged.CacheAvailable | Should -BeTrue
                $app.Type | Should -Be 'VendorMsi'
                $app.Package.Replace('\','/') | Should -Be "BuiltIn/ZoomWorkplace/$arch/ZoomInstallerFull.msi"
                $app.Architecture | Should -Be $arch
                $app.MsiProperties | Should -Contain 'ALLUSERS=1'
                $app.MsiProperties | Should -Contain 'zNoDesktopShortCut=True'
                (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
    }

    It 'creates valid deployment intent without USB, for Windows acquisition at SetupComplete' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'NoUsbWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            $staged = Add-OSDStageZoomWorkplaceInternal -WindowsPath $windows -Architecture x64 -PackageUri 'https://example.invalid/ZoomInstallerFull.msi' -Confirm:$false
            $stageRoot = Join-Path $windows 'Windows\Temp\OSDStage'
            $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'ZoomWorkplace')[0]
            $staged.CacheAvailable | Should -BeFalse
            $app.CachePreferred | Should -BeFalse
            $app.Package | Should -BeNullOrEmpty
            $app.PayloadRoot.Replace('\','/') | Should -Be 'BuiltIn/ZoomWorkplace/x64'
            $app.PayloadExtension | Should -Be '.msi'
        }
    }

    It 'syncs and reuses Zoom MSI cache entries without re-downloading an unchanged ETag' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'SyncUsb'
            New-Item -ItemType Directory -Path $usb -Force | Out-Null

            Mock Test-OSDStageWinPE { $false }
            Mock Get-OSDStageCachePath { Join-Path $TestDrive 'SyncUsb' }
            Mock Assert-OSDStageCacheFreeSpace { }
            Mock Get-OSDStageRemoteFileMetadata {
                [pscustomobject]@{
                    ETag = '"zoom-test-etag"'
                    LastModified = '2026-10-09T00:00:00Z'
                    ContentLength = 1024
                    FinalUri = 'https://example.invalid/ZoomInstallerFull.msi'
                }
            }
            Mock Save-OSDStageDownload {
                $path = Join-Path $DestinationDirectory 'ZoomInstallerFull.msi'
                Set-Content -LiteralPath $path -Value 'Zoom Workplace MSI fixture' -Encoding Ascii
                Get-Item -LiteralPath $path
            }
            # Synthetic MSI fixtures are not authenticode-signed. Trust policy
            # is exercised in TrustedPublisher.Tests.ps1 instead.
            Mock Assert-OSDStageBuiltInSignature {
                [pscustomobject]@{ Status='Valid'; PublisherMatches=$true }
            }

            $cold = Sync-OSDStageZoomWorkplace -Architecture x64
            $warm = Sync-OSDStageZoomWorkplace -Architecture x64
            $arm = Sync-OSDStageZoomWorkplace -Architecture arm64

            $cold.Updated | Should -BeTrue
            $warm.Updated | Should -BeFalse
            $arm.Updated | Should -BeTrue
            $cold.CachePath | Should -Be (Join-Path $usb 'BuiltIn\ZoomWorkplace\x64')
            $arm.CachePath | Should -Be (Join-Path $usb 'BuiltIn\ZoomWorkplace\arm64')
            Should -Invoke Save-OSDStageDownload -Exactly -Times 2

            $entries = @(Get-OSDStageCache -Name 'ZoomWorkplace')
            $entries.Count | Should -Be 2
            @($entries | Where-Object Valid).Count | Should -Be 2
        }
    }

    It 'includes ZoomWorkplace in standalone offline PreInstall and the generic MSI Runner' {
        $preInstall = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStageRunner.ps1') -Raw
        $preInstall.Contains("'ZoomWorkplace' {") | Should -BeTrue
        $preInstall.Contains("Join-Path 'BuiltIn\ZoomWorkplace'") | Should -BeTrue
        $preInstall.Contains("Sync-PreInstallVendorMsi -App") | Should -BeTrue
        $runner.Contains("'VendorMsi' {") | Should -BeTrue
        $runner.Contains('MsiProperties') | Should -BeTrue
    }
}

Describe 'Zoom configuration and publisher boundaries' {
    BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force }
    It 'serializes optional settings deterministically and preserves casing and defaults' {
        InModuleScope OSDStage {
            @(New-OSDStageZoomWorkplaceMsiProperties) | Should -Be @('ALLUSERS=1')
            $p = @(New-OSDStageZoomWorkplaceMsiProperties -NoDesktopShortcut -SsoHost example.zoom.us -ZConfig @{ DisableZoomOnboarding=$true; AutoStartAfterReboot=$false } -ZRecommend @{ AudioAutoAdjust=1 })
            $p | Should -Be @('ALLUSERS=1','zNoDesktopShortCut=True','zSSOHost="example.zoom.us"','ZConfig="AutoStartAfterReboot=0;DisableZoomOnboarding=1"','ZRecommend="AudioAutoAdjust=1"')
        }
    }
    It 'rejects unsafe, unsupported types and deprecated settings before staging writes' {
        InModuleScope OSDStage {
            foreach ($value in @('x" ALLUSERS=2','a;b',"a`nb",'ends\','',@('a','b'),$null)) {
                { New-OSDStageZoomWorkplaceMsiProperties -ZConfig @{ Setting=$value } } | Should -Throw
            }
            { New-OSDStageZoomWorkplaceMsiProperties -ZConfig @{ 'bad key'=1 } } | Should -Throw
            { New-OSDStageZoomWorkplaceMsiProperties -ZRecommend @{ ZoomAutoUpdate=1 } } | Should -Throw '*no longer supports*'
            { New-OSDStageZoomWorkplaceMsiProperties -SsoHost 'https://example.zoom.us/' } | Should -Throw '*vanity host*'
            $target = Join-Path $TestDrive 'InvalidZoom'
            { Add-OSDStageZoomWorkplaceInternal -WindowsPath $target -PackageUri https://example.invalid/zoom.msi -ZConfig @{ Setting='a;b' } } | Should -Throw
            Test-Path $target | Should -BeFalse
        }
    }
    It 'honors public WhatIf without writing a manifest or SetupComplete' {
        InModuleScope OSDStage {
            $target = Join-Path $TestDrive 'WhatIfZoom'
            Mock Resolve-OSDStageWindowsPath { $WindowsPath }
            Mock Get-OSDStageCachePath { throw 'No USB cache' }
            Mock Add-OSDStageSetupComplete { throw 'Must not run' }
            Add-OSDStageZoomWorkplace -WindowsPath $target -WhatIf
            Test-Path $target | Should -BeFalse
            Should -Invoke Add-OSDStageSetupComplete -Times 0 -Exactly
        }
    }
    It 'updates one queue entry when settings change without modifying cached bytes' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'ZoomCache'
            $windows = Join-Path $TestDrive 'ZoomWindows'
            $file = Join-Path $cache 'BuiltIn\ZoomWorkplace\x64\ZoomInstallerFull.msi'
            New-Item (Split-Path $file -Parent) -ItemType Directory -Force | Out-Null
            Set-Content $file -Value 'immutable fixture'
            $hash = (Get-FileHash $file).Hash
            Add-OSDStageZoomWorkplaceInternal -CachePath $cache -WindowsPath $windows -PackageUri https://example.invalid/zoom.msi | Out-Null
            Add-OSDStageZoomWorkplaceInternal -CachePath $cache -WindowsPath $windows -PackageUri https://example.invalid/zoom.msi -NoDesktopShortcut -ZConfig @{ DisableZoomOnboarding=1 } | Out-Null
            $manifest = Get-Content (Join-Path $windows 'Windows\Temp\OSDStage\DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages).Count | Should -Be 1
            $manifest.Packages[0].MsiProperties | Should -Contain 'ZConfig="DisableZoomOnboarding=1"'
            (Get-FileHash $file).Hash | Should -Be $hash
        }
    }
    It 'accepts the observed Zoom organization and rejects look-alike publishers' {
        InModuleScope OSDStage {
            Test-OSDStageExpectedPublisher -Id ZoomWorkplace -SignerSubject 'CN="Zoom Communications, Inc.", O="Zoom Communications, Inc.", C=US' | Should -BeTrue
            Test-OSDStageExpectedPublisher -Id ZoomWorkplace -SignerSubject 'CN="Zoom Communications, Inc.", O=Someone Else, C=US' | Should -BeFalse
        }
    }
}
