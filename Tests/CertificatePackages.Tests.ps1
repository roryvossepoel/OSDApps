Describe 'Repository certificate packages' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\OSDAppCertificate.ps1')
        $script:ca=New-SelfSignedCertificate -Type Custom -Subject 'CN=OSDApps Repository CI CA' -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -KeyUsage CertSign,CRLSign -TextExtension @('2.5.29.19={critical}{text}ca=1') -NotAfter (Get-Date).AddDays(1)
        $script:source=Join-Path $TestDrive 'Source'
        New-Item -ItemType Directory -Path (Join-Path $script:source 'Nested') -Force | Out-Null
        Export-Certificate -Cert $script:ca -FilePath (Join-Path $script:source 'root.cer') | Out-Null
        Export-Certificate -Cert $script:ca -FilePath (Join-Path $script:source 'Nested\duplicate.crt') | Out-Null
        $script:package=New-OSDAppPackage -Id TestRootCA -Version 1.0.0 -PackageType Certificate -SourcePath $script:source -OutputPath (Join-Path $TestDrive 'Build')
    }
    AfterAll {
        if($script:ca){Remove-Item -LiteralPath ('Cert:\CurrentUser\My\'+$script:ca.Thumbprint) -DeleteKey -ErrorAction SilentlyContinue}
    }
    BeforeEach { Set-OSDAppConfiguration -EnableRepository $true -EnableBuiltIns $true }
    It 'builds a certificate ZIP without a script and deduplicates nested certificates' {
        $check=Test-OSDAppPackage -PackagePath $script:package.PackagePath -PackageType Certificate -CertificateStore Root
        $check.Valid | Should -BeTrue
        $check.CertificateCount | Should -Be 1
        $check.InstallPs1Exists | Should -BeFalse
        (Test-OSDAppPackage -PackagePath $script:package.PackagePath -PackageType App).Valid | Should -BeFalse
    }
    It 'validates the ZIP when the PowerShell Archive command cannot run in WinPE' {
        Mock Expand-Archive -ModuleName OSDApps { throw 'Microsoft.PowerShell.Archive cannot load in this WinPE environment.' }
        $check=Test-OSDAppPackage -PackagePath $script:package.PackagePath -PackageType Certificate -CertificateStore Root
        $check.Valid | Should -BeTrue
        $check.CertificateCount | Should -Be 1
        Should -Invoke Expand-Archive -ModuleName OSDApps -Times 0 -Exactly
    }
    It 'rejects ZIP entries that escape the temporary validation directory' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zipPath=Join-Path $TestDrive 'Traversal.zip'
        $escapeName='OSDApps-escape-'+[guid]::NewGuid().ToString('N')+'.cer'
        $outside=Join-Path ([IO.Path]::GetTempPath()) $escapeName
        $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry=$zip.CreateEntry('../'+$escapeName)
            $writer=[IO.StreamWriter]::new($entry.Open())
            try { $writer.Write('must not escape extraction') } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        try {
            {Test-OSDAppPackage -PackagePath $zipPath -PackageType Certificate -CertificateStore Root} | Should -Throw
            Test-Path -LiteralPath $outside | Should -BeFalse
        }
        finally { if(Test-Path -LiteralPath $outside){Remove-Item -LiteralPath $outside -Force} }
    }
    It 'requires an explicit machine store on publication and preserves it on updates' {
        $repo=Join-Path $TestDrive 'Repository'
        New-OSDAppRepository -Path $repo | Out-Null
        $publishParameters=@{Id='TestRootCA';DisplayName='Test Root CA';Version='1.0.0';Architecture='any';PackageType='Certificate';PackagePath=$script:package.PackagePath;RepositoryPath=$repo}
        {Add-OSDAppPackage @publishParameters} | Should -Throw '*require CertificateStore*'
        Add-OSDAppPackage @publishParameters -CertificateStore Root | Out-Null
        (Add-OSDAppPackage @publishParameters).CertificateStore | Should -Be Root
        $manifest=Get-Content (Join-Path $repo 'Apps\TestRootCA\1.0.0\any\manifest.json') -Raw | ConvertFrom-Json
        $manifest.CertificateStore | Should -Be Root
        $manifest.PackageType | Should -Be Certificate
        @(Test-OSDAppRepository -RepositoryPath $repo)[0].Valid | Should -BeTrue
        $before=Get-Content (Join-Path $repo 'catalog.json') -Raw
        Add-OSDAppPackage @publishParameters -CertificateStore CA -WhatIf
        (Get-Content (Join-Path $repo 'catalog.json') -Raw) | Should -Be $before
        (Get-Content (Join-Path $repo 'Apps\TestRootCA\1.0.0\any\manifest.json') -Raw | ConvertFrom-Json).CertificateStore | Should -Be Root
        $manifest.CertificateStore='My'
        $manifest | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $repo 'Apps\TestRootCA\1.0.0\any\manifest.json') -Encoding UTF8
        @(Test-OSDAppRepository -RepositoryPath $repo)[0].Valid | Should -BeFalse
    }
    It 'preserves the store through catalog, cache and offline staging and blocks tampering' {
        InModuleScope OSDApps -Parameters @{PackagePath=$script:package.PackagePath} {
            param($PackagePath)
            $repo=Join-Path $TestDrive 'StagingRepo'
            $cache=Join-Path $TestDrive 'Cache'
            $target=Join-Path $TestDrive 'Offline'
            New-OSDAppRepository -Path $repo | Out-Null
            Add-OSDAppPackage -Id TestRootCA -DisplayName 'Test Root CA' -Version 1.0.0 -Architecture any -PackageType Certificate -CertificateStore Root -PackagePath $PackagePath -RepositoryPath $repo | Out-Null
            Sync-OSDAppCache -CatalogPath (Join-Path $repo 'catalog.json') -CachePath $cache -Architecture x64 -Confirm:$false | Out-Null
            (Get-Content (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json).Packages[0].CertificateStore | Should -Be Root
            New-Item -ItemType Directory -Path $target | Out-Null
            Mock Get-OSDAppCachePath {$cache}
            Add-OSDApp -Name TestRootCA -WindowsPath $target -SkipCacheRefresh | Out-Null
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $stage=Join-Path $target 'Windows\Temp\OSDApps'
            (Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json).Apps[0].CertificateStore | Should -Be Root
            Add-Content (Join-Path $stage 'Packages\TestRootCA\Package.zip') 'tampered'
            {Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure} | Should -Throw
            $catalog=Get-Content (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            $catalog.Packages[0].CertificateStore='My'
            $catalog | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8
            @(Test-OSDAppRepositoryCache -CachePath $cache)[0].Valid | Should -BeFalse
        }
    }
    It 'rejects scripts and disguised private keys before building' {
        $source=Join-Path $TestDrive 'InvalidSource'
        New-Item -ItemType Directory -Path $source | Out-Null
        Copy-Item (Join-Path $script:source 'root.cer') $source
        Set-Content (Join-Path $source 'Install.ps1') 'throw "must never run"'
        {New-OSDAppPackage -Id Bad -Version 1.0.0 -PackageType Certificate -SourcePath $source -OutputPath (Join-Path $TestDrive 'BadBuild')} | Should -Throw '*only public*'
        Remove-Item (Join-Path $source 'Install.ps1')
        [IO.File]::WriteAllBytes((Join-Path $source 'key.cer'),$script:ca.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,'fixture-password'))
        {New-OSDAppPackage -Id Bad -Version 1.0.0 -PackageType Certificate -SourcePath $source -OutputPath (Join-Path $TestDrive 'BadBuild')} | Should -Throw '*PFX*'
    }
    It 'stages only certificate packages through the Id interface and respects WhatIf' {
        InModuleScope OSDApps {
            Mock Get-OSDApp {[pscustomobject]@{Id='TestRootCA';Source='Repository';PackageType='Certificate'}}
            Mock Add-OSDApp {[pscustomobject]@{Id='TestRootCA';PackageType='Certificate'}}
            (Add-OSDAppCertificate -Id TestRootCA -SkipCacheRefresh).PackageType | Should -Be Certificate
            Should -Invoke Add-OSDApp -Times 1 -Exactly -ParameterFilter {$Name -eq 'TestRootCA' -and $SkipCacheRefresh}
            Add-OSDAppCertificate -Id TestRootCA -WhatIf
            Should -Invoke Add-OSDApp -Times 1 -Exactly
            Mock Get-OSDApp {[pscustomobject]@{Id='TestRootCA';Source='Repository';PackageType='App'}}
            {Add-OSDAppCertificate -Id TestRootCA} | Should -Throw '*not Certificate*'
            {Add-OSDAppCertificate -Id TestRootCA -Store Root} | Should -Throw
        }
    }
    It 'validates the whole payload before importing its first valid certificate' {
        $payload=Join-Path $TestDrive 'InvalidPayload'
        New-Item -ItemType Directory -Path $payload | Out-Null
        Copy-Item (Join-Path $script:source 'root.cer') (Join-Path $payload 'a.cer')
        Set-Content (Join-Path $payload 'z.cer') 'invalid'
        Mock Install-OSDAppPublicCertificate {throw 'must not import'}
        $resultPath=Join-Path $TestDrive 'InvalidResult.json'
        (Invoke-OSDAppCertificatePackage -PayloadRoot $payload -PackageId TestRootCA -Store Root -DeploymentId 'test' -ResultPath $resultPath).ExitCode | Should -Be 1
        Should -Invoke Install-OSDAppPublicCertificate -Times 0 -Exactly
        $report=Get-Content $resultPath -Raw | ConvertFrom-Json
        $report.Status | Should -Be Failed
        $report.OperationCount | Should -Be 0
        $report.RestartNeeded | Should -BeFalse
    }
    It 'runs a real repository ZIP through the one-shot runner into the machine CA store' {
        $stage=Join-Path $TestDrive 'RuntimeStage'
        $packageRoot=Join-Path $stage 'Packages\TestRootCA'
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        Copy-Item $script:package.PackagePath (Join-Path $packageRoot 'Package.zip')
        $resultPath=Join-Path $TestDrive 'RuntimeResults\Latest.json'
        @{
            SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid
            Runtime=@{CleanupMode='Never';CacheVolumeLabel='OSDCloud';LogPath=(Join-Path $TestDrive 'Runtime.log');ResultPath=$resultPath}
            Apps=@(@{Id='TestRootCA';DisplayName='Test Root CA';Source='Repository';Type='RepositoryPackage';PackageType='Certificate';CertificateStore='CA';Version='1.0.0';Architecture='any';Archive=@{Sha256=$script:package.Sha256};SuccessCodes=@(0)})
        } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
        $target=[Security.Cryptography.X509Certificates.X509Store]::new('CA',[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
        try {
            $target.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:root 'Runtime\Invoke-OSDAppRunner.ps1') -StagedPath $stage
            $LASTEXITCODE | Should -Be 0
            (Get-Content $resultPath -Raw | ConvertFrom-Json).Status | Should -Be Succeeded
            $report=Get-Content (Join-Path $TestDrive 'RuntimeResults\Certificate-TestRootCA-Result.json') -Raw | ConvertFrom-Json
            $report.Items[0].Outcome | Should -Be Imported
            $report.Items[0].Store | Should -Be 'LocalMachine\CA'
            $target.Certificates.Find([Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,$script:ca.Thumbprint,$false).Count | Should -Be 1
        }
        finally { $target.Remove($script:ca);$target.Close();$target.Dispose() }
    }
    It 'reports machine import outcomes without certificate content' {
        Mock Install-OSDAppPublicCertificate {'Imported'}
        $resultPath=Join-Path $TestDrive 'GoodResult.json'
        (Invoke-OSDAppCertificatePackage -PayloadRoot $script:source -PackageId TestRootCA -Store Root -DeploymentId 'test' -ResultPath $resultPath).ExitCode | Should -Be 0
        $raw=Get-Content $resultPath -Raw
        $report=$raw | ConvertFrom-Json
        $report.OperationCount | Should -Be 1
        $report.Items[0].Store | Should -Be 'LocalMachine\Root'
        $report.Items[0].Outcome | Should -Be Imported
        $raw | Should -Not -Match ([regex]::Escape([Convert]::ToBase64String($script:ca.RawData)))
        Mock Install-OSDAppPublicCertificate {throw 'fixture import failure'}
        (Invoke-OSDAppCertificatePackage -PayloadRoot $script:source -PackageId TestRootCA -Store Root -DeploymentId 'test' -ResultPath $resultPath).ExitCode | Should -Be 1
        (Get-Content $resultPath -Raw | ConvertFrom-Json).FailedOperationCount | Should -Be 1
    }
}
