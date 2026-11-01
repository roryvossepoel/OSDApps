Describe 'Office CDN descriptor interpretation' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/Test-OSDStageOfficeCacheCompatibility.ps1')
    }
    BeforeEach {
        Set-StrictMode -Version Latest
        $path = Join-Path $TestDrive 'VersionDescriptor.xml'
        $channel = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        $xml = '<Version><Available Build="16.0.12527.22286" I320Version="16.0.20430.20180" I640Version="16.0.20430.20180" /><DeliveryMechanism FFNRoot="55336b82-a18d-4dd6-b5f6-9e5095c314a6" /><AvailableBuilds><AvailableBuild RestrictionType="Default" Version="16.0.20430.20180" /><AvailableBuild RestrictionType="OS" Value="7" Version="16.0.12527.22286" /></AvailableBuilds><CreatedTimeUtc Value="10/18/2026 14:39" /></Version>'
        Set-Content $path $xml
    }
    It 'uses the architecture build instead of the legacy OS Build attribute' {
        Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel | Should -Be '16.0.20430.20180'
    }
    It 'reads x86 independently of the x64 build' {
        $xml.Replace('I640Version="16.0.20430.20180"','I640Version="16.0.20430.20200"') | Set-Content $path
        Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x86 -ChannelId $channel | Should -Be '16.0.20430.20180'
        { Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel } | Should -Throw '*conflicting*'
    }
    It 'accepts a version descriptor without optional rollout fields' {
        '<Version><Available I640Version="16.0.20430.20180" /><DeliveryMechanism FFNRoot="{0}" /></Version>' -f $channel | Set-Content $path
        Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel | Should -Be '16.0.20430.20180'
    }
    It 'rejects an unexpected channel' {
        { Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId wrong } | Should -Throw '*unexpected channel*'
    }
    It 'rejects a missing or dynamic architecture build' {
        $xml.Replace('I640Version="16.0.20430.20180"','I640Version="Current"') | Set-Content $path
        { Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel } | Should -Throw '*concrete build*'
    }
    It 'rejects duplicate Available elements' {
        $xml.Replace('</Version>','<Available I640Version="16.0.20430.20180" /></Version>') | Set-Content $path
        { Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel } | Should -Throw '*ambiguous*'
    }
    It 'prohibits DTDs' {
        ('<!DOCTYPE Version [<!ENTITY build "16.0.20430.20180">]>' + $xml) | Set-Content $path
        { Get-OSDStageOfficeDescriptorVersion -Path $path -Architecture x64 -ChannelId $channel } | Should -Throw
    }
    It 'expands a real CAB using Windows expand with paths containing spaces' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $folder = Join-Path $TestDrive 'native descriptor test'
        New-Item $folder -ItemType Directory | Out-Null
        $cab = Join-Path $folder 'v64.cab'
        & "$env:SystemRoot\System32\makecab.exe" $path $cab | Out-Null
        $LASTEXITCODE | Should -Be 0
        [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($cab),0,4) | Should -Be 'MSCF'
        $expanded = Expand-OSDStageOfficeDescriptor -CabPath $cab -DestinationPath $folder
        Get-OSDStageOfficeDescriptorVersion -Path $expanded -Architecture x64 -ChannelId $channel | Should -Be '16.0.20430.20180'
    }
    It 'extracts only the descriptor from a multi-file LZX cabinet' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $folder = Join-Path $TestDrive 'multi file cabinet'
        New-Item $folder -ItemType Directory | Out-Null
        $extra = Join-Path $folder 'v64.hash'
        Set-Content $extra 'unrelated metadata'
        $ddf = Join-Path $folder 'cab.ddf'
        @(
            '.Set Cabinet=on'
            '.Set Compress=on'
            '.Set CompressionType=LZX'
            '.Set CabinetNameTemplate=v64.cab'
            ('.Set DiskDirectory1="{0}"' -f $folder)
            ('.Set InfFileName="{0}"' -f (Join-Path $folder 'cab.inf'))
            ('.Set RptFileName="{0}"' -f (Join-Path $folder 'cab.rpt'))
            ('"{0}" VersionDescriptor.xml' -f $path)
            ('"{0}" v64.hash' -f $extra)
        ) | Set-Content $ddf -Encoding ASCII
        & "$env:SystemRoot\System32\makecab.exe" /F $ddf | Out-Null
        $LASTEXITCODE | Should -Be 0
        $cab = Join-Path $folder 'v64.cab'
        [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($cab),0,4) | Should -Be 'MSCF'
        $expanded = Expand-OSDStageOfficeDescriptor -CabPath $cab -DestinationPath $folder
        Get-OSDStageOfficeDescriptorVersion -Path $expanded -Architecture x64 -ChannelId $channel | Should -Be '16.0.20430.20180'
        Test-Path (Join-Path (Split-Path $expanded -Parent) 'v64.hash') | Should -BeFalse
    }

}
