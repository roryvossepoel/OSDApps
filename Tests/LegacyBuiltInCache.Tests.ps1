BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Legacy built-in cache refresh' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
        . (Join-Path $root 'Runtime/OSDStagePayloadFile.ps1')
    }
    It 'treats unsupported metadata as a miss but keeps the strict resolver strict: <Kind>' -ForEach @(
        @{Kind='Legacy'}, @{Kind='Partial'}, @{Kind='Malformed'}, @{Kind='Generic'}
    ) {
        $root = Join-Path $TestDrive $Kind
        New-Item -ItemType Directory $root | Out-Null
        $file = Join-Path $root $(if ($Kind -eq 'Generic') {'Package.msi'} else {'vendor.msi'})
        Set-Content $file 'old payload'
        $infoPath = Join-Path $root 'CacheInfo.json'
        switch ($Kind) {
            Legacy { '{"Id":"GoogleChromeEnterprise","Architecture":"x64"}' | Set-Content $infoPath }
            Partial { '{"Id":"GoogleChromeEnterprise","Architecture":"x64","PayloadFileName":"vendor.msi"}' | Set-Content $infoPath }
            Malformed { '{invalid' | Set-Content $infoPath }
            Generic { Set-OSDStageTestPayloadInfo -Path $file -Id GoogleChromeEnterprise }
        }
        $before = (Get-FileHash $file).Hash
        Test-OSDStageBuiltInPayload -Root $root -ExpectedExtension '.msi' | Should -BeFalse
        { Assert-OSDStageCachedPayload -Root $root -ExpectedExtension '.msi' -Id GoogleChromeEnterprise } | Should -Throw
        (Get-FileHash $file).Hash | Should -Be $before
    }
    It 'stages acquisition intent without copying legacy Adobe or Chrome bytes' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $cache = Join-Path $TestDrive ('USB-' + [guid]::NewGuid().ToString('N'))
            Mock Get-OSDStageCachePath { $cache }
            $windows = Join-Path $TestDrive 'Windows'
            New-Item -ItemType Directory $windows | Out-Null
            foreach ($id in @('AdobeAcrobatUnified','GoogleChromeEnterprise')) {
                $root = Join-Path $cache "BuiltIn/$id/x64"
                New-Item -ItemType Directory $root -Force | Out-Null
                '{"Id":"old","Architecture":"x64"}' | Set-Content (Join-Path $root 'CacheInfo.json')
                Set-Content (Join-Path $root 'Package.zip') 'unverified old bytes'
            }
            Add-OSDStageAdobeAcrobatUnified -Architecture x64 -WindowsPath $windows | Out-Null
            Add-OSDStageGoogleChromeEnterprise -Architecture x64 -WindowsPath $windows | Out-Null
            $stage = Join-Path $windows 'Windows/Temp/OSDStage'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $manifest.Packages.Count | Should -Be 2
            foreach ($app in $manifest.Packages) {
                $app.Package | Should -BeNullOrEmpty
                $app.PayloadSha256 | Should -BeNullOrEmpty
                Test-Path (Join-Path $stage "$($app.PayloadRoot)/CacheInfo.json") | Should -BeFalse
                Test-Path (Join-Path $cache "$($app.PayloadRoot)/Package.zip") | Should -BeTrue
            }
            $validation = Test-OSDStageDeployment -WindowsPath $windows
            $validation.Valid | Should -BeTrue
            $validation.OfflineReady | Should -BeFalse
            $validation.NetworkRequired | Should -BeTrue
            { Test-OSDStageDeployment -WindowsPath $windows -RequireOfflineReady -ThrowOnFailure } | Should -Throw
        }
    }
    It 'rebuilds a legacy cache through public Sync even when the remote ETag is unchanged: <Id>' -ForEach @(
        @{Id='AdobeAcrobatUnified'}, @{Id='GoogleChromeEnterprise'}
    ) {
        InModuleScope OSDStage -Parameters @{Id=$Id} {
            param($Id)
            Mock Test-OSDStageWinPE { $false }
            $cache = Join-Path $TestDrive ('USB-' + [guid]::NewGuid().ToString('N'))
            Mock Get-OSDStageCachePath { $cache }
            Mock Assert-OSDStageTransactionSpace { }
            Mock Get-OSDStageRemoteFileMetadata { [pscustomobject]@{ETag='unchanged';ContentLength=100;LastModified=$null;FinalUri='https://example.invalid/vendor'} }
            Mock Get-OSDStageCachedPackageVersion { [pscustomobject]@{Version='1.2.3';VersionSource='Fixture'} }
            Mock Assert-OSDStageBuiltInSignature { }
            Mock Save-OSDStageDownload {
                $file = Join-Path $DestinationDirectory 'Acrobat_fixture.zip'
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $zip = [IO.Compression.ZipFile]::Open($file,[IO.Compression.ZipArchiveMode]::Create)
                try { $null = $zip.CreateEntry('payload.txt') } finally { $zip.Dispose() }
                Get-Item $file
            }
            Mock Save-OSDStageVerifiedBuiltInDownload {
                $file = Join-Path $DestinationDirectory 'Chrome_fixture.msi'
                Set-Content $file 'new publisher-validated fixture'
                Get-Item $file
            }
            $root = Join-Path $cache "BuiltIn/$Id/x64"
            New-Item -ItemType Directory $root -Force | Out-Null
            @{Id=$Id;Architecture='x64';RemoteETag='unchanged';PackageUri='https://example.invalid/vendor'} | ConvertTo-Json | Set-Content (Join-Path $root 'CacheInfo.json')
            Set-Content (Join-Path $root 'Package.zip') 'legacy bytes'
            $command = 'Sync-OSDStage' + $Id
            $result = & $command -Architecture x64 -PackageUri 'https://example.invalid/vendor' -Confirm:$false
            $result.Updated | Should -BeTrue
            $info = Get-Content (Join-Path $root 'CacheInfo.json') -Raw | ConvertFrom-Json
            $info.PayloadFileName | Should -Match '_fixture\.(zip|msi)$'
            Assert-OSDStageCachedPayload -Root $root -Id $Id -Architecture x64 | Should -Be (Join-Path $root $info.PayloadFileName)
            Test-Path (Join-Path $root 'Package.zip') | Should -BeFalse
            if ($Id -eq 'AdobeAcrobatUnified') { Should -Invoke Save-OSDStageDownload -Exactly 1 }
            else { Should -Invoke Save-OSDStageVerifiedBuiltInDownload -Exactly 1 }
        }
    }
    It 'preserves the legacy generation when replacement download or validation fails: <Failure>' -ForEach @(
        @{Failure='Download'}, @{Failure='Validation'}
    ) {
        InModuleScope OSDStage -Parameters @{Failure=$Failure} {
            param($Failure)
            Mock Test-OSDStageWinPE { $false }
            $cache = Join-Path $TestDrive ('USB-' + [guid]::NewGuid().ToString('N'))
            Mock Get-OSDStageCachePath { $cache }
            Mock Assert-OSDStageTransactionSpace { }
            Mock Get-OSDStageRemoteFileMetadata { [pscustomobject]@{ETag='same';ContentLength=100;LastModified=$null;FinalUri='https://example.invalid/vendor'} }
            Mock Get-OSDStageCachedPackageVersion { [pscustomobject]@{Version='1';VersionSource='Fixture'} }
            Mock Save-OSDStageVerifiedBuiltInDownload {
                if ($Failure -eq 'Download') { throw 'fixture download failed' }
                $file = Join-Path $DestinationDirectory 'Chrome_fixture.msi'
                Set-Content $file 'untrusted fixture'
                Get-Item $file
            }
            Mock Assert-OSDStageBuiltInSignature { throw [Security.SecurityException]::new('fixture publisher mismatch') }
            $root = Join-Path $cache 'BuiltIn/GoogleChromeEnterprise/x64'
            New-Item -ItemType Directory $root -Force | Out-Null
            $infoPath = Join-Path $root 'CacheInfo.json'
            '{"Id":"GoogleChromeEnterprise","Architecture":"x64"}' | Set-Content $infoPath
            $file = Join-Path $root 'Package.msi'
            Set-Content $file 'old bytes'
            $hash = (Get-FileHash $file).Hash
            $infoHash = (Get-FileHash $infoPath).Hash
            { Sync-OSDStageGoogleChromeEnterprise -Architecture x64 -Confirm:$false } | Should -Throw '*fixture*'
            (Get-FileHash $file).Hash | Should -Be $hash
            (Get-FileHash $infoPath).Hash | Should -Be $infoHash
            Test-Path (Join-Path $root 'Chrome_fixture.msi') | Should -BeFalse
            @(Get-ChildItem (Split-Path $root -Parent) -Directory | Where-Object Name -like '*.osdstage-new-*').Count | Should -Be 0
        }
    }
}
