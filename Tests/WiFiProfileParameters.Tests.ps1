Describe 'Wi-Fi profiles generated from parameters' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }
    It 'round-trips XML metacharacters in SSID, profile name and password without injection' {
        InModuleScope OSDApps {
            $password='Example<&>"''123'
            $definition=New-OSDAppWiFiProfileDefinition -SSID 'Net<&>"' -ProfileName 'Profile<&>' -Security WPA2Personal -Password $password
            [xml]$doc=$definition.Xml
            $doc.WLANProfile.name | Should -Be 'Profile<&>'
            $doc.WLANProfile.SSIDConfig.SSID.name | Should -Be 'Net<&>"'
            $doc.WLANProfile.MSM.security.sharedKey.keyMaterial | Should -Be $password
            @($doc.WLANProfile.MSM.security.sharedKey).Count | Should -Be 1
            $doc.WLANProfile.NamespaceURI | Should -Be 'http://www.microsoft.com/networking/WLAN/profile/v1'
            $doc.WLANProfile.connectionMode | Should -Be auto
            $doc.WLANProfile.SSIDConfig.nonBroadcast | Should -Be false
        }
    }
    It 'generates WPA3 SAE with manual connection and hidden-network discovery' {
        InModuleScope OSDApps {
            $definition=New-OSDAppWiFiProfileDefinition -SSID 'FixtureWiFi' -Security WPA3Personal -Password 'ExampleOnly123!' -ConnectionMode Manual -Hidden
            [xml]$doc=$definition.Xml
            $definition.Name | Should -Be FixtureWiFi
            $doc.WLANProfile.MSM.security.authEncryption.authentication | Should -Be WPA3SAE
            $doc.WLANProfile.MSM.security.authEncryption.encryption | Should -Be AES
            $doc.WLANProfile.connectionMode | Should -Be manual
            $doc.WLANProfile.SSIDConfig.nonBroadcast | Should -Be true
        }
    }
    It 'generates open profiles without a shared key and rejects any supplied password' {
        InModuleScope OSDApps {
            [xml]$doc=(New-OSDAppWiFiProfileDefinition -SSID Guest -Security Open).Xml
            $doc.WLANProfile.MSM.security.authEncryption.authentication | Should -Be open
            $doc.WLANProfile.MSM.security.authEncryption.encryption | Should -Be none
            $doc.WLANProfile.MSM.security.sharedKey | Should -BeNullOrEmpty
            {New-OSDAppWiFiProfileDefinition -SSID Guest -Security Open -Password ''} | Should -Throw '*do not accept Password*'
        }
    }
    It 'accepts SecureString input and produces the same profile as a literal password' {
        InModuleScope OSDApps {
            $secure=ConvertTo-SecureString 'ExampleOnly123!' -AsPlainText -Force
            $a=New-OSDAppWiFiProfileDefinition -SSID Test -Security WPA2Personal -Password $secure
            $b=New-OSDAppWiFiProfileDefinition -SSID Test -Security WPA2Personal -Password 'ExampleOnly123!'
            $a.Xml | Should -Be $b.Xml
        }
    }
    It 'enforces SSID byte length and preserves UTF-8 network identity' {
        InModuleScope OSDApps {
            $ssid=([string][char]0xE9)*16
            [xml]$doc=(New-OSDAppWiFiProfileDefinition -SSID $ssid -Security Open).Xml
            $doc.WLANProfile.SSIDConfig.SSID.hex | Should -Be ('C3A9'*16)
            {New-OSDAppWiFiProfileDefinition -SSID ($ssid+'a') -Security Open} | Should -Throw '*32 UTF-8 bytes*'
            {New-OSDAppWiFiProfileDefinition -SSID "Test`nNetwork" -Security Open} | Should -Throw
            {New-OSDAppWiFiProfileDefinition -SSID Test -ProfileName '' -Security Open} | Should -Throw
        }
    }
    It 'rejects invalid passphrases with errors that do not repeat their contents' {
        InModuleScope OSDApps {
            foreach($password in @('short',('x'*64),"ValidLength`nSecret")) {
                $message=$null
                try {New-OSDAppWiFiProfileDefinition -SSID Test -Security WPA2Personal -Password $password | Out-Null}
                catch {$message=$_.Exception.Message}
                $message | Should -Be 'Password must contain 8 to 63 printable ASCII characters.'
                $message.Contains($password) | Should -BeFalse
            }
            {New-OSDAppWiFiProfileDefinition -SSID Test -Security WPA3Personal} | Should -Throw '*require Password*'
        }
    }
    It 'keeps generated and file-based input in separate parameter sets' {
        $command=Get-Command Add-OSDAppWiFiProfile -Module OSDApps
        $file=@($command.ParameterSets | Where-Object Name -eq File)[0]
        $settings=@($command.ParameterSets | Where-Object Name -eq Settings)[0]
        $file.Parameters.Name | Should -Contain Path
        $file.Parameters.Name | Should -Not -Contain SSID
        $settings.Parameters.Name | Should -Contain SSID
        $settings.Parameters.Name | Should -Not -Contain Path
    }
    It 'stages generated intent through the existing transaction and merges an XML input' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE {$true}
            Set-OSDAppConfiguration -EnableBuiltIns $true
            $target=Join-Path $TestDrive 'generated'
            New-Item -ItemType Directory -Path $target | Out-Null
            $result=Add-OSDAppWiFiProfile -SSID 'FixtureWiFi' -Security WPA2Personal -Password 'ExampleOnly123!' -WindowsPath $target
            ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'ExampleOnly|keyMaterial'
            $config=Get-Content (Join-Path $result.StagedPath 'config.json') -Raw | ConvertFrom-Json
            [xml]$doc=$config.Operations[0].Xml
            $doc.WLANProfile.MSM.security.sharedKey.keyMaterial | Should -Be 'ExampleOnly123!'
            $export=Join-Path $TestDrive 'export.xml'
            $config.Operations[0].Xml | Set-Content -LiteralPath $export -Encoding UTF8
            $last=Add-OSDAppWiFiProfile -Path $export -WindowsPath $target
            $last.OperationCount | Should -Be 1
            (Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure).OfflineReady | Should -BeTrue
            $last=Add-OSDAppWiFiProfile -SSID Guest -Security Open -WindowsPath $target
            $last.OperationCount | Should -Be 2
        }
    }
    It 'does not create staging for invalid input or WhatIf' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE {$true}
            Set-OSDAppConfiguration -EnableBuiltIns $true
            $target=Join-Path $TestDrive 'unchanged'
            New-Item -ItemType Directory -Path $target | Out-Null
            {Add-OSDAppWiFiProfile -SSID Test -Security Open -Password 'ExampleOnly123!' -WindowsPath $target} | Should -Throw
            Add-OSDAppWiFiProfile -SSID Test -Security Open -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps') | Should -BeFalse
        }
    }
}
