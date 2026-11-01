BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Cisco Webex built-in MSI integration' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force
        $script:metadata = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'metadata\builtins.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'exports the Add and Sync cmdlets with x64 default and only x64/arm64 values' {
        foreach ($name in @('Add-OSDStageCiscoWebex','Sync-OSDStageCiscoWebex')) {
            $cmd = Get-Command -Module OSDStage -Name $name
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Definition | Should -Match ([regex]::Escape('$Architecture') + "\s*=\s*'x64'")
            $validate = @($cmd.Parameters['Architecture'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            @($validate[0].ValidValues | Sort-Object) | Should -Be @('arm64','x64')
        }
    }

    It 'publishes metadata for the right commands, cache and brand icon' {
        $app = @($script:metadata.Packages | Where-Object Id -eq 'CiscoWebex')[0]
        $app.DisplayName | Should -Be 'Cisco Webex'
        $app.Vendor | Should -Be 'Cisco'
        $app.Acquisition | Should -Be 'VendorMsi'
        $app.SyncPhase | Should -Be 'FullWindowsPreInstall'
        $app.AddCommand | Should -Be 'Add-OSDStageCiscoWebex'
        $app.SyncCommand | Should -Be 'Sync-OSDStageCiscoWebex'
        $app.CachePath | Should -Be 'BuiltIn/CiscoWebex/<architecture>'
        $app.IconUrl | Should -Match '/metadata/icons/ciscowebex\.svg$'
        (Test-Path -LiteralPath (Join-Path $script:moduleRoot 'metadata\icons\ciscowebex.svg') -PathType Leaf) | Should -BeTrue
    }

    It 'uses the documented official Cisco non-localized MSI URLs' {
        foreach ($name in @('Add-OSDStageCiscoWebex','Sync-OSDStageCiscoWebex')) {
            $text = (Get-Command $name).Definition
            $text | Should -Match 'https://binaries\.webex\.com/WebexOfclDesktop-Win-64-Gold/Webex_en\.msi'
            $text | Should -Match 'https://binaries\.webex\.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en\.msi'
        }
    }

    It 'uses per-machine install, EULA acceptance and no autostart by default' {
        InModuleScope OSDStage {
            $properties = @(New-OSDStageCiscoWebexMsiProperties)
            $properties | Should -Contain 'ALLUSERS=1'
            $properties | Should -Contain 'ACCEPT_EULA=TRUE'
            $properties | Should -Contain 'AUTOSTART_WITH_WINDOWS=FALSE'
            $properties | Should -Not -Contain 'PREVENT_PRELOGIN_UPDATES=1'
            $properties | Should -Not -Contain 'ENABLEOUTLOOKINTEGRATION=0'
            $properties | Should -Not -Contain 'EMAIL=$userPrincipalName'
        }
    }

    It 'honors optional update, Outlook, theme, EULA and email hint properties' {
        InModuleScope OSDStage {
            $properties = @(New-OSDStageCiscoWebexMsiProperties -AutoStartWithWindows $true -AcceptEula $false -PreventPreLoginUpdates $true -EnableOutlookIntegration $true -DefaultTheme 'Light' -EmailHint '$userPrincipalName')
            $properties | Should -Contain 'ALLUSERS=1'
            $properties | Should -Not -Contain 'ACCEPT_EULA=TRUE'
            $properties | Should -Contain 'AUTOSTART_WITH_WINDOWS=TRUE'
            $properties | Should -Contain 'PREVENT_PRELOGIN_UPDATES=1'
            $properties | Should -Contain 'ENABLEOUTLOOKINTEGRATION=1'
            $properties | Should -Contain 'DEFAULT_THEME=Light'
            $properties | Should -Contain 'EMAIL=$userPrincipalName'
            @(New-OSDStageCiscoWebexMsiProperties -EnableOutlookIntegration $false) | Should -Contain 'ENABLEOUTLOOKINTEGRATION=0'
        }
    }

    It 'quotes legitimate additional MSI properties, and rejects reserved or malformed ones' {
        InModuleScope OSDStage {
            $properties = @(New-OSDStageCiscoWebexMsiProperties -AdditionalMsiProperties @('INSTALLWV2=1','INSTALL_ROOT=C:\Program Files\Cisco Spark'))
            $properties | Should -Contain 'INSTALLWV2=1'
            $properties | Should -Contain 'INSTALL_ROOT="C:\Program Files\Cisco Spark"'
            { New-OSDStageCiscoWebexMsiProperties -AdditionalMsiProperties 'ALLUSERS=2' } | Should -Throw '*reserved*'
            { New-OSDStageCiscoWebexMsiProperties -AdditionalMsiProperties @('INSTALLWV2=1','installwv2=0') } | Should -Throw '*Duplicate*'
            { New-OSDStageCiscoWebexMsiProperties -AdditionalMsiProperties 'broken' } | Should -Throw '*NAME=VALUE*'
            { New-OSDStageCiscoWebexMsiProperties -AdditionalMsiProperties 'INSTALL_ROOT="C:\Temp"' } | Should -Throw '*quote*'
        }
    }

    It 'does not hardcode one user identity in an all-users install' {
        InModuleScope OSDStage {
            { New-OSDStageCiscoWebexMsiProperties -EmailHint 'person@example.org' } | Should -Throw '*ALLUSERS*'
            foreach ($placeholder in @('$userPrincipalName','$mail','$SAMAccountName')) {
                @(New-OSDStageCiscoWebexMsiProperties -EmailHint $placeholder) | Should -Contain "EMAIL=$placeholder"
            }
        }
    }

    It 'allows the public Add cmdlet to stage defaults without optional theme or cached media' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'PublicAddWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            Mock Resolve-OSDStageWindowsPath { $WindowsPath }
            Mock Get-OSDStageCachePath { throw 'No USB cache' }
            Mock Add-OSDStageSetupComplete { }

            $result = Add-OSDStageCiscoWebex -WindowsPath $windows -Confirm:$false
            $manifestPath = Join-Path $windows 'Windows\Temp\OSDStage\DeviceManifest.json'
            (Test-Path -LiteralPath $manifestPath -PathType Leaf) | Should -BeTrue
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'CiscoWebex')[0]
            $result.Name | Should -Be 'CiscoWebex'
            $app.MsiProperties | Should -Contain 'AUTOSTART_WITH_WINDOWS=FALSE'
            $app.MsiProperties | Should -Contain 'ALLUSERS=1'
            $app.MsiProperties | Should -Not -Contain 'DEFAULT_THEME=Light'
            $app.MsiProperties | Should -Not -Contain 'ENABLEOUTLOOKINTEGRATION=0'
            Should -Invoke Add-OSDStageSetupComplete -Exactly -Times 1
        }
    }

    It 'copies real cached MSI bytes to exactly the x64 and arm64 manifest paths' {
        InModuleScope OSDStage {
            foreach ($arch in @('x64','arm64')) {
                $usb = Join-Path $TestDrive "$arch-Usb"
                $windows = Join-Path $TestDrive "$arch-Windows"
                $source = Join-Path $usb "BuiltIn\CiscoWebex\$arch\Webex_en.msi"
                New-Item -ItemType Directory -Path (Split-Path -Parent $source),$windows -Force | Out-Null
                Set-Content -LiteralPath $source -Value "Cisco Webex $arch MSI fixture" -Encoding Ascii
                Set-OSDStageTestPayloadInfo -Path $source -Id CiscoWebex -Architecture $arch

                $staged = Add-OSDStageCiscoWebexInternal -CachePath $usb -WindowsPath $windows -Architecture $arch -PackageUri 'https://example.invalid/Webex_en.msi' -PreventPreLoginUpdates $true -AdditionalMsiProperties 'INSTALLWV2=1' -Confirm:$false
                $stageRoot = Join-Path $windows 'Windows\Temp\OSDStage'
                $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $app = @($manifest.Packages | Where-Object Id -eq 'CiscoWebex')[0]
                $destination = Join-Path $stageRoot $app.Package

                $staged.Name | Should -Be 'CiscoWebex'
                $staged.CacheAvailable | Should -BeTrue
                $app.Type | Should -Be 'VendorMsi'
                $app.Package | Should -Be "BuiltIn\CiscoWebex\$arch\Webex_en.msi"
                $app.Architecture | Should -Be $arch
                $app.MsiProperties | Should -Contain 'ALLUSERS=1'
                $app.MsiProperties | Should -Contain 'INSTALLWV2=1'
                $app.MsiProperties | Should -Contain 'PREVENT_PRELOGIN_UPDATES=1'
                (Test-Path -LiteralPath $destination -PathType Leaf) | Should -BeTrue
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
    }

    It 'creates valid deployment intent without USB, for Windows acquisition at SetupComplete' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'NoUsbWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            $staged = Add-OSDStageCiscoWebexInternal -WindowsPath $windows -Architecture x64 -PackageUri 'https://example.invalid/Webex_en.msi' -Confirm:$false
            $stageRoot = Join-Path $windows 'Windows\Temp\OSDStage'
            $manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $app = @($manifest.Packages | Where-Object Id -eq 'CiscoWebex')[0]
            $staged.CacheAvailable | Should -BeFalse
            $app.CachePreferred | Should -BeFalse
            $app.Package | Should -BeNullOrEmpty
            $app.PayloadRoot.Replace('\','/') | Should -Be 'BuiltIn/CiscoWebex/x64'
            $app.PayloadExtension | Should -Be '.msi'
        }
    }

    It 'rejects invalid MSI properties before creating staging directories' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'RejectedWindows'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            { Add-OSDStageCiscoWebexInternal -WindowsPath $windows -PackageUri 'https://example.invalid/Webex_en.msi' -EmailHint 'oneuser@example.com' -Confirm:$false } | Should -Throw '*ALLUSERS*'
            (Test-Path -LiteralPath (Join-Path $windows 'Windows\Temp\OSDStage') -PathType Container) | Should -BeFalse
        }
    }

    It 'syncs and reuses Cisco MSI cache entries without re-downloading an unchanged ETag' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'SyncUsb'
            New-Item -ItemType Directory -Path $usb -Force | Out-Null

            Mock Test-OSDStageWinPE { $false }
            Mock Get-OSDStageCachePath { Join-Path $TestDrive 'SyncUsb' }
            Mock Assert-OSDStageCacheFreeSpace { }
            Mock Get-OSDStageRemoteFileMetadata {
                [pscustomobject]@{
                    ETag = '"webex-test-etag"'
                    LastModified = '2026-10-09T00:00:00Z'
                    ContentLength = 1024
                    FinalUri = 'https://binaries.webex.com/test/Webex_en.msi'
                }
            }
            Mock Save-OSDStageDownload {
                $path = Join-Path $DestinationDirectory 'Webex_en.msi'
                Set-Content -LiteralPath $path -Value 'Cisco Webex MSI fixture' -Encoding Ascii
                Get-Item -LiteralPath $path
            }
            # Synthetic MSI fixtures are not authenticode-signed. Trust policy
            # is exercised in TrustedPublisher.Tests.ps1 instead.
            Mock Assert-OSDStageBuiltInSignature {
                [pscustomobject]@{ Status='Valid'; PublisherMatches=$true }
            }

            $cold = Sync-OSDStageCiscoWebex -Architecture x64
            $warm = Sync-OSDStageCiscoWebex -Architecture x64
            $arm = Sync-OSDStageCiscoWebex -Architecture arm64

            $cold.Updated | Should -BeTrue
            $warm.Updated | Should -BeFalse
            $arm.Updated | Should -BeTrue
            $cold.CachePath | Should -Be (Join-Path $usb 'BuiltIn\CiscoWebex\x64')
            $arm.CachePath | Should -Be (Join-Path $usb 'BuiltIn\CiscoWebex\arm64')
            Should -Invoke Save-OSDStageDownload -Exactly -Times 2

            $entries = @(Get-OSDStageCache -Name 'CiscoWebex')
            $entries.Count | Should -Be 2
            @($entries | Where-Object Valid).Count | Should -Be 2
        }
    }

    It 'includes CiscoWebex in standalone offline PreInstall and the generic MSI Runner' {
        $preInstall = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStageRunner.ps1') -Raw
        $preInstall.Contains("'CiscoWebex' {") | Should -BeTrue
        $preInstall.Contains("Join-Path 'BuiltIn\CiscoWebex'") | Should -BeTrue
        $preInstall.Contains("Sync-PreInstallVendorMsi -App") | Should -BeTrue
        $runner.Contains("'VendorMsi' {") | Should -BeTrue
        $runner.Contains('MsiProperties') | Should -BeTrue
    }
}
