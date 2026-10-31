BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Cache transaction space budgets' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force
    }

    It 'allows a candidate without budgeting the already occupied old generation twice' {
        InModuleScope OSDStage {
            Mock Get-OSDStageAvailableDiskBytes { 150MB }
            $result = Assert-OSDStageTransactionSpace -Path $TestDrive -ExpectedBytes 64MB -Operation test
            $result.RequiredBytes | Should -Be ([math]::Ceiling(64MB * 1.2) + 64MB)
        }
    }

    It 'accounts for growth beyond the public minimum' {
        InModuleScope OSDStage {
            Mock Get-OSDStageAvailableDiskBytes { 2GB }
            { Assert-OSDStageTransactionSpace -Path $TestDrive -ExpectedBytes 3GB -MinimumFreeSpaceGB 1 -Operation test } |
                Should -Throw '*Insufficient free space*'
        }
    }

    It 'uses the old generation as an estimate when the remote length is unknown' {
        InModuleScope OSDStage {
            Mock Get-OSDStageAvailableDiskBytes { 10GB }
            Mock Get-OSDStagePathSize { 5GB }
            $result = Assert-OSDStageTransactionSpace -Path $TestDrive -ExistingPath $TestDrive -MinimumFreeSpaceGB 1 -Operation test
            $result.Basis | Should -Be 'ExistingGenerationEstimate'
            $result.RequiredBytes | Should -Be ([math]::Ceiling(5GB * 1.2) + 64MB)
        }
    }

    It 'stops before building or renaming and preserves every old byte' {
        InModuleScope OSDStage {
            $root = Join-Path $TestDrive 'Active'
            New-Item -ItemType Directory -Path $root | Out-Null
            $payload = Join-Path $root 'googlechromestandaloneenterprise64.msi'
            Set-Content -LiteralPath $payload -Value 'old signed payload fixture'
            $hash = (Get-FileHash -LiteralPath $payload).Hash
            Mock Get-OSDStageAvailableDiskBytes { 1MB }
            { Invoke-OSDStageBuiltInCacheTransaction -Root $root -ExpectedBytes 100MB -Build { throw 'build must not run' } -Validate { throw 'validation must not run' } } |
                Should -Throw '*Insufficient free space*'
            (Get-FileHash -LiteralPath $payload).Hash | Should -Be $hash
            @(Get-ChildItem -LiteralPath $TestDrive -Directory).Count | Should -Be 1
        }
    }

    It 'does not start an Office download when a complete candidate cannot fit' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $false }
            Mock Get-OSDStageCachePath { $TestDrive }
            Mock Restore-OSDStageBuiltInCache { }
            Mock Get-OSDStageAvailableDiskBytes { 2GB }
            Mock Save-OSDStageVerifiedBuiltInDownload { throw 'download must not run' }
            { Sync-OSDStageMicrosoft365Apps -Confirm:$false } | Should -Throw '*Insufficient free space*'
            Should -Invoke Save-OSDStageVerifiedBuiltInDownload -Times 0 -Exactly
            @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Directory | Where-Object Name -Like '*.osdstage-new-*').Count | Should -Be 0
        }
    }

    It 'does not demand replacement space when a vendor generation is reused' {
        InModuleScope OSDStage {
            $root = Join-Path $TestDrive 'Vendor'
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'googlechromestandaloneenterprise64.msi') -Value 'current'
            Set-OSDStageTestPayloadInfo -Path (Join-Path $root 'googlechromestandaloneenterprise64.msi') -Id GoogleChromeEnterprise -Metadata @{RemoteETag='same';Version='1.0';PackageUri='https://example.invalid/app.msi'}
            Mock Restore-OSDStageBuiltInCache { }
            Mock Get-OSDStageRemoteFileMetadata { [pscustomobject]@{ETag='same';ContentLength=100MB} }
            Mock Test-OSDStageBuiltInCacheGeneration { $true }
            Mock Get-OSDStageCachedPackageVersion { [pscustomobject]@{Version='1.0';VersionSource='Fixture'} }
            Mock Get-OSDStageAvailableDiskBytes { throw 'space query must not run for reuse' }
            $result = Sync-OSDStageVendorBuiltInCache -Id GoogleChromeEnterprise -Root $root -PackageUri 'https://example.invalid/app.msi' -Architecture x64 -ExpectedExtension '.msi' -Activity test
            $result.Updated | Should -BeFalse
            Should -Invoke Get-OSDStageAvailableDiskBytes -Times 0 -Exactly
        }
    }

    It 'uses a bounded length probe and falls back when HEAD is unsupported' {
        InModuleScope OSDStage {
            Mock Invoke-WebRequest { throw '405 Method Not Allowed' } -ParameterFilter { $Method -eq 'Head' -and $TimeoutSec -eq 15 }
            Mock Get-OSDStagePathSize { 2GB }
            $archive = [pscustomobject]@{Uri='https://example.invalid/Package.zip';SourcePath=$null}
            Get-OSDStageArchiveSpaceEstimate -Archive $archive -ExistingPath $TestDrive | Should -Be 2GB
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
    }

    It 'uses the remote archive length when it is available' {
        InModuleScope OSDStage {
            Mock Invoke-WebRequest { [pscustomobject]@{Headers=@{'Content-Length'='123456'}} }
            $archive = [pscustomobject]@{Uri='https://example.invalid/Package.zip';SourcePath=$null}
            Get-OSDStageArchiveSpaceEstimate -Archive $archive -ExistingPath $TestDrive | Should -Be 123456
        }
    }

    It 'stages the exact shared space helper alongside PreInstall' {
        InModuleScope OSDStage {
            Add-OSDStageSetupComplete -WindowsPath $TestDrive -Confirm:$false | Out-Null
            $source = Join-Path (Split-Path (Get-Module OSDStage).Path -Parent) 'Runtime\Assert-OSDStageTransactionSpace.ps1'
            $staged = Join-Path $TestDrive 'Windows\Temp\OSDStage\Assert-OSDStageTransactionSpace.ps1'
            (Get-FileHash -LiteralPath $staged).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        }
    }
}

Describe 'Standalone PreInstall low-space fallback' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDStagePayloadFile.ps1')
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'Runtime\Assert-OSDStageTransactionSpace.ps1')
        . (Join-Path $root 'Runtime\Invoke-OSDStageBuiltInCacheTransaction.ps1')
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime\Invoke-OSDStagePreInstall.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Test-LocalMsiSource','Sync-PreInstallVendorMsi','Set-PreInstallAcquisitionResult','Get-PreInstallFailureType','Get-PreInstallHttpCacheReason')) {
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
        Set-Content -LiteralPath (Join-Path $active 'googlechromestandaloneenterprise64.msi') -Value 'working payload'
        Set-OSDStageTestPayloadInfo -Path (Join-Path $active 'googlechromestandaloneenterprise64.msi') -Id GoogleChromeEnterprise -Metadata @{RemoteETag='old';Version='1.0';PackageUri='https://example.invalid/googlechromestandaloneenterprise64.msi'}
        $hash = (Get-FileHash -LiteralPath (Join-Path $active 'googlechromestandaloneenterprise64.msi')).Hash
        Mock Get-OSDStageAvailableDiskBytes { 100MB }
        Mock Get-RemoteMetadata { [pscustomobject]@{ETag='new';ContentLength=200MB} }
        Mock Save-PreInstallDownload { throw 'download must not start' }
        Mock Write-PreInstallLog { }
        $acquisition = @{ Outcome='Failed'; RefreshFailureType=$null; RefreshError=$null }
        Sync-PreInstallVendorMsi -App ([pscustomobject]@{Id='GoogleChromeEnterprise';Architecture='x64'}) -RelativeRoot $relative -PackageUri 'https://example.invalid/googlechromestandaloneenterprise64.msi' -DisplayName Chrome -Acquisition $acquisition
        (Get-FileHash -LiteralPath (Join-Path $active 'googlechromestandaloneenterprise64.msi')).Hash | Should -Be $hash
        (Get-FileHash -LiteralPath (Join-Path (Join-Path $StagedPath $relative) 'googlechromestandaloneenterprise64.msi')).Hash | Should -Be $hash
        $acquisition.Outcome | Should -Be FallbackCacheUsed
        $acquisition.RefreshFailureType | Should -Be InsufficientDiskSpace
        $acquisition.CacheDecisionReason | Should -Match 'Refresh failed.*Insufficient free space'
        Should -Invoke Save-PreInstallDownload -Times 0 -Exactly
        Should -Invoke Write-PreInstallLog -Times 1 -Exactly -ParameterFilter { $Event -eq 'BuiltInRefreshFailed' -and $Data.Fallback -eq 'ExistingStagedPayload' -and $Message -like '*Insufficient free space*' }
    }
}
