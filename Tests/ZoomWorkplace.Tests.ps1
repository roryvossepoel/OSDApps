Describe 'Zoom Workplace built-in MSI integration' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:moduleRoot 'OSDApps.psd1') -Force
        $script:metadata = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'metadata\builtins.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'exports the Add and Sync cmdlets with x64 default and only x64/arm64 values' {
        foreach ($name in @('Add-OSDAppZoomWorkplace','Sync-OSDAppZoomWorkplace')) {
            $cmd = Get-Command -Module OSDApps -Name $name
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Definition | Should -Match ([regex]::Escape('$Architecture') + "\s*=\s*'x64'")
            $validate = @($cmd.Parameters['Architecture'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            @($validate[0].ValidValues | Sort-Object) | Should -Be @('arm64','x64')
        }
    }

    It 'publishes metadata for the right commands, cache and brand icon' {
        $app = @($script:metadata.Apps | Where-Object Id -eq 'ZoomWorkplace')[0]
        $app.DisplayName | Should -Be 'Zoom Workplace'
        $app.Vendor | Should -Be 'Zoom'
        $app.Acquisition | Should -Be 'VendorMsi'
        $app.SyncPhase | Should -Be 'FullWindowsPreInstall'
        $app.AddCommand | Should -Be 'Add-OSDAppZoomWorkplace'
        $app.SyncCommand | Should -Be 'Sync-OSDAppZoomWorkplace'
        $app.CachePath | Should -Be 'BuiltIn/ZoomWorkplace/<architecture>'
        $app.IconUrl | Should -Match '/metadata/icons/zoom\.svg$'
        (Test-Path -LiteralPath (Join-Path $script:moduleRoot 'metadata\icons\zoom.svg') -PathType Leaf) | Should -BeTrue
    }

    It 'discovers the host Zoom cache and redirects generic Add to its built-in command' {
        InModuleScope OSDApps {
            $script:ZoomDiscoveryCache = Join-Path $TestDrive 'Discovery'
            $entry = Join-Path $script:ZoomDiscoveryCache 'BuiltIn/ZoomWorkplace/arm64'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            '{"Version":"7.2.1","Architecture":"arm64"}' | Set-Content -LiteralPath (Join-Path $entry 'CacheInfo.json')
            Mock Get-OSDAppCachePath { $script:ZoomDiscoveryCache }
            Mock Get-OSDAppHostArchitecture { 'arm64' }
            $app = @(Get-OSDApp -Offline | Where-Object Id -eq 'ZoomWorkplace')
            $app.Count | Should -Be 1
            $app[0].Availability | Should -Be 'Cached'
            $app[0].CachedVersion | Should -Be '7.2.1'
            $app[0].Architecture | Should -Be 'arm64'
            { Add-OSDApp -Name ZoomWorkplace } | Should -Throw '*Use Add-OSDAppZoomWorkplace instead*'
        }
    }

    It 'allows the public Add cmdlet to stage defaults without cached media' {
        InModuleScope OSDApps {
            $windows = Join-Path $TestDrive 'PublicAddWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No USB cache' }
            Mock Add-OSDAppSetupComplete { }

            $result = Add-OSDAppZoomWorkplace -WindowsPath $windows -Confirm:$false
            $manifestPath = Join-Path $windows 'Windows\Temp\OSDApps\DeviceManifest.json'
            (Test-Path -LiteralPath $manifestPath -PathType Leaf) | Should -BeTrue
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $app = @($manifest.Apps | Where-Object Id -eq 'ZoomWorkplace')[0]
            $result.Name | Should -Be 'ZoomWorkplace'
            @($app.MsiProperties) | Should -Be @('ALLUSERS=1')
            Should -Invoke Add-OSDAppSetupComplete -Exactly -Times 1
        }
    }

    It 'copies real cached MSI bytes to exactly the x64 and arm64 manifest paths' {
        InModuleScope OSDApps {
            foreach ($arch in @('x64','arm64')) {
                $usb = Join-Path $TestDrive "$arch-Usb"
                $windows = Join-Path $TestDrive "$arch-Windows"
                $source = Join-Path $usb "BuiltIn\ZoomWorkplace\$arch\Package.msi"
                New-Item -ItemType Directory -Path (Split-Path -Parent $source),$windows -Force | Out-Null
                Set-Content -LiteralPath $source -Value "Zoom Workplace $arch MSI fixture" -Encoding Ascii

                $staged = Add-OSDAppZoomWorkplaceInternal -CachePath $usb -WindowsPath $windows -Architecture $arch -PackageUri 'https://example.invalid/ZoomInstallerFull.msi' -NoDesktopShortcut -Confirm:$false
                $stageRoot = Join-Path $windows 'Windows\Temp\OSDApps'
                $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $app = @($manifest.Apps | Where-Object Id -eq 'ZoomWorkplace')[0]
                $destination = Join-Path $stageRoot $app.Package

                $staged.Name | Should -Be 'ZoomWorkplace'
                $staged.CacheAvailable | Should -BeTrue
                $app.Type | Should -Be 'VendorMsi'
                $app.Package.Replace('\','/') | Should -Be "BuiltIn/ZoomWorkplace/$arch/Package.msi"
                $app.Architecture | Should -Be $arch
                $app.MsiProperties | Should -Contain 'ALLUSERS=1'
                $app.MsiProperties | Should -Contain 'zNoDesktopShortCut=True'
                (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
    }

    It 'creates valid deployment intent without USB, for Windows acquisition at SetupComplete' {
        InModuleScope OSDApps {
            $windows = Join-Path $TestDrive 'NoUsbWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            $staged = Add-OSDAppZoomWorkplaceInternal -WindowsPath $windows -Architecture x64 -PackageUri 'https://example.invalid/ZoomInstallerFull.msi' -Confirm:$false
            $stageRoot = Join-Path $windows 'Windows\Temp\OSDApps'
            $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Apps | Where-Object Id -eq 'ZoomWorkplace')[0]
            $staged.CacheAvailable | Should -BeFalse
            $app.CachePreferred | Should -BeFalse
            $app.Package.Replace('\','/') | Should -Be 'BuiltIn/ZoomWorkplace/x64/Package.msi'
            (Test-Path -LiteralPath (Join-Path $stageRoot $app.Package) -PathType Leaf) | Should -BeFalse
        }
    }

    It 'syncs and reuses Zoom MSI cache entries without re-downloading an unchanged ETag' {
        InModuleScope OSDApps {
            $usb = Join-Path $TestDrive 'SyncUsb'
            New-Item -ItemType Directory -Path $usb -Force | Out-Null

            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { Join-Path $TestDrive 'SyncUsb' }
            Mock Assert-OSDAppCacheFreeSpace { }
            Mock Get-OSDAppRemoteFileMetadata {
                [pscustomobject]@{
                    ETag = '"zoom-test-etag"'
                    LastModified = '2026-10-09T00:00:00Z'
                    ContentLength = 1024
                    FinalUri = 'https://example.invalid/ZoomInstallerFull.msi'
                }
            }
            Mock Save-OSDAppDownload {
                Set-Content -LiteralPath $DestinationPath -Value 'Zoom Workplace MSI fixture' -Encoding Ascii
            }
            # Synthetic MSI fixtures are not authenticode-signed. Trust policy
            # is exercised in TrustedPublisher.Tests.ps1 instead.
            Mock Assert-OSDAppBuiltInSignature {
                [pscustomobject]@{ Status='Valid'; PublisherMatches=$true }
            }

            $cold = Sync-OSDAppZoomWorkplace -Architecture x64
            $warm = Sync-OSDAppZoomWorkplace -Architecture x64
            $arm = Sync-OSDAppZoomWorkplace -Architecture arm64

            $cold.Updated | Should -BeTrue
            $warm.Updated | Should -BeFalse
            $arm.Updated | Should -BeTrue
            $cold.CachePath | Should -Be (Join-Path $usb 'BuiltIn\ZoomWorkplace\x64')
            $arm.CachePath | Should -Be (Join-Path $usb 'BuiltIn\ZoomWorkplace\arm64')
            Should -Invoke Save-OSDAppDownload -Exactly -Times 2

            $entries = @(Get-OSDAppCache -Name 'ZoomWorkplace')
            $entries.Count | Should -Be 2
            @($entries | Where-Object Valid).Count | Should -Be 2
        }
    }

    It 'includes ZoomWorkplace in standalone offline PreInstall and the generic MSI Runner' {
        $preInstall = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1') -Raw
        $preInstall.Contains("'ZoomWorkplace' {") | Should -BeTrue
        $preInstall.Contains("Join-Path 'BuiltIn\ZoomWorkplace'") | Should -BeTrue
        $preInstall.Contains("Sync-PreInstallVendorMsi -App") | Should -BeTrue
        $runner.Contains("'VendorMsi' {") | Should -BeTrue
        $runner.Contains('MsiProperties') | Should -BeTrue
    }
}

Describe 'Zoom configuration and publisher boundaries' {
    BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force }
    It 'serializes optional settings deterministically and preserves casing and defaults' {
        InModuleScope OSDApps {
            @(New-OSDAppZoomWorkplaceMsiProperties) | Should -Be @('ALLUSERS=1')
            $p = @(New-OSDAppZoomWorkplaceMsiProperties -NoDesktopShortcut -SsoHost example.zoom.us -ZConfig @{ DisableZoomOnboarding=$true; AutoStartAfterReboot=$false } -ZRecommend @{ AudioAutoAdjust=1 })
            $p | Should -Be @('ALLUSERS=1','zNoDesktopShortCut=True','zSSOHost="example.zoom.us"','ZConfig="AutoStartAfterReboot=0;DisableZoomOnboarding=1"','ZRecommend="AudioAutoAdjust=1"')
        }
    }
    It 'rejects unsafe, unsupported types and deprecated settings before staging writes' {
        InModuleScope OSDApps {
            foreach ($value in @('x" ALLUSERS=2','a;b',"a`nb",'ends\','',@('a','b'),$null)) {
                { New-OSDAppZoomWorkplaceMsiProperties -ZConfig @{ Setting=$value } } | Should -Throw
            }
            { New-OSDAppZoomWorkplaceMsiProperties -ZConfig @{ 'bad key'=1 } } | Should -Throw
            { New-OSDAppZoomWorkplaceMsiProperties -ZRecommend @{ ZoomAutoUpdate=1 } } | Should -Throw '*no longer supports*'
            { New-OSDAppZoomWorkplaceMsiProperties -SsoHost 'https://example.zoom.us/' } | Should -Throw '*vanity host*'
            $target = Join-Path $TestDrive 'InvalidZoom'
            { Add-OSDAppZoomWorkplaceInternal -WindowsPath $target -PackageUri https://example.invalid/zoom.msi -ZConfig @{ Setting='a;b' } } | Should -Throw
            Test-Path $target | Should -BeFalse
        }
    }
    It 'honors public WhatIf without writing a manifest or SetupComplete' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'WhatIfZoom'
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No USB cache' }
            Mock Add-OSDAppSetupComplete { throw 'Must not run' }
            Add-OSDAppZoomWorkplace -WindowsPath $target -WhatIf
            Test-Path $target | Should -BeFalse
            Should -Invoke Add-OSDAppSetupComplete -Times 0 -Exactly
        }
    }
    It 'updates one queue entry when settings change without modifying cached bytes' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'ZoomCache'
            $windows = Join-Path $TestDrive 'ZoomWindows'
            $file = Join-Path $cache 'BuiltIn\ZoomWorkplace\x64\Package.msi'
            New-Item (Split-Path $file -Parent) -ItemType Directory -Force | Out-Null
            Set-Content $file -Value 'immutable fixture'
            $hash = (Get-FileHash $file).Hash
            Add-OSDAppZoomWorkplaceInternal -CachePath $cache -WindowsPath $windows -PackageUri https://example.invalid/zoom.msi | Out-Null
            Add-OSDAppZoomWorkplaceInternal -CachePath $cache -WindowsPath $windows -PackageUri https://example.invalid/zoom.msi -NoDesktopShortcut -ZConfig @{ DisableZoomOnboarding=1 } | Out-Null
            $manifest = Get-Content (Join-Path $windows 'Windows\Temp\OSDApps\DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 1
            $manifest.Apps[0].MsiProperties | Should -Contain 'ZConfig="DisableZoomOnboarding=1"'
            (Get-FileHash $file).Hash | Should -Be $hash
        }
    }
    It 'accepts the observed Zoom organization and rejects look-alike publishers' {
        InModuleScope OSDApps {
            Test-OSDAppExpectedPublisher -Id ZoomWorkplace -SignerSubject 'CN="Zoom Communications, Inc.", O="Zoom Communications, Inc.", C=US' | Should -BeTrue
            Test-OSDAppExpectedPublisher -Id ZoomWorkplace -SignerSubject 'CN="Zoom Communications, Inc.", O=Someone Else, C=US' | Should -BeFalse
        }
    }
}
