Describe 'One-shot Wi-Fi profile staging' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        $script:xml='<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>FixtureWiFi</name><SSIDConfig><SSID><name>FixtureWiFi</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>Synthetic-Key-123</keyMaterial></sharedKey></security></MSM></WLANProfile>'
        $runtime=Join-Path $script:root 'Runtime\Invoke-OSDAppWiFiProfiles.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($runtime,[ref]$tokens,[ref]$errors)
        if(@($errors).Count){throw 'Wi-Fi runtime parser errors.'}
        foreach($name in @('Initialize-OSDAppWiFiNative','Import-OSDAppWiFiNativeProfile','Invoke-OSDAppWiFiProfileOperation')){
            $def=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
            . ([scriptblock]::Create($def.Extent.Text))
        }
    }
    BeforeEach {
        Set-OSDAppConfiguration -EnableBuiltIns $true -CleanupMode Never
        $script:profile=Join-Path $TestDrive 'profile.xml'
        $script:xml | Set-Content -LiteralPath $script:profile -Encoding UTF8
    }
    It 'compiles the native WLAN binding without accessing a WLAN interface' {
        Initialize-OSDAppWiFiNative
        ('OSDApps.WiFiNative' -as [type]) | Should -Not -BeNullOrEmpty
    }
    It 'rejects machine-protected credentials, enterprise and unsafe XML before staging' {
        & (Get-Module OSDApps) {param($file) (Read-OSDAppWiFiProfile -LiteralPath $file).Name} $script:profile | Should -Be FixtureWiFi
        foreach($invalid in @(
            $script:xml.Replace('<protected>false','<protected>true'),
            $script:xml.Replace('WPA2PSK','WPA2'),
            ('<!DOCTYPE WLANProfile [<!ENTITY x SYSTEM "file:///not-read">]>'+$script:xml),
            '<not-xml>')) {
            $invalid | Set-Content -LiteralPath $script:profile -Encoding UTF8
            { & (Get-Module OSDApps) {param($file) Read-OSDAppWiFiProfile -LiteralPath $file} $script:profile } | Should -Throw
        }
    }
    It 'stages one integrity-checked entry, replaces a same-name profile and restricts credential access' {
        InModuleScope OSDApps -Parameters @{Profile=$script:profile} {
            param($Profile)
            Mock Test-OSDAppWinPE {$true}
            $target=Join-Path $TestDrive 'offline'
            New-Item -ItemType Directory -Path $target | Out-Null
            $first=Add-OSDAppWiFiProfile -Path $Profile -WindowsPath $target
            $last=Add-OSDAppWiFiProfile -Path $Profile -WindowsPath $target
            $last.OperationCount | Should -Be 1
            ($last | ConvertTo-Json -Depth 10) | Should -Not -Match 'Synthetic-Key'
            $config=Join-Path $last.StagedPath 'config.json'
            $acl=Get-Acl -LiteralPath $last.StagedPath
            $acl.AreAccessRulesProtected | Should -BeTrue
            $rules=@($acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]))
            @($rules.IdentityReference.Value | Sort-Object) | Should -Be @('S-1-5-18','S-1-5-32-544')
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            Add-Content -LiteralPath $config -Value 'tampered'
            {Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure} | Should -Throw
            {Add-OSDAppWiFiProfile -Path $Profile -WindowsPath $target} | Should -Throw '*not an intact*'
        }
    }
    It 'honors WhatIf without staging credentials' {
        InModuleScope OSDApps -Parameters @{Profile=$script:profile} {
            param($Profile)
            Mock Test-OSDAppWinPE {$true}
            $target=Join-Path $TestDrive 'whatif'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDAppWiFiProfile -Path $Profile -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps') | Should -BeFalse
        }
    }
    It 'reports partial interface failures and omits credentials' {
        Mock Import-OSDAppWiFiNativeProfile {
            [pscustomobject]@{InterfaceId='one';ErrorCode=0;ReasonCode=0}
            [pscustomobject]@{InterfaceId='two';ErrorCode=87;ReasonCode=123}
        }
        $result=Invoke-OSDAppWiFiProfileOperation -Operation ([pscustomobject]@{Name='FixtureWiFi';Xml=$script:xml})
        $result.Status | Should -Be Failed
        $result.Interfaces.Count | Should -Be 2
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'Synthetic-Key|keyMaterial'
    }
    It 'sanitizes native exceptions including credential-bearing error text' {
        Mock Import-OSDAppWiFiNativeProfile {throw 'Synthetic-Key-123'}
        $result=Invoke-OSDAppWiFiProfileOperation -Operation ([pscustomobject]@{Name='FixtureWiFi';Xml=$script:xml})
        $result.Status | Should -Be Failed
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'Synthetic-Key'
    }
    It 'consumes credential staging in a failing runtime without requesting a reboot' {
        $config=Join-Path $TestDrive 'config.json'
        $resultPath=Join-Path $TestDrive 'result.json'
        @{SchemaVersion=1;DeploymentId=[guid]::NewGuid().ToString();ResultPath=$resultPath;Operations=@(@{Name='FixtureWiFi';Xml=$script:xml})} | ConvertTo-Json -Depth 10 | Set-Content $config -Encoding UTF8
        $wrapper=Join-Path $TestDrive 'run.ps1'
        @'
param($Runtime,$Config)
function Get-Service {param($Name) throw 'Synthetic-Key-123 service unavailable'}
& $Runtime -ConfigPath $Config
exit $LASTEXITCODE
'@ | Set-Content $wrapper -Encoding UTF8
        $exe=(Get-Process -Id $PID).Path
        & $exe -NoProfile -File $wrapper -Runtime (Join-Path $script:root 'Runtime\Invoke-OSDAppWiFiProfiles.ps1') -Config $config | Out-Null
        $LASTEXITCODE | Should -Be 1
        Test-Path $config | Should -BeFalse
        $report=Get-Content $resultPath -Raw
        $report | Should -Not -Match 'Synthetic-Key|keyMaterial'
        ($report | ConvertFrom-Json).RestartNeeded | Should -BeFalse
        ($report | ConvertFrom-Json).Status | Should -Be Failed
    }
}
