BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Built-in vendor filenames' {
    BeforeAll {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
        . (Join-Path $moduleRoot 'Runtime/OSDStagePayloadFile.ps1')
        Add-Type -AssemblyName System.Net.Http
        function New-FilenameResponse {
            param([string]$Uri, [string]$Disposition)
            $response = [Net.Http.HttpResponseMessage]::new()
            $response.RequestMessage = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Uri)
            $response.Content = [Net.Http.StringContent]::new('fixture')
            if ($Disposition) {
                $response.Content.Headers.ContentDisposition = [Net.Http.Headers.ContentDispositionHeaderValue]::Parse($Disposition)
            }
            $response
        }
    }
    It 'uses the final redirect filename, preserving spaces and capitalization' {
        $response = New-FilenameResponse 'https://vendor.example/releases/Firefox%20145.0.msi?download=1'
        try { Get-OSDStageDownloadFileName -Response $response -ExpectedExtension '.msi' | Should -BeExactly 'Firefox 145.0.msi' }
        finally { $response.Dispose() }
    }
    It 'uses the Content-Disposition filename ahead of an opaque endpoint' {
        $response = New-FilenameResponse 'https://vendor.example/download' 'attachment; filename="VC_redist.x64.exe"'
        try { Get-OSDStageDownloadFileName -Response $response -ExpectedExtension '.exe' | Should -BeExactly 'VC_redist.x64.exe' }
        finally { $response.Dispose() }
    }
    It 'supports the extended Content-Disposition filename' {
        $response = New-FilenameResponse 'https://vendor.example/download' "attachment; filename*=UTF-8''Firefox%20145.0.msi"
        try { Get-OSDStageDownloadFileName -Response $response -ExpectedExtension '.msi' | Should -BeExactly 'Firefox 145.0.msi' }
        finally { $response.Dispose() }
    }
    It 'rejects unsafe or unexpected server filenames: <Name>' -ForEach @(
        @{Name='../escape.exe'}, @{Name='C:\escape.exe'}, @{Name='CON.exe'},
        @{Name='file.exe:stream'}, @{Name='file.exe.'}, @{Name='file.exe '}, @{Name='payload.zip'}
    ) {
        $response = New-FilenameResponse ('https://vendor.example/' + [uri]::EscapeDataString($Name))
        try { { Get-OSDStageDownloadFileName -Response $response -ExpectedExtension '.exe' } | Should -Throw '*safe .exe filename*' }
        finally { $response.Dispose() }
    }
    It 'resolves only the recorded name even with same-extension decoys present' {
        $root = Join-Path $TestDrive 'Native'
        New-Item -ItemType Directory $root | Out-Null
        $native = Join-Path $root '7z2605-x64.exe'
        Set-Content -LiteralPath $native 'original bytes'
        Set-Content -LiteralPath (Join-Path $root 'another.exe') 'decoy'
        Set-OSDStageTestPayloadInfo -Path $native -Id 7Zip
        $hash = (Get-FileHash $native).Hash
        Resolve-OSDStageBuiltInPayloadPath -Root $root -ExpectedExtension '.exe' | Should -Be $native
        (Get-FileHash $native).Hash | Should -Be $hash
        Test-Path (Join-Path $root 'Package.exe') | Should -BeFalse
        Remove-Item -LiteralPath $native
        { Assert-OSDStageCachedPayload -Root $root -ExpectedExtension '.exe' } | Should -Throw
        Test-Path (Join-Path $root 'another.exe') | Should -BeTrue
    }
    It 'rejects generic payload names instead of accepting or migrating old caches: <Name>' -ForEach @(
        @{Name='Package.msi'}, @{Name='Package.exe'}, @{Name='Package.zip'}, @{Name='teams.msix'}
    ) {
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory $root | Out-Null
        $path = Join-Path $root $Name
        Set-Content -LiteralPath $path 'bytes'
        Set-OSDStageTestPayloadInfo -Path $path -Id TestVendor
        { Resolve-OSDStageBuiltInPayloadPath -Root $root } | Should -Throw '*Invalid vendor payload filename*'
        { Resolve-OSDStageBuiltInPayloadPath -Path $path } | Should -Throw '*Invalid vendor payload filename*'
        Test-Path -LiteralPath $path | Should -BeTrue
    }
    It 'refuses missing metadata rather than discovering an installer by extension' {
        $root = Join-Path $TestDrive 'Unrecorded'
        New-Item -ItemType Directory $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'installer.exe') 'bytes'
        { Resolve-OSDStageBuiltInPayloadPath -Root $root -ExpectedExtension '.exe' } | Should -Throw
        Test-OSDStageBuiltInPayload -Root $root -ExpectedExtension '.exe' | Should -BeFalse
    }
    It 'copies the original name and retires only the recorded previous payload' {
        $source = Join-Path $TestDrive 'Source'
        $target = Join-Path $TestDrive 'Target'
        New-Item -ItemType Directory $source,$target | Out-Null
        $native = Join-Path $source 'vendor-installer-2.msi'
        $previous = Join-Path $target 'vendor-installer-1.msi'
        Set-Content -LiteralPath $native 'new bytes'
        Set-Content -LiteralPath $previous 'old bytes'
        Set-OSDStageTestPayloadInfo -Path $previous -Id GoogleChromeEnterprise
        Set-Content -LiteralPath (Join-Path $target 'unrelated.msi') 'leave unchanged'
        Copy-OSDStageBuiltInPayload -Path $native -DestinationDirectory $target
        (Get-FileHash (Join-Path $target 'vendor-installer-2.msi')).Hash | Should -Be (Get-FileHash $native).Hash
        Test-Path $previous | Should -BeFalse
        Test-Path (Join-Path $target 'unrelated.msi') | Should -BeTrue
        Test-Path $native | Should -BeTrue
    }
    It 'stages and pins the exact cached Chrome filename without renaming it' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'StageCache'
            $payload = Join-Path $cache 'BuiltIn/GoogleChromeEnterprise/x64/googlechromestandaloneenterprise64.msi'
            New-Item -ItemType Directory (Split-Path $payload -Parent) -Force | Out-Null
            Set-Content $payload 'signed-payload-fixture'
            Set-OSDStageTestPayloadInfo -Path $payload -Id GoogleChromeEnterprise
            $windows = Join-Path $TestDrive 'StageWindows'
            New-Item -ItemType Directory $windows | Out-Null
            Add-OSDStageGoogleChromeEnterpriseInternal -CachePath $cache -WindowsPath $windows -Architecture x64 -PackageUri 'https://vendor.example/chrome.msi' -Confirm:$false | Out-Null
            $stage = Join-Path $windows 'Windows/Temp/OSDStage'
            $app = (Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json).Packages[0]
            $app.Package.Replace('\','/') | Should -BeExactly 'BuiltIn/GoogleChromeEnterprise/x64/googlechromestandaloneenterprise64.msi'
            $app.PayloadSha256 | Should -Be (Get-FileHash $payload).Hash
            $resolved = Assert-OSDStageManifestPayload -App $app -StagedPath $stage
            (Get-FileHash $resolved).Hash | Should -Be (Get-FileHash $payload).Hash
            $app.Package = $app.Package.Replace('googlechromestandaloneenterprise64.msi','decoy.msi')
            Set-Content (Join-Path (Split-Path $resolved -Parent) 'decoy.msi') 'decoy'
            { Assert-OSDStageManifestPayload -App $app -StagedPath $stage } | Should -Throw
        }
    }
    It 'stages only intent for a cold download and binds the real acquired name before execution' {
        InModuleScope OSDStage {
            $windows = Join-Path $TestDrive 'ColdWindows'
            New-Item -ItemType Directory $windows -Force | Out-Null
            Add-OSDStageGoogleChromeEnterpriseInternal -WindowsPath $windows -Architecture x64 -PackageUri 'https://vendor.example/latest' -Confirm:$false | Out-Null
            $stage = Join-Path $windows 'Windows/Temp/OSDStage'
            $app = (Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json).Packages[0]
            $app.Package | Should -BeNullOrEmpty
            $app.PayloadSha256 | Should -BeNullOrEmpty
            { Assert-OSDStageManifestPayload -App $app -StagedPath $stage } | Should -Throw
            $payload = Join-Path $stage 'BuiltIn/GoogleChromeEnterprise/x64/googlechromestandaloneenterprise64.msi'
            Set-Content -LiteralPath $payload 'acquired bytes'
            Set-OSDStageTestPayloadInfo -Path $payload -Id GoogleChromeEnterprise
            Set-OSDStageManifestPayload -App $app -StagedPath $stage
            Assert-OSDStageManifestPayload -App $app -StagedPath $stage | Should -Be $payload
            Add-Content -LiteralPath $payload 'tampered'
            { Assert-OSDStageManifestPayload -App $app -StagedPath $stage } | Should -Throw '*SHA-256*'
        }
    }
    It 'promotes a native vendor generation and validates reuse without another download' {
        InModuleScope OSDStage {
            Mock Restore-OSDStageBuiltInCache { }
            Mock Get-OSDStageRemoteFileMetadata { [pscustomobject]@{ ETag='same'; LastModified=$null; ContentLength=7; FinalUri='https://vendor.example/native.msi' } }
            Mock Assert-OSDStageTransactionSpace { }
            Mock Save-OSDStageVerifiedBuiltInDownload {
                $path = Join-Path $DestinationDirectory 'native.msi'
                Set-Content -LiteralPath $path -Value 'fixture'
                Get-Item -LiteralPath $path
            }
            Mock Assert-OSDStageBuiltInSignature { }
            Mock Get-OSDStageCachedPackageVersion { [pscustomobject]@{Version='1.0';VersionSource='MsiProductVersion'} }
            $root = Join-Path $TestDrive 'TransactionNative'
            $arguments = @{Id='GoogleChromeEnterprise';Root=$root;PackageUri='https://vendor.example/latest';Architecture='x64';ExpectedExtension='.msi';Activity='Test';SignedPackage=$true}
            (Sync-OSDStageVendorBuiltInCache @arguments).Updated | Should -BeTrue
            (Sync-OSDStageVendorBuiltInCache @arguments).Updated | Should -BeFalse
            Should -Invoke Save-OSDStageVerifiedBuiltInDownload -Times 1 -Exactly -ParameterFilter { $ExpectedExtension -eq '.msi' -and $DestinationDirectory }
            $info = Get-Content (Join-Path $root 'CacheInfo.json') -Raw | ConvertFrom-Json
            $info.PayloadFileName | Should -BeExactly 'native.msi'
            $info.Sha256 | Should -Be (Get-FileHash (Join-Path $root 'native.msi')).Hash
            $info.Size | Should -Be (Get-Item (Join-Path $root 'native.msi')).Length
            Test-Path (Join-Path $root 'Package.msi') | Should -BeFalse
        }
    }
    It 'keeps a corrupt recorded variant visible and unhealthy alongside a healthy variant' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Inventory'
            foreach ($arch in @('x86','x64')) {
                $variant = Join-Path $cache (Join-Path 'BuiltIn/GoogleChromeEnterprise' $arch)
                New-Item -ItemType Directory $variant -Force | Out-Null
                $payload = Join-Path $variant 'chrome.msi'
                Set-Content $payload 'fixture'
                Set-OSDStageTestPayloadInfo -Path $payload -Id GoogleChromeEnterprise -Architecture $arch
            }
            Add-Content (Join-Path $cache 'BuiltIn/GoogleChromeEnterprise/x64/chrome.msi') 'changed'
            $entries = @(Get-OSDStageCache -CachePath $cache)
            $entries.Count | Should -Be 2
            ($entries | Where-Object Architecture -eq x86).Valid | Should -BeTrue
            ($entries | Where-Object Architecture -eq x64).Valid | Should -BeFalse
            ($entries | Where-Object Architecture -eq x64).PayloadError | Should -Not -BeNullOrEmpty
            $health = Get-OSDStageCacheHealthState -CachePath $cache
            @($health.Entries | Where-Object State -eq Corrupt).Count | Should -Be 1
        }
    }
}
