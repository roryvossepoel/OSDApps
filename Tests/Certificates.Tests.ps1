Describe 'One-shot public certificate staging' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        $script:ca=New-SelfSignedCertificate -Type Custom -Subject 'CN=OSDApps CI Test CA' -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -KeyUsage CertSign,CRLSign -TextExtension @('2.5.29.19={critical}{text}ca=1') -NotAfter (Get-Date).AddDays(1)
        $script:leaf=New-SelfSignedCertificate -Subject 'OSDApps-CI-Leaf' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddDays(1)
        $script:intermediate=New-SelfSignedCertificate -Type Custom -Subject 'CN=OSDApps CI Intermediate' -Signer $script:ca -CertStoreLocation 'Cert:\CurrentUser\My' -KeyUsage CertSign,CRLSign -TextExtension @('2.5.29.19={critical}{text}ca=1') -NotAfter (Get-Date).AddHours(12)
        $script:file=Join-Path $TestDrive 'ca.cer'
        Export-Certificate -Cert $script:ca -FilePath $script:file | Out-Null
        $runtime=Join-Path $script:root 'Runtime\OSDAppCertificate.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$tokens,[ref]$errors)
        if(@($errors).Count){throw 'Certificate runtime parser errors.'}
        foreach($name in @('ConvertFrom-OSDAppCertificateOperation','Install-OSDAppPublicCertificate','Invoke-OSDAppCertificateOperation')){
            $def=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
            . ([scriptblock]::Create($def.Extent.Text))
        }
        $script:operation=& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store Root} $script:file
    }
    AfterAll {
        foreach($cert in @($script:intermediate,$script:leaf,$script:ca)) {
            if($cert){Remove-Item -LiteralPath ('Cert:\CurrentUser\My\'+$cert.Thumbprint) -DeleteKey -ErrorAction SilentlyContinue}
        }
    }
    BeforeEach { Set-OSDAppConfiguration -EnableBuiltIns $true -CleanupMode Never }
    It 'reads a public DER CA and emits its exact identity' {
        $script:operation.Thumbprint | Should -Be $script:ca.Thumbprint
        $script:operation.Store | Should -Be Root
        $cert=ConvertFrom-OSDAppCertificateOperation -Operation $script:operation
        try { $cert.HasPrivateKey | Should -BeFalse } finally { $cert.Dispose() }
    }
    It 'accepts a single PEM certificate but rejects PEM bundles and extra key content' {
        $file=Join-Path $TestDrive 'ca.crt'
        $pem="-----BEGIN CERTIFICATE-----`n"+[Convert]::ToBase64String($script:ca.RawData)+"`n-----END CERTIFICATE-----`n"
        $pem | Set-Content $file -Encoding Ascii
        $op=& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store Root} $file
        $op.Thumbprint | Should -Be $script:ca.Thumbprint
        foreach($invalid in @(($pem+$pem),($pem+'-----BEGIN PRIVATE KEY-----'))) {
            $invalid | Set-Content $file -Encoding Ascii
            {& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store Root} $file} | Should -Throw
        }
    }
    It 'rejects a disguised PFX before constructing a certificate with a private key' {
        $file=Join-Path $TestDrive 'disguised.cer'
        [IO.File]::WriteAllBytes($file,$script:ca.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,'fixture-password'))
        {& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store Root} $file} | Should -Throw '*PFX*'
    }
    It 'rejects leaf certificates and intermediate CAs in Root' {
        $file=Join-Path $TestDrive 'wrong.cer'
        Export-Certificate -Cert $script:leaf -FilePath $file | Out-Null
        {& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store CA} $file} | Should -Throw '*CA basic constraint*'
        Export-Certificate -Cert $script:intermediate -FilePath $file -Force | Out-Null
        {& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store Root} $file} | Should -Throw '*self-issued*'
        $op=& (Get-Module OSDApps) {param($file) Read-OSDAppCertificate -LiteralPath $file -Store CA} $file
        $op.Thumbprint | Should -Be $script:intermediate.Thumbprint
    }
    It 'stages one entry, deduplicates by thumbprint and store, and detects tampering' {
        InModuleScope OSDApps -Parameters @{File=$script:file} {
            param($File)
            Mock Test-OSDAppWinPE {$true}
            $target=Join-Path $TestDrive 'offline'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDAppCertificate -Path @($File,$File) -Store Root -WindowsPath $target | Out-Null
            $last=Add-OSDAppCertificate -Path $File -Store CA -WindowsPath $target
            $last.OperationCount | Should -Be 2
            $last=Add-OSDAppCertificate -Path $File -Store Root -WindowsPath $target
            $last.OperationCount | Should -Be 2
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $ready.AppCount | Should -Be 1
            Add-Content -LiteralPath (Join-Path $last.StagedPath 'config.json') -Value 'tampered'
            {Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure} | Should -Throw
            {Add-OSDAppCertificate -Path $File -Store Root -WindowsPath $target} | Should -Throw '*not an intact*'
        }
    }
    It 'honors WhatIf and refuses staging on the preparation PC' {
        InModuleScope OSDApps -Parameters @{File=$script:file} {
            param($File)
            Mock Test-OSDAppWinPE {$false}
            {Add-OSDAppCertificate -Path $File -Store Root} | Should -Throw '*WinPE*'
            Mock Test-OSDAppWinPE {$true}
            $target=Join-Path $TestDrive 'whatif'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDAppCertificate -Path $File -Store Root -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps') | Should -BeFalse
        }
    }
    It 'reports import and already-present outcomes without embedding certificate content' {
        Mock Install-OSDAppPublicCertificate {'Imported'}
        $result=Invoke-OSDAppCertificateOperation -Operation $script:operation
        $result.Outcome | Should -Be Imported
        $result.Store | Should -Be 'LocalMachine\Root'
        $result.Thumbprint | Should -Be $script:ca.Thumbprint
        ($result | ConvertTo-Json) | Should -Not -Match ([regex]::Escape($script:operation.Certificate))
        Mock Install-OSDAppPublicCertificate {'AlreadyPresent'}
        (Invoke-OSDAppCertificateOperation -Operation $script:operation).Outcome | Should -Be AlreadyPresent
    }
    It 'imports into the real machine stores once and reports an existing certificate on repeat' {
        $publicCert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($script:ca.RawData)
        foreach($store in @('Root','CA')) {
            $target=[Security.Cryptography.X509Certificates.X509Store]::new($store,[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
            try {
                $target.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                # This certificate was generated uniquely for this test run.
                Install-OSDAppPublicCertificate -Certificate $publicCert -Store $store | Should -Be Imported
                Install-OSDAppPublicCertificate -Certificate $publicCert -Store $store | Should -Be AlreadyPresent
                $found=$target.Certificates.Find([Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,$script:ca.Thumbprint,$false)
                $found.Count | Should -Be 1
            }
            finally {
                $target.Remove($script:ca)
                $target.Close();$target.Dispose()
            }
        }
        $publicCert.Dispose()
    }
    It 'blocks a mismatched identity or unsupported store before importing' {
        Mock Install-OSDAppPublicCertificate {throw 'Should not be reached'}
        $op=$script:operation.PSObject.Copy()
        $op.Thumbprint='0'*40
        {Invoke-OSDAppCertificateOperation -Operation $op} | Should -Throw '*identity mismatch*'
        $op=$script:operation.PSObject.Copy();$op.Store='My'
        {Invoke-OSDAppCertificateOperation -Operation $op} | Should -Throw '*Unsupported*'
        Should -Invoke Install-OSDAppPublicCertificate -Times 0 -Exactly
    }
    It 'validates all operations before trust changes and writes a failing one-shot report' {
        $config=Join-Path $TestDrive 'invalid-config.json'
        $resultPath=Join-Path $TestDrive 'result.json'
        $invalid=$script:operation.PSObject.Copy();$invalid.Store='Invalid'
        @{SchemaVersion=1;DeploymentId=[guid]::NewGuid().ToString();ResultPath=$resultPath;Operations=@($script:operation,$invalid)} | ConvertTo-Json -Depth 10 | Set-Content $config -Encoding UTF8
        $exe=(Get-Process -Id $PID).Path
        & $exe -NoProfile -File (Join-Path $script:root 'Runtime\Invoke-OSDAppCertificates.ps1') -ConfigPath $config | Out-Null
        $LASTEXITCODE | Should -Be 1
        $report=Get-Content $resultPath -Raw | ConvertFrom-Json
        $report.Status | Should -Be Failed
        $report.OperationCount | Should -Be 0
        $report.RestartNeeded | Should -BeFalse
    }
}
