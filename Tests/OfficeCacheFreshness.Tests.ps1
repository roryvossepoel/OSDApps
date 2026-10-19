Describe 'Office cache freshness decisions' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $root 'Runtime/Test-OSDAppOfficeCacheCompatibility.ps1')
        . (Join-Path $root 'Private/New-OSDAppOfficeConfiguration.ps1')
        function New-FreshnessFixture {
            param([string]$Channel='MonthlyEnterprise', [string]$Architecture='x64', [string]$Version='')
            New-OSDAppOfficeConfiguration -Path $config -Channel $Channel -Architecture $Architecture
            if ($Version) {
                [xml]$xml = Get-Content $config -Raw
                $xml.Configuration.Add.SetAttribute('Version',$Version)
                $xml.Save($config)
            }
            $profile = Get-OSDAppOfficePayloadProfile -Path $config
            @{ Version='16.0.20430.20180'; Architecture=$Architecture; PayloadProfile=$profile } |
                ConvertTo-Json -Depth 30 | Set-Content (Join-Path $cache 'CacheInfo.json')
        }
    }
    BeforeEach {
        Set-StrictMode -Version Latest
        $cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $data = Join-Path $cache 'Office/Data'
        New-Item $data -ItemType Directory -Force | Out-Null
        $config = Join-Path $cache 'configuration.xml'
        Set-Content (Join-Path $data 'v64.cab') 'descriptor'
        Set-Content (Join-Path $data 'v32.cab') 'descriptor'
        New-FreshnessFixture
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value descriptor }
    }
    It 'uses the selected <Channel> descriptor without touching the cache' -ForEach @(
        @{Channel='Current'; Guid='492350f6-3a01-4f97-b9c0-c7c6ddf67d60'}
        @{Channel='MonthlyEnterprise'; Guid='55336b82-a18d-4dd6-b5f6-9e5095c314a6'}
        @{Channel='SemiAnnual'; Guid='7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'}
        @{Channel='CurrentPreview'; Guid='64256afe-f5d9-4f86-8936-8840a6a4f5be'}
        @{Channel='SemiAnnualPreview'; Guid='b8f9b850-328d-4355-9145-c59439a0c4cf'}
        @{Channel='BetaChannel'; Guid='5440fd1f-7ecb-4221-8110-145efaa6372f'}
    ) {
        New-FreshnessFixture -Channel $Channel
        $before = (Get-FileHash (Join-Path $data 'v64.cab')).Hash
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeTrue
        Should -Invoke Invoke-WebRequest -Exactly 1 -ParameterFilter { $Uri -eq "https://officecdn.microsoft.com/pr/$Guid/Office/Data/v64.cab" -and $TimeoutSec -eq 30 }
        (Get-FileHash (Join-Path $data 'v64.cab')).Hash | Should -Be $before
    }
    It 'checks v32 for x86' {
        New-FreshnessFixture -Architecture x86
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeTrue
        Should -Invoke Invoke-WebRequest -Exactly 1 -ParameterFilter { $Uri -like '*/v32.cab' }
    }
    It 'requires acquisition for a changed descriptor' {
        Mock Invoke-WebRequest { Set-Content $OutFile 'new descriptor' }
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeFalse
    }
    It 'accepts an exact build pin without querying the current channel' {
        New-FreshnessFixture -Version '16.0.20430.20180'
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeTrue
        Should -Invoke Invoke-WebRequest -Exactly 0
    }
    It 'rejects a mismatched pin without querying the channel' {
        New-FreshnessFixture -Version '16.0.20430.20146'
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Exactly 0
    }
    It 'does not equate a custom download source with the public CDN' {
        [xml]$xml = Get-Content $config -Raw
        $xml.Configuration.Add.SetAttribute('DownloadPath','C:\CustomSource')
        $xml.Save($config)
        $info = Get-Content (Join-Path $cache 'CacheInfo.json') -Raw | ConvertFrom-Json
        $info.PayloadProfile = Get-OSDAppOfficePayloadProfile -Path $config
        $info | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $cache 'CacheInfo.json')
        Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Exactly 0
    }
    It 'removes temporary metadata after a failed request and propagates the failure' {
        Mock Invoke-WebRequest {
            $script:probePath = $OutFile
            Set-Content $OutFile 'partial'
            throw 'Connection failed.'
        }
        { Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config } | Should -Throw '*Connection failed*'
        Test-Path $script:probePath | Should -BeFalse
    }
    It 'does not silently accept an empty response' {
        Mock Invoke-WebRequest { [IO.File]::WriteAllBytes($OutFile, [byte[]]@()) }
        { Test-OSDAppOfficeCacheCurrent -OfficeRoot $cache -ConfigurationPath $config } | Should -Throw '*empty version descriptor*'
    }
}
