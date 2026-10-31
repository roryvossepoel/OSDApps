Describe 'Office payload configuration compatibility' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'Runtime\Test-OSDStageOfficeCacheCompatibility.ps1')
        . (Join-Path $root 'Private\New-OSDStageOfficeConfiguration.ps1')
        $runtimeAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime\Invoke-OSDStagePreInstall.ps1'), [ref]$null, [ref]$null)
        foreach ($name in @('Test-OfficeCacheGeneration','Test-LocalOfficeSource','Copy-DirectoryReplace','Copy-OfficeCachePayload')) {
            $node = $runtimeAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            . ([scriptblock]::Create($node.Extent.Text))
        }
        function Write-PreInstallLog { param($Event,$Level,$Message,$Data) }
        # Exercise the real Office switch body with controlled network/download
        # outcomes; no installers, network requests or production cache changes.
        $runtime = Get-Content (Join-Path $root 'Runtime\Invoke-OSDStagePreInstall.ps1') -Raw
        $start = $runtime.IndexOf("'Microsoft365Apps' {") + "'Microsoft365Apps' {".Length
        $end = $runtime.IndexOf("'MicrosoftTeams' {", $start)
        $body = $runtime.Substring($start, $end - $start).Trim()
        $body = $body.Substring(0, $body.LastIndexOf('}'))
        $wrapper = @'
function Invoke-OfficePreInstallTest {
    param([string]$StagedPath, [bool]$NetworkAvailable, [string]$UsbRoot)
    $acquisition = @{}
    foreach ($app in @([pscustomobject]@{ Architecture='x64'; OfficeDeploymentToolUri='https://example.invalid/setup.exe' })) {
__BODY__
    }
    return $acquisition
}
'@
        . ([scriptblock]::Create($wrapper.Replace('__BODY__', $body)))
        function Restore-PreInstallBuiltInCache { param($Root,$Id) }
        function Assert-OSDStageTransactionSpace { param($Path,$ExistingPath,$MinimumFreeSpaceGB,$Operation) }
        function Save-PreInstallDownload { param($Uri,$DestinationPath,$Id,$Description,$TimeoutMinutes) throw 'Simulated download failure.' }
        function Assert-PreInstallSignedPayload { param($Id,$Path) }
        function Set-PreInstallAcquisitionResult { param($Result,$Outcome,$RefreshError) $Result.Outcome=$Outcome }

        function New-CompatibilityFixture {
            param([string]$Path, [hashtable]$Options=@{})
            $data = Join-Path $Path 'Office\Data'
            $version = '16.0.20430.20180'
            $payload = Join-Path $data $version
            New-Item -ItemType Directory -Path $payload -Force | Out-Null
            $config = Join-Path $Path 'configuration.xml'
            New-OSDStageOfficeConfiguration -Path $config @Options
            $profile = Get-OSDStageOfficePayloadProfile -Path $config
            $prefix = if ($profile.Architecture -eq 'x86') { 'v32' } else { 'v64' }
            Set-Content (Join-Path $Path 'setup.exe') 'setup'
            Set-Content (Join-Path $payload 'payload.dat') 'payload'
            Set-Content (Join-Path $data "$prefix.cab") 'cab'
            Set-Content (Join-Path $data ("{0}_{1}.cab" -f $prefix,$version)) 'cab'
            $info = [ordered]@{ Version=$version; Architecture=$profile.Architecture }
            $info.PayloadProfile = $profile
            $info | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $Path 'CacheInfo.json')
        }
    }

    BeforeEach {
        Mock Test-OSDStageOfficeCacheCurrent { $false }
        Set-StrictMode -Version Latest
        $cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $desired = Join-Path $TestDrive 'desired.xml'
        New-CompatibilityFixture -Path $cache
    }

    It 'rejects a changed <Label> even when the Office build is unchanged' -ForEach @(
        @{Label='channel'; Options=@{Channel='MonthlyEnterprise'}; Reason='channel'}
        @{Label='architecture'; Options=@{Architecture='x86'}; Reason='architecture'}
        @{Label='language'; Options=@{Language=@('en-us','nl-nl')}; Reason='languages'}
        @{Label='product'; Options=@{ProductId='O365BusinessRetail'}; Reason='products'}
        @{Label='Visio selection'; Options=@{IncludeVisio=$true}; Reason='products'}
        @{Label='Project selection'; Options=@{IncludeProject=$true}; Reason='products'}
        @{Label='exclusion'; Options=@{ExcludeApp=@('Access')}; Reason='download settings'}
    ) {
        New-OSDStageOfficeConfiguration -Path $desired @Options
        $result = Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired
        $result.Compatible | Should -BeFalse
        ($result.Reasons -join ' ') | Should -Match $Reason
        Test-LocalOfficeSource -Root $cache -ConfigurationPath $desired | Should -BeFalse
    }

    It 'allows licensing and update changes without changing payload eligibility' {
        New-OSDStageOfficeConfiguration -Path $desired -SharedComputerLicensing $true -UpdatesEnabled $false -AcceptEula $false
        (Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired).Compatible | Should -BeTrue
        Test-LocalOfficeSource -Root $cache -ConfigurationPath $desired | Should -BeTrue
    }

    It 'normalizes attribute order and known ID casing without including SourcePath' {
        '<Configuration><Add SourcePath="D:\Different" Channel="current" OfficeClientEdition="64"><Product ID="o365proplusretail"><Language ID="EN-US" /></Product></Add></Configuration>' | Set-Content $desired
        (Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired).Compatible | Should -BeTrue
    }

    It 'requires a pinned version to match the actual cached build' {
        New-OSDStageOfficeConfiguration -Path $desired
        [xml]$xml = Get-Content $desired -Raw
        $xml.Configuration.Add.SetAttribute('Version','16.0.20430.20180')
        $xml.Save($desired)
        (Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired).Compatible | Should -BeTrue
        $xml.Configuration.Add.SetAttribute('Version','16.0.20430.20146')
        $xml.Save($desired)
        (Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired).Compatible | Should -BeFalse
    }

    It 'rejects dynamic and implicit configuration for fallback' -ForEach @(
        @{Xml='<Configuration><Add OfficeClientEdition="64" Channel="Current"><Product ID="O365ProPlusRetail"><Language ID="MatchOS" /></Product></Add></Configuration>'}
        @{Xml='<Configuration><Add><Product ID="O365ProPlusRetail"><Language ID="en-us" /></Product></Add></Configuration>'}
    ) {
        $Xml | Set-Content $desired
        $result = Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired
        $result.Compatible | Should -BeFalse
        ($result.Reasons -join ' ') | Should -Match 'Dynamic or implicit'
    }

    It 'rejects malformed metadata and DTD input without leaking XML content' {
        '<!DOCTYPE Configuration [<!ENTITY secret "private-value">]><Configuration>&secret;</Configuration>' | Set-Content $desired
        $result = Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired
        $result.Compatible | Should -BeFalse
        ($result.Reasons -join ' ') | Should -Not -Match 'private-value'
        New-OSDStageOfficeConfiguration -Path $desired
        '{}' | Set-Content (Join-Path $cache 'CacheInfo.json')
        (Test-OSDStageOfficeCacheCompatibility -OfficeRoot $cache -ConfigurationPath $desired).Compatible | Should -BeFalse
    }

    It 'uses matching fallback but stops on mismatched languages when network availability is <Online>' -ForEach @(
        @{Online=$false; Outcome='OfflineCacheUsed'}
        @{Online=$true; Outcome='FallbackCacheUsed'}
    ) {
        $stage = Join-Path $TestDrive ('Runtime-' + $Online)
        $local = Join-Path $stage 'BuiltIn\Microsoft365Apps'
        New-CompatibilityFixture -Path $local
        $config = Join-Path $local 'configuration.xml'
        New-OSDStageOfficeConfiguration -Path $config -SharedComputerLicensing $true
        $before = (Get-FileHash $config).Hash
        $result = Invoke-OfficePreInstallTest -StagedPath $stage -NetworkAvailable $Online
        $result.Outcome | Should -Be $Outcome
        (Get-FileHash $config).Hash | Should -Be $before
        New-OSDStageOfficeConfiguration -Path $config -Language nl-nl
        $before = (Get-FileHash $config).Hash
        { Invoke-OfficePreInstallTest -StagedPath $stage -NetworkAvailable $Online } | Should -Throw '*compatible*'
        (Get-FileHash $config).Hash | Should -Be $before
        @(Get-ChildItem (Split-Path $local -Parent) -Directory | Where-Object Name -Match 'osdstage-(new|old)-').Count | Should -Be 0
    }

    It 'refuses USB restaging of incompatible content before copying any files' {
        $local = Join-Path $TestDrive 'Rejected'
        New-Item -ItemType Directory -Path $local -Force | Out-Null
        $config = Join-Path $local 'configuration.xml'
        New-OSDStageOfficeConfiguration -Path $config -IncludeVisio
        $before = (Get-FileHash $config).Hash
        { Copy-OfficeCachePayload -SourceRoot $cache -DestinationRoot $local -ConfigurationPath $config } | Should -Throw '*cannot satisfy*'
        (Get-FileHash $config).Hash | Should -Be $before
        Test-Path (Join-Path $local 'setup.exe') | Should -BeFalse
    }
}

Describe 'Office staging keeps intent separate from cache payload' {
    BeforeAll { Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'OSDStage.psd1') -Force }
    It 'stages only intent when a structurally valid cache has different languages' {
        InModuleScope OSDStage {
            $usb = Join-Path $TestDrive 'Usb'
            $cache = Join-Path $usb 'BuiltIn\Microsoft365Apps'
            $windows = Join-Path $TestDrive 'Windows'
            $data = Join-Path $cache 'Office\Data'
            $version = '16.0.20430.20180'
            New-Item -ItemType Directory -Path (Join-Path $data $version),$windows -Force | Out-Null
            New-OSDStageOfficeConfiguration -Path (Join-Path $cache 'configuration.xml') -Language en-us
            Set-Content (Join-Path $cache 'setup.exe') 'setup'
            Set-Content (Join-Path $data "$version\payload.dat") 'payload'
            Set-Content (Join-Path $data 'v64.cab') 'cab'
            Set-Content (Join-Path $data "v64_$version.cab") 'cab'
            @{Version=$version;Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $cache 'CacheInfo.json')
            $before = (Get-FileHash (Join-Path $cache 'configuration.xml')).Hash
            $result = Add-OSDStageMicrosoft365AppsInternal -CachePath $usb -WindowsPath $windows -Language nl-nl -UseCachedConfiguration $false -Confirm:$false
            $result.CacheAvailable | Should -BeFalse
            $stage = $result.StagedPath
            [xml]$xml = Get-Content (Join-Path $stage 'configuration.xml') -Raw
            $xml.Configuration.Add.Product.Language.ID | Should -Be 'nl-nl'
            Test-Path (Join-Path $stage 'Office') | Should -BeFalse
            (Get-FileHash (Join-Path $cache 'configuration.xml')).Hash | Should -Be $before
        }
    }
}
