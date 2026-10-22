Describe 'Built-in vendor filenames' {
    BeforeAll {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
        . (Join-Path $moduleRoot 'Runtime/OSDAppPayloadFile.ps1')
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
        try { Get-OSDAppDownloadFileName -Response $response -ExpectedExtension '.msi' | Should -BeExactly 'Firefox 145.0.msi' }
        finally { $response.Dispose() }
    }
    It 'uses the Content-Disposition filename ahead of an opaque endpoint' {
        $response = New-FilenameResponse 'https://vendor.example/download' 'attachment; filename="VC_redist.x64.exe"'
        try { Get-OSDAppDownloadFileName -Response $response -ExpectedExtension '.exe' | Should -BeExactly 'VC_redist.x64.exe' }
        finally { $response.Dispose() }
    }
    It 'supports the extended Content-Disposition filename' {
        $response = New-FilenameResponse 'https://vendor.example/download' "attachment; filename*=UTF-8''Firefox%20145.0.msi"
        try { Get-OSDAppDownloadFileName -Response $response -ExpectedExtension '.msi' | Should -BeExactly 'Firefox 145.0.msi' }
        finally { $response.Dispose() }
    }
    It 'rejects unsafe or unexpected server filenames: <Name>' -ForEach @(
        @{Name='../escape.exe'}, @{Name='C:\escape.exe'}, @{Name='CON.exe'},
        @{Name='file.exe:stream'}, @{Name='file.exe.'}, @{Name='file.exe '}, @{Name='payload.zip'}
    ) {
        $response = New-FilenameResponse ('https://vendor.example/' + [uri]::EscapeDataString($Name))
        try { { Get-OSDAppDownloadFileName -Response $response -ExpectedExtension '.exe' } | Should -Throw '*safe .exe filename*' }
        finally { $response.Dispose() }
    }
    It 'resolves a native payload and leaves its name and contents unchanged' {
        $root = Join-Path $TestDrive 'Native'
        New-Item -ItemType Directory $root | Out-Null
        $native = Join-Path $root '7z2605-x64.exe'
        Set-Content -LiteralPath $native 'original bytes'
        $hash = (Get-FileHash $native).Hash
        Resolve-OSDAppBuiltInPayloadPath (Join-Path $root 'Package.exe') | Should -Be $native
        (Get-FileHash $native).Hash | Should -Be $hash
        Test-Path (Join-Path $root 'Package.exe') | Should -BeFalse
    }
    It 'continues reading an existing generic-name cache without renaming it' {
        $root = Join-Path $TestDrive 'Legacy'
        New-Item -ItemType Directory $root | Out-Null
        $legacy = Join-Path $root 'Package.msi'
        Set-Content $legacy 'old bytes'
        Resolve-OSDAppBuiltInPayloadPath $legacy | Should -Be $legacy
    }
    It 'rejects ambiguous generations instead of choosing a version or a generic name' {
        $root = Join-Path $TestDrive 'Ambiguous'
        New-Item -ItemType Directory $root | Out-Null
        Set-Content (Join-Path $root 'Package.exe') old
        Set-Content (Join-Path $root '7z2605-x64.exe') new
        { Resolve-OSDAppBuiltInPayloadPath (Join-Path $root 'Package.exe') } | Should -Throw '*Ambiguous*'
    }
    It 'copies a replacement under its original name and retires the previous staged payload' {
        $source = Join-Path $TestDrive 'Source'
        $target = Join-Path $TestDrive 'Target'
        New-Item -ItemType Directory $source,$target | Out-Null
        $native = Join-Path $source 'vendor-installer.msi'
        Set-Content $native 'new bytes'
        Set-Content (Join-Path $target 'Package.msi') 'old bytes'
        Copy-OSDAppBuiltInPayload -Path (Join-Path $source 'Package.msi') -DestinationDirectory $target
        (Get-FileHash (Join-Path $target 'vendor-installer.msi')).Hash | Should -Be (Get-FileHash $native).Hash
        Test-Path (Join-Path $target 'Package.msi') | Should -BeFalse
        Test-Path $native | Should -BeTrue
    }
    It 'stages a native Chrome installer and the runtime filename helper without renaming the installer' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'StageCache'
            $payload = Join-Path $cache 'BuiltIn/GoogleChromeEnterprise/x64/googlechromestandaloneenterprise64.msi'
            New-Item -ItemType Directory (Split-Path $payload -Parent) -Force | Out-Null
            Set-Content $payload 'signed-payload-fixture'
            $windows = Join-Path $TestDrive 'StageWindows'
            New-Item -ItemType Directory $windows | Out-Null
            Add-OSDAppGoogleChromeEnterpriseInternal -CachePath $cache -WindowsPath $windows -Architecture x64 -PackageUri 'https://vendor.example/chrome.msi' -Confirm:$false | Out-Null
            $stage = Join-Path $windows 'Windows/Temp/OSDApps'
            $app = (Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json).Apps[0]
            $resolved = Resolve-OSDAppBuiltInPayloadPath (Join-Path $stage $app.Package)
            (Split-Path $resolved -Leaf) | Should -Be 'googlechromestandaloneenterprise64.msi'
            (Get-FileHash $resolved).Hash | Should -Be (Get-FileHash $payload).Hash
            Test-Path (Join-Path (Split-Path $resolved -Parent) 'Package.msi') | Should -BeFalse
        }
    }
    It 'promotes a native vendor generation and validates reuse without another download' {
        InModuleScope OSDApps {
            Mock Restore-OSDAppBuiltInCache { }
            Mock Get-OSDAppRemoteFileMetadata { [pscustomobject]@{ ETag='same'; LastModified=$null; ContentLength=7; FinalUri='https://vendor.example/native.msi' } }
            Mock Assert-OSDAppTransactionSpace { }
            Mock Save-OSDAppVerifiedBuiltInDownload {
                Set-Content -LiteralPath (Join-Path (Split-Path $DestinationPath -Parent) 'native.msi') -Value 'fixture'
            }
            Mock Assert-OSDAppBuiltInSignature { }
            Mock Get-OSDAppCachedPackageVersion { [pscustomobject]@{Version='1.0';VersionSource='MsiProductVersion'} }
            $root = Join-Path $TestDrive 'TransactionNative'
            $arguments = @{Id='GoogleChromeEnterprise';Root=$root;PackageUri='https://vendor.example/latest';Architecture='x64';PackageFileName='Package.msi';Activity='Test';SignedPackage=$true}
            (Sync-OSDAppVendorBuiltInCache @arguments).Updated | Should -BeTrue
            (Sync-OSDAppVendorBuiltInCache @arguments).Updated | Should -BeFalse
            Should -Invoke Save-OSDAppVerifiedBuiltInDownload -Times 1 -Exactly -ParameterFilter { $PreserveFileName }
            Test-Path (Join-Path $root 'native.msi') | Should -BeTrue
            Test-Path (Join-Path $root 'Package.msi') | Should -BeFalse
        }
    }
    It 'keeps an ambiguous variant visible and unhealthy alongside a healthy variant' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Inventory'
            foreach ($arch in @('x86','x64')) {
                $variant = Join-Path $cache (Join-Path 'BuiltIn/GoogleChromeEnterprise' $arch)
                New-Item -ItemType Directory $variant -Force | Out-Null
                @{Id='GoogleChromeEnterprise';Architecture=$arch;Version='1.0';Cached=$true} | ConvertTo-Json | Set-Content (Join-Path $variant 'CacheInfo.json')
                Set-Content (Join-Path $variant 'chrome.msi') 'fixture'
            }
            Set-Content (Join-Path $cache 'BuiltIn/GoogleChromeEnterprise/x64/Package.msi') 'ambiguous'
            $entries = @(Get-OSDAppCache -CachePath $cache)
            $entries.Count | Should -Be 2
            ($entries | Where-Object Architecture -eq x86).Valid | Should -BeTrue
            ($entries | Where-Object Architecture -eq x64).Valid | Should -BeFalse
            ($entries | Where-Object Architecture -eq x64).PayloadError | Should -Match 'Ambiguous'
            $health = Get-OSDAppCacheHealthState -CachePath $cache
            @($health.Entries | Where-Object State -eq Corrupt).Count | Should -Be 1
        }
    }

}
