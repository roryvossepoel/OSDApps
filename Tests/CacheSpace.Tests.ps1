Describe 'Cache transaction space budgets' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force
    }

    It 'allows a candidate without budgeting the already occupied old generation twice' {
        InModuleScope OSDApps {
            Mock Get-OSDAppAvailableDiskBytes { 150MB }
            $result = Assert-OSDAppTransactionSpace -Path $TestDrive -ExpectedBytes 64MB -Operation test
            $result.RequiredBytes | Should -Be ([math]::Ceiling(64MB * 1.2) + 64MB)
        }
    }

    It 'accounts for growth beyond the public minimum' {
        InModuleScope OSDApps {
            Mock Get-OSDAppAvailableDiskBytes { 2GB }
            { Assert-OSDAppTransactionSpace -Path $TestDrive -ExpectedBytes 3GB -MinimumFreeSpaceGB 1 -Operation test } |
                Should -Throw '*Insufficient free space*'
        }
    }

    It 'uses the old generation as an estimate when the remote length is unknown' {
        InModuleScope OSDApps {
            Mock Get-OSDAppAvailableDiskBytes { 10GB }
            Mock Get-OSDAppPathSize { 5GB }
            $result = Assert-OSDAppTransactionSpace -Path $TestDrive -ExistingPath $TestDrive -MinimumFreeSpaceGB 1 -Operation test
            $result.Basis | Should -Be 'ExistingGenerationEstimate'
            $result.RequiredBytes | Should -Be ([math]::Ceiling(5GB * 1.2) + 64MB)
        }
    }

    It 'stops before building or renaming and preserves every old byte' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'Active'
            New-Item -ItemType Directory -Path $root | Out-Null
            $payload = Join-Path $root 'Package.msi'
            Set-Content -LiteralPath $payload -Value 'old signed payload fixture'
            $hash = (Get-FileHash -LiteralPath $payload).Hash
            Mock Get-OSDAppAvailableDiskBytes { 1MB }
            { Invoke-OSDAppBuiltInCacheTransaction -Root $root -ExpectedBytes 100MB -Build { throw 'build must not run' } -Validate { throw 'validation must not run' } } |
                Should -Throw '*Insufficient free space*'
            (Get-FileHash -LiteralPath $payload).Hash | Should -Be $hash
            @(Get-ChildItem -LiteralPath $TestDrive -Directory).Count | Should -Be 1
        }
    }

    It 'does not start an Office download when a complete candidate cannot fit' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $TestDrive }
            Mock Restore-OSDAppBuiltInCache { }
            Mock Get-OSDAppAvailableDiskBytes { 2GB }
            Mock Save-OSDAppVerifiedBuiltInDownload { throw 'download must not run' }
            { Sync-OSDAppMicrosoft365Apps -Confirm:$false } | Should -Throw '*Insufficient free space*'
            Should -Invoke Save-OSDAppVerifiedBuiltInDownload -Times 0 -Exactly
            @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Directory | Where-Object Name -Like '*.osdapps-new-*').Count | Should -Be 0
        }
    }

    It 'does not demand replacement space when a vendor generation is reused' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'Vendor'
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Package.msi') -Value 'current'
            @{RemoteETag='same';Version='1.0'} | ConvertTo-Json | Set-Content (Join-Path $root 'CacheInfo.json')
            Mock Restore-OSDAppBuiltInCache { }
            Mock Get-OSDAppRemoteFileMetadata { [pscustomobject]@{ETag='same';ContentLength=100MB} }
            Mock Test-OSDAppBuiltInCacheGeneration { $true }
            Mock Get-OSDAppCachedPackageVersion { [pscustomobject]@{Version='1.0';VersionSource='Fixture'} }
            Mock Get-OSDAppAvailableDiskBytes { throw 'space query must not run for reuse' }
            $result = Sync-OSDAppVendorBuiltInCache -Id GoogleChromeEnterprise -Root $root -PackageUri 'https://example.invalid/app.msi' -Architecture x64 -PackageFileName Package.msi -Activity test
            $result.Updated | Should -BeFalse
            Should -Invoke Get-OSDAppAvailableDiskBytes -Times 0 -Exactly
        }
    }

    It 'uses a bounded length probe and falls back when HEAD is unsupported' {
        InModuleScope OSDApps {
            Mock Invoke-WebRequest { throw '405 Method Not Allowed' } -ParameterFilter { $Method -eq 'Head' -and $TimeoutSec -eq 15 }
            Mock Get-OSDAppPathSize { 2GB }
            $archive = [pscustomobject]@{Uri='https://example.invalid/Package.zip';SourcePath=$null}
            Get-OSDAppArchiveSpaceEstimate -Archive $archive -ExistingPath $TestDrive | Should -Be 2GB
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
    }

    It 'uses the remote archive length when it is available' {
        InModuleScope OSDApps {
            Mock Invoke-WebRequest { [pscustomobject]@{Headers=@{'Content-Length'='123456'}} }
            $archive = [pscustomobject]@{Uri='https://example.invalid/Package.zip';SourcePath=$null}
            Get-OSDAppArchiveSpaceEstimate -Archive $archive -ExistingPath $TestDrive | Should -Be 123456
        }
    }

    It 'stages the exact shared space helper alongside PreInstall' {
        InModuleScope OSDApps {
            Add-OSDAppSetupComplete -WindowsPath $TestDrive -Confirm:$false | Out-Null
            $source = Join-Path (Split-Path (Get-Module OSDApps).Path -Parent) 'Runtime\Assert-OSDAppTransactionSpace.ps1'
            $staged = Join-Path $TestDrive 'Windows\Temp\OSDApps\Assert-OSDAppTransactionSpace.ps1'
            (Get-FileHash -LiteralPath $staged).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        }
    }
}

Describe 'Standalone PreInstall low-space fallback' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'Runtime\Assert-OSDAppTransactionSpace.ps1')
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime\Invoke-OSDAppPreInstall.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Test-LocalMsiSource','Sync-PreInstallVendorMsi')) {
            $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
            . ([scriptblock]::Create($node.Extent.Text))
        }
        function Assert-PreInstallSignedPayload { param($Id,$Path) }
        function Restore-PreInstallBuiltInCache { param($Root,$Id) }
        function Write-PreInstallLog { param($Event,$Level,$Message,$Data) }
        function Get-RemoteMetadata { param($Uri) }
        function Save-PreInstallDownload { param($Uri,$DestinationPath,$Id,$Description,$TimeoutMinutes) }
    }

    It 'preserves the active generation and uses the staged payload when refresh cannot fit' {
        $usbRoot = Join-Path $TestDrive 'Usb'
        $StagedPath = Join-Path $TestDrive 'Staged'
        $networkAvailable = $true
        $relative = 'BuiltIn\GoogleChromeEnterprise\x64'
        $active = Join-Path $usbRoot $relative
        New-Item -ItemType Directory -Path $active -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $active 'Package.msi') -Value 'working payload'
        @{Id='GoogleChromeEnterprise';RemoteETag='old';Version='1.0'} | ConvertTo-Json | Set-Content (Join-Path $active 'CacheInfo.json')
        $hash = (Get-FileHash -LiteralPath (Join-Path $active 'Package.msi')).Hash
        Mock Get-OSDAppAvailableDiskBytes { 100MB }
        Mock Get-RemoteMetadata { [pscustomobject]@{ETag='new';ContentLength=200MB} }
        Mock Save-PreInstallDownload { throw 'download must not start' }
        Mock Write-PreInstallLog { }
        Sync-PreInstallVendorMsi -App ([pscustomobject]@{Id='GoogleChromeEnterprise';Architecture='x64'}) -RelativeRoot $relative -PackageUri 'https://example.invalid/package.msi' -DisplayName Chrome
        (Get-FileHash -LiteralPath (Join-Path $active 'Package.msi')).Hash | Should -Be $hash
        (Get-FileHash -LiteralPath (Join-Path (Join-Path $StagedPath $relative) 'Package.msi')).Hash | Should -Be $hash
        Should -Invoke Save-PreInstallDownload -Times 0 -Exactly
        Should -Invoke Write-PreInstallLog -Times 1 -Exactly -ParameterFilter { $Event -eq 'BuiltInRefreshFailed' -and $Data.Fallback -eq 'ExistingStagedPayload' -and $Message -like '*Insufficient free space*' }
    }
}
