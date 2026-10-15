Describe 'Interrupted built-in cache directory swap recovery' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $moduleRoot 'Runtime\Restore-OSDAppCacheGeneration.ps1')
        $validate = {
            param($candidate)
            $file = Join-Path $candidate 'payload.txt'
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Content -LiteralPath $file -Raw).Trim() -ne 'valid-old') {
                throw 'Invalid test generation.'
            }
        }
        function New-RecoveryFixture {
            param([string]$Root)
            $backup = "$Root.osdapps-old-$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $backup 'payload.txt') -Value 'valid-old' -Encoding ASCII
            $backup
        }
    }

    It 'restores unchanged old bytes after a stop between the two renames, leaving new content uncommitted' {
        $root = Join-Path $TestDrive 'BeforePromotion\Active'
        $old = New-RecoveryFixture $root
        $hash = (Get-FileHash -LiteralPath (Join-Path $old 'payload.txt')).Hash
        $new = "$root.osdapps-new-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $new | Out-Null
        Set-Content -LiteralPath (Join-Path $new 'partial.txt') -Value 'partial'
        $result = Restore-OSDAppCacheGeneration -Root $root -Validate $validate
        $result.Recovered | Should -BeTrue
        (Get-FileHash -LiteralPath (Join-Path $root 'payload.txt')).Hash | Should -Be $hash
        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $new | Should -BeTrue
        @(Restore-OSDAppCacheGeneration -Root $root -Validate { throw 'must not run twice' }).Count | Should -Be 0
    }

    It 'does not replace active content when interruption was after promotion' {
        $root = Join-Path $TestDrive 'AfterPromotion\Active'
        $old = New-RecoveryFixture $root
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'payload.txt') -Value 'new-active'
        Restore-OSDAppCacheGeneration -Root $root -Validate { throw 'must not inspect old while active exists' }
        (Get-Content -LiteralPath (Join-Path $root 'payload.txt') -Raw).Trim() | Should -Be 'new-active'
        Test-Path -LiteralPath $old | Should -BeTrue
    }

    It 'never promotes only-new content or folders with unrelated backup names' {
        $root = Join-Path $TestDrive 'OnlyNew\Active'
        $new = "$root.osdapps-new-$([guid]::NewGuid().ToString('N'))"
        $unrelated = "$root.osdapps-old-user-backup"
        New-Item -ItemType Directory -Path $new,$unrelated -Force | Out-Null
        Restore-OSDAppCacheGeneration -Root $root -Validate { throw 'must not run' }
        Test-Path -LiteralPath $root | Should -BeFalse
        Test-Path -LiteralPath $new | Should -BeTrue
        Test-Path -LiteralPath $unrelated | Should -BeTrue
    }

    It 'preserves all evidence and refuses to guess between multiple valid old generations' {
        $root = Join-Path $TestDrive 'Ambiguous\Active'
        $one = New-RecoveryFixture $root
        $two = New-RecoveryFixture $root
        { Restore-OSDAppCacheGeneration -Root $root -Validate $validate } | Should -Throw '*found 2*'
        Test-Path -LiteralPath $root | Should -BeFalse
        Test-Path -LiteralPath $one | Should -BeTrue
        Test-Path -LiteralPath $two | Should -BeTrue
    }

    It 'preserves a rejected old generation without creating an empty active directory' {
        $root = Join-Path $TestDrive 'Invalid\Active'
        $old = New-RecoveryFixture $root
        { Restore-OSDAppCacheGeneration -Root $root -Validate { throw 'bad signature or payload' } } | Should -Throw '*found 0*'
        Test-Path -LiteralPath $root | Should -BeFalse
        Test-Path -LiteralPath $old | Should -BeTrue
    }

    It 'preserves the backup if restoring the directory fails' {
        $root = Join-Path $TestDrive 'MoveFailure\Active'
        $old = New-RecoveryFixture $root
        Mock Move-Item { throw 'simulated locked destination' }
        { Restore-OSDAppCacheGeneration -Root $root -Validate $validate } | Should -Throw '*locked destination*'
        Test-Path -LiteralPath $old | Should -BeTrue
        Test-Path -LiteralPath $root | Should -BeFalse
    }
}

Describe 'Built-in recovery validation' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $moduleRoot 'Runtime\Restore-OSDAppCacheGeneration.ps1')
        . (Join-Path $moduleRoot 'Private\Test-OSDAppOfficeCacheGeneration.ps1')
        . (Join-Path $moduleRoot 'Private\Get-OSDAppMicrosoftTeamsPackageVersion.ps1')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $validators = @{
            SignatureValidator = { param($appId,$file) }
            OfficeValidator = {
                param($officeRoot,$version,$architecture)
                Test-OSDAppOfficeCacheGeneration -OfficeRoot $officeRoot -ExpectedVersion $version -Architecture $architecture | Out-Null
            }
            TeamsVersionReader = { param($file) Get-OSDAppMicrosoftTeamsPackageVersion -Path $file }
        }
        function New-BuiltInRecoveryFixture {
            param([string]$Root,[string]$Id)
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            @{Id=$Id;Cached=$true;Version='1.2.3.4';Architecture='x64'} | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $Root 'CacheInfo.json')
            switch ($Id) {
                'Microsoft365Apps' {
                    $data = Join-Path $Root 'Office\Data'
                    New-Item -ItemType Directory -Path (Join-Path $data '1.2.3.4') -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $Root 'setup.exe') -Value setup
                    Set-Content -LiteralPath (Join-Path $Root 'configuration.xml') -Value '<Configuration />'
                    Set-Content -LiteralPath (Join-Path $data '1.2.3.4\stream.dat') -Value payload
                    Set-Content -LiteralPath (Join-Path $data 'v64.cab') -Value cab
                    Set-Content -LiteralPath (Join-Path $data 'v64_1.2.3.4.cab') -Value cab
                }
                'MicrosoftTeams' {
                    Set-Content -LiteralPath (Join-Path $Root 'teamsbootstrapper.exe') -Value bootstrapper
                    $zip = [IO.Compression.ZipFile]::Open((Join-Path $Root 'teams.msix'),[IO.Compression.ZipArchiveMode]::Create)
                    try {
                        $writer = [IO.StreamWriter]::new($zip.CreateEntry('AppxManifest.xml').Open())
                        try { $writer.Write('<Package><Identity Version="1.2.3.4" /></Package>') } finally { $writer.Dispose() }
                    }
                    finally { $zip.Dispose() }
                }
                'AdobeAcrobatUnified' {
                    $zip = [IO.Compression.ZipFile]::Open((Join-Path $Root 'Package.zip'),[IO.Compression.ZipArchiveMode]::Create)
                    try { [void]$zip.CreateEntry('Acrobat/setup.exe') } finally { $zip.Dispose() }
                }
                default { Set-Content -LiteralPath (Join-Path $Root 'Package.msi') -Value msi }
            }
        }
    }

    It 'validates the required layout and metadata for <Id>' -ForEach @(
        @{Id='Microsoft365Apps'}, @{Id='MicrosoftTeams'}, @{Id='GoogleChromeEnterprise'},
        @{Id='MozillaFirefoxEnterprise'}, @{Id='CiscoWebex'}, @{Id='AdobeAcrobatUnified'}
    ) {
        $root = Join-Path $TestDrive $Id
        New-BuiltInRecoveryFixture -Root $root -Id $Id
        { Assert-OSDAppRecoverableBuiltInGeneration -Root $root -Id $Id @validators } | Should -Not -Throw
    }

    It 'rejects hybrid Office CAB metadata before restoring an old generation' {
        $root = Join-Path $TestDrive HybridOffice
        New-BuiltInRecoveryFixture -Root $root -Id Microsoft365Apps
        Set-Content -LiteralPath (Join-Path $root 'Office\Data\v64.cab') -Value wrong
        { Assert-OSDAppRecoverableBuiltInGeneration -Root $root -Id Microsoft365Apps @validators } | Should -Throw '*does not match*'
    }

    It 'rejects a Teams MSIX version that differs from cache metadata' {
        $root = Join-Path $TestDrive MismatchedTeams
        New-BuiltInRecoveryFixture -Root $root -Id MicrosoftTeams
        @{Id='MicrosoftTeams';Cached=$true;Version='9.9.9.9'} | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json')
        { Assert-OSDAppRecoverableBuiltInGeneration -Root $root -Id MicrosoftTeams @validators } | Should -Throw '*does not match*'
    }

    It 'rejects a publisher validation failure' {
        $root = Join-Path $TestDrive RejectedPublisher
        New-BuiltInRecoveryFixture -Root $root -Id GoogleChromeEnterprise
        $rejecting = $validators.Clone()
        $rejecting.SignatureValidator = { throw 'publisher rejected' }
        { Assert-OSDAppRecoverableBuiltInGeneration -Root $root -Id GoogleChromeEnterprise @rejecting } | Should -Throw '*publisher rejected*'
    }

    It 'rejects malformed cache metadata rather than treating files alone as a complete generation' {
        $root = Join-Path $TestDrive MalformedMetadata
        New-BuiltInRecoveryFixture -Root $root -Id GoogleChromeEnterprise
        Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Value '{'
        { Assert-OSDAppRecoverableBuiltInGeneration -Root $root -Id GoogleChromeEnterprise @validators } | Should -Throw
    }
}

Describe 'Recovery integration before acquisition' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'restores the previous module cache before a network failure can prevent downloading' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'ModuleRecovery\x64'
            $old = "$root.osdapps-old-$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $old -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $old 'Package.msi') -Value 'old-msi'
            @{Id='GoogleChromeEnterprise';Cached=$true;Version='1.0';Architecture='x64'} | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $old 'CacheInfo.json')
            $hash = (Get-FileHash -LiteralPath (Join-Path $old 'Package.msi')).Hash
            Mock Assert-OSDAppBuiltInSignature { return }
            Mock Get-OSDAppRemoteFileMetadata { throw 'simulated unavailable network' }
            {
                Sync-OSDAppVendorBuiltInCache -Id GoogleChromeEnterprise -Root $root -PackageUri 'https://example.invalid/package.msi' -Architecture x64 -PackageFileName Package.msi -Activity Test -SignedPackage
            } | Should -Throw '*unavailable network*'
            (Get-FileHash -LiteralPath (Join-Path $root 'Package.msi')).Hash | Should -Be $hash
            Test-Path -LiteralPath $old | Should -BeFalse
            Should -Invoke Assert-OSDAppBuiltInSignature -Exactly 1
        }
    }

    It 'does not restore or download anything under public WhatIf' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'WhatIfRecovery'
            $root = Join-Path $cache 'BuiltIn\MicrosoftTeams'
            $old = "$root.osdapps-old-$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $old -Force | Out-Null
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $cache }
            Mock Restore-OSDAppBuiltInCache { throw 'must not mutate under WhatIf' }
            Sync-OSDAppMicrosoftTeams -WhatIf
            Test-Path -LiteralPath $old | Should -BeTrue
            Test-Path -LiteralPath $root | Should -BeFalse
            Should -Invoke Restore-OSDAppBuiltInCache -Exactly 0
        }
    }

    It 'stages the exact shared recovery helper with SetupComplete' {
        InModuleScope OSDApps {
            $windows = Join-Path $TestDrive 'RecoveryRuntimeStaging'
            Add-OSDAppSetupComplete -WindowsPath $windows -Confirm:$false | Out-Null
            $source = Join-Path (Split-Path (Get-Module OSDApps).Path -Parent) 'Runtime\Restore-OSDAppCacheGeneration.ps1'
            $staged = Join-Path $windows 'Windows\Temp\OSDApps\Restore-OSDAppCacheGeneration.ps1'
            (Get-FileHash -LiteralPath $staged).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        }
    }
}

Describe 'Standalone PreInstall recovery with no network' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'Runtime\Restore-OSDAppCacheGeneration.ps1')
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime\Invoke-OSDAppPreInstall.ps1'),[ref]$tokens,[ref]$errors)
        foreach ($name in @('Restore-PreInstallBuiltInCache','Test-LocalMsiSource','Sync-PreInstallVendorMsi')) {
            $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
            . ([scriptblock]::Create($node.Extent.Text))
        }
        function Assert-PreInstallSignedPayload { param($Id,$Path) }
        function Write-PreInstallLog { param($Event,$Level,$Message,$Data) }
        function Get-RemoteMetadata { param($Uri) }
    }

    It 'recovers the USB directory and stages fallback before the offline early return' {
        $usbRoot = Join-Path $TestDrive 'Usb'
        $StagedPath = Join-Path $TestDrive 'Staged'
        $networkAvailable = $false
        $relative = 'BuiltIn\GoogleChromeEnterprise\x64'
        $active = Join-Path $usbRoot $relative
        $old = "$active.osdapps-old-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $old 'Package.msi') -Value 'offline-msi'
        @{Id='GoogleChromeEnterprise';Cached=$true;Version='1.0';Architecture='x64'} | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $old 'CacheInfo.json')
        $hash = (Get-FileHash -LiteralPath (Join-Path $old 'Package.msi')).Hash
        Mock Assert-PreInstallSignedPayload { return }
        Mock Write-PreInstallLog { return }
        Mock Get-RemoteMetadata { throw 'offline recovery must not need network' }
        Sync-PreInstallVendorMsi -App ([pscustomobject]@{Id='GoogleChromeEnterprise';Architecture='x64'}) -RelativeRoot $relative -PackageUri 'https://example.invalid/package.msi' -DisplayName Chrome
        (Get-FileHash -LiteralPath (Join-Path $active 'Package.msi')).Hash | Should -Be $hash
        (Get-FileHash -LiteralPath (Join-Path (Join-Path $StagedPath $relative) 'Package.msi')).Hash | Should -Be $hash
        Test-Path -LiteralPath $old | Should -BeFalse
        Should -Invoke Get-RemoteMetadata -Exactly 0
        Should -Invoke Write-PreInstallLog -Exactly 1 -ParameterFilter { $Event -eq 'CacheGenerationRecovered' }
        Should -Invoke Write-PreInstallLog -Exactly 1 -ParameterFilter { $Event -eq 'BuiltInRefreshSkipped' }
    }
}
