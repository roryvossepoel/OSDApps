Describe 'Office XML generation' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'OSDStage.psd1') -Force
    }

    It 'generates default 64-bit Microsoft 365 Apps with enabled updates' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'default.xml'
            New-OSDStageOfficeConfiguration -Path $path
            [xml]$xml = Get-Content -LiteralPath $path -Raw
            $xml.Configuration.Add.OfficeClientEdition | Should -Be '64'
            $xml.Configuration.Add.Channel | Should -Be 'Current'
            @($xml.Configuration.Add.Product).Count | Should -Be 1
            $xml.Configuration.Add.Product.ID | Should -Be 'O365ProPlusRetail'
            $xml.Configuration.Updates.Enabled | Should -Be 'TRUE'
        }
    }

    It 'generates Office, Visio and Project with Dutch language and updates disabled' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'multiple.xml'
            New-OSDStageOfficeConfiguration -Path $path -IncludeVisio -IncludeProject -Language nl-nl -Channel MonthlyEnterprise -Architecture x86 -UpdatesEnabled:$false -ExcludeApp Access
            [xml]$xml = Get-Content -LiteralPath $path -Raw
            $xml.Configuration.Add.OfficeClientEdition | Should -Be '32'
            $xml.Configuration.Add.Channel | Should -Be 'MonthlyEnterprise'
            $ids = @($xml.Configuration.Add.Product | ForEach-Object { $_.ID })
            $ids | Should -Be @('O365ProPlusRetail','VisioProRetail','ProjectProRetail')
            @($xml.Configuration.Add.Product | ForEach-Object { $_.Language.ID }) | Should -Be @('nl-nl','nl-nl','nl-nl')
            $xml.Configuration.Updates.Enabled | Should -Be 'FALSE'
            $xml.Configuration.Add.Product[0].ExcludeApp.ID | Should -Be 'Access'
            $null -eq $xml.Configuration.Add.Product[1].ExcludeApp | Should -BeTrue
        }
    }

    It 'rejects conflicting activation modes' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'conflict.xml'
            { New-OSDStageOfficeConfiguration -Path $path -SharedComputerLicensing:$true -DeviceBasedLicensing:$true } | Should -Throw
        }
    }

    It 'generates either supported activation property' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'device.xml'
            New-OSDStageOfficeConfiguration -Path $path -DeviceBasedLicensing:$true
            [xml]$xml = Get-Content -LiteralPath $path -Raw
            $xml.Configuration.Property.Name | Should -Be 'DeviceBasedLicensing'
            $xml.Configuration.Property.Value | Should -Be '1'
        }
    }
}
