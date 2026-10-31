Describe 'Microsoft 365 Apps cache generation integrity' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:moduleRoot 'Private\Test-OSDStageOfficeCacheGeneration.ps1')

        function global:New-OfficeGenerationFixture {
            param([string]$Root,[string]$Version='16.0.20430.20146',[string]$Shared='cab-current',[string]$Versioned='cab-current')
            $data=Join-Path $Root 'Office\Data';$versionRoot=Join-Path $data $Version
            New-Item -ItemType Directory -Path $versionRoot -Force|Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'setup.exe') -Value setup
            Set-Content -LiteralPath (Join-Path $Root 'configuration.xml') -Value '<Configuration />'
            Set-Content -LiteralPath (Join-Path $versionRoot 'stream.x64.x-none.dat') -Value payload
            Set-Content -LiteralPath (Join-Path $data 'v64.cab') -Value $Shared
            Set-Content -LiteralPath (Join-Path $data "v64_$Version.cab") -Value $Versioned
        }
    }

    AfterAll { Remove-Item Function:\New-OfficeGenerationFixture -ErrorAction SilentlyContinue }

    It 'accepts one internally consistent Office generation' {
        $root=Join-Path $TestDrive Valid
        New-OfficeGenerationFixture -Root $root
        $result=Test-OSDStageOfficeCacheGeneration -OfficeRoot $root -ExpectedVersion '16.0.20430.20146' -Architecture x64 -PassThru
        $result.Valid|Should -BeTrue
        $result.SharedCabSha256|Should -Be $result.VersionCabSha256
    }

    It 'rejects the hybrid cache shape found during physical validation' {
        $root=Join-Path $TestDrive Hybrid
        New-OfficeGenerationFixture -Root $root -Shared 'cab-from-16.0.20326' -Versioned 'cab-from-16.0.20430'
        $result=Test-OSDStageOfficeCacheGeneration -OfficeRoot $root -ExpectedVersion '16.0.20430.20146' -Architecture x64 -PassThru
        $result.Valid|Should -BeFalse
        ($result.Errors -join ' ')|Should -Match 'does not match the active version-specific CAB'
    }

    It 'rejects multiple version directories even if the newest looks complete' {
        $root=Join-Path $TestDrive Multiple
        New-OfficeGenerationFixture -Root $root
        $old=Join-Path $root 'Office\Data\16.0.20326.20142';New-Item -ItemType Directory -Path $old -Force|Out-Null
        Set-Content -LiteralPath (Join-Path $old 'stream.dat') -Value old
        $result=Test-OSDStageOfficeCacheGeneration -OfficeRoot $root -Architecture x64 -PassThru
        $result.Valid|Should -BeFalse
        ($result.Errors -join ' ')|Should -Match 'exactly one Office version directory'
    }
}
