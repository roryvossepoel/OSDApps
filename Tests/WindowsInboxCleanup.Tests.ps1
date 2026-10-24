Describe 'Built-in Windows Inbox Cleanup staging' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDApps.psd1') -Force
    }

    It 'advertises the bundled cleanup as a Script without a repository URL' {
        $app = Get-OSDApp -Name WindowsInboxCleanup -Offline
        $app.Id | Should -Be 'WindowsInboxCleanup'
        $app.Source | Should -Be 'BuiltIn'
        $app.PackageType | Should -Be 'Script'
        $app.Architecture | Should -Be 'any'
    }

    It 'rejects unsafe identifiers without staging' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'InvalidTarget'
            Mock Resolve-OSDAppWindowsPath { $target }
            { Add-OSDAppWindowsInboxCleanup -Remove @('Microsoft.BingWeather','*') -WindowsPath $target -Confirm:$false } | Should -Throw
            Test-Path -LiteralPath $target | Should -BeFalse
        }
    }

    It 'does not mutate the target when WhatIf is supplied' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'WhatIfWindows'
            Mock Resolve-OSDAppWindowsPath { $target }
            Mock Add-OSDAppSetupComplete { throw 'SetupComplete should not be staged under WhatIf' }
            Add-OSDAppWindowsInboxCleanup -Remove 'Microsoft.BingWeather' -WindowsPath $target -WhatIf | Out-Null
            Test-Path -LiteralPath $target | Should -BeFalse
            Should -Invoke Add-OSDAppSetupComplete -Exactly 0
        }
    }

    It 'stages the tested 13 with SHA-256 and preflight validates them' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Staged'
            Mock Resolve-OSDAppWindowsPath { $target }
            $staged = Add-OSDAppWindowsInboxCleanup -Preset Tested13 -WindowsPath $target -Confirm:$false
            $staged.SelectedCount | Should -Be 13
            $staged.PackageType | Should -Be 'Script'
            $manifestPath = Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 1
            $app = $manifest.Apps[0]
            $app.Id | Should -Be 'WindowsInboxCleanup'
            $app.PackageType | Should -Be 'Script'
            $app.ScriptSha256 | Should -Match '^[A-F0-9]{64}$'
            $app.ConfigurationSha256 | Should -Match '^[A-F0-9]{64}$'
            $configuration = Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\WindowsInboxCleanup\config.json'
            @((Get-Content -LiteralPath $configuration -Raw | ConvertFrom-Json).Remove).Count | Should -Be 13
            $check = Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $check.Valid | Should -BeTrue
            $check.OfflineReady | Should -BeTrue
            @($check.Applications).Count | Should -Be 1
            $check.Applications[0].IntegrityValid | Should -BeTrue
        }
    }

    It 'detects a modified script configuration and rejects it before boot' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Tampered'
            Mock Resolve-OSDAppWindowsPath { $target }
            Add-OSDAppWindowsInboxCleanup -Remove @('Microsoft.BingWeather','Microsoft.BingNews') -WindowsPath $target -Confirm:$false | Out-Null
            $config = Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\WindowsInboxCleanup\config.json'
            Set-Content -LiteralPath $config -Value '{"Remove":["Microsoft.WindowsStore"]}' -Encoding UTF8
            $check = Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady
            $check.Valid | Should -BeFalse
            $check.OfflineReady | Should -BeFalse
            $check.Applications[0].IntegrityValid | Should -BeFalse
        }
    }

    It 'preserves unrelated staged applications when the cleanup is re-added' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Order'
            Mock Resolve-OSDAppWindowsPath { $target }
            Add-OSDAppWindowsInboxCleanup -Remove 'Microsoft.BingNews' -WindowsPath $target -Confirm:$false | Out-Null
            $manifestPath = Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest = Set-OSDAppManifestApp -Manifest $manifest -App ([pscustomobject]@{Id='Other'; Source='Repository';Type='RepositoryPackage'})
            $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            Add-OSDAppWindowsInboxCleanup -Remove 'Microsoft.BingWeather' -DiagnoseOnly -WindowsPath $target -Confirm:$false | Out-Null
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            @($manifest.Apps.Id) | Should -Be @('Other','WindowsInboxCleanup')
            $manifest.Apps[-1].DiagnoseOnly | Should -BeTrue
            $config = Get-Content -LiteralPath (Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\WindowsInboxCleanup\config.json') -Raw | ConvertFrom-Json
            @($config.Remove) | Should -Be @('Microsoft.BingWeather')
        }
    }

    It 'resolves the default config path after script parameter binding' {
        # A parameter default can see an empty $PSScriptRoot under powershell.exe -File.
        $source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\Invoke-OSDAppWindowsInboxCleanup.ps1'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $configParam = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ConfigurationPath' })
        $configParam.Count | Should -Be 1
        $configParam[0].DefaultValue | Should -BeNullOrEmpty
        $body = Get-Content -LiteralPath $source -Raw -Encoding UTF8
        $body.Contains("`$ConfigurationPath = Join-Path `$PSScriptRoot 'config.json'") | Should -BeTrue
    }

    It 'declares the cleanup source with valid Windows PowerShell syntax' {
        $source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\Invoke-OSDAppWindowsInboxCleanup.ps1'
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }
}
