Describe 'Registry staging contract' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'exports two registry commands with optional switches and no view parameter' {
        foreach ($name in @('Add-OSDAppRegistryKey','Add-OSDAppRegistryValue')) {
            $cmd = Get-Command $name -Module OSDApps
            $cmd.Parameters.Keys | Should -Contain 'Registry32'
            $cmd.Parameters.Keys | Should -Contain 'Registry64'
            $cmd.Parameters.Keys | Should -Not -Contain 'View'
            @($cmd.Parameters.Registry32.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 0
        }
        (Get-Command Add-OSDAppRegistryKey).Parameters.Keys | Should -Not -Contain 'Value'
    }

    It 'refuses HKCU, HKCC, unknown roots, ambiguous switches and explicit redirection nodes' {
        foreach ($path in @('HKCU:\Software\Test','HKEY_CURRENT_USER\Software\Test','HKCC:\Test','HCU:\Test','HKLM:\SOFTWARE\WOW6432Node\Test','HKLM:\SOFTWARE\..\Test')) {
            { Add-OSDAppRegistryKey -Path $path -WhatIf } | Should -Throw
        }
        { Add-OSDAppRegistryKey -Path 'HKLM:\SOFTWARE\Test' -Registry32 -Registry64 -WhatIf } | Should -Throw
    }

    It 'maps HKCR to machine Classes and preserves explicit HKU hive names' {
        InModuleScope OSDApps {
            (Resolve-OSDAppRegistryTarget -Path 'HKCR:\OSDApps.Tests\Child').Path | Should -Be 'HKLM\SOFTWARE\Classes\OSDApps.Tests\Child'
            (Resolve-OSDAppRegistryTarget -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\OSDApps').Path | Should -Be 'HKLM\SOFTWARE\OSDApps'
            (Resolve-OSDAppRegistryTarget -Path 'HKU:\S-1-5-18\Software\OSDApps').Hive | Should -Be 'HKU'
            { Resolve-OSDAppRegistryTarget -Path 'HKU:\MadeUpHive\Software\OSDApps' } | Should -Throw
        }
    }

    It 'round-trips all supported data types without executing string content' {
        InModuleScope OSDApps {
            $cases = @(
                @{Type='String'; Value='$(throw "do not run")'; Expected='$(throw "do not run")'},
                @{Type='String'; Value=''; Expected=''},
                @{Type='ExpandString'; Value='%SystemRoot%\Temp'; Expected='%SystemRoot%\Temp'},
                @{Type='DWord'; Value='4294967295'; Expected='4294967295'},
                @{Type='DWord'; Value=-1; Expected='4294967295'},
                @{Type='QWord'; Value='18446744073709551615'; Expected='18446744073709551615'},
                @{Type='MultiString'; Value=[string[]]@('one','two'); Expected=[string[]]@('one','two')},
                @{Type='MultiString'; Value=[string[]]@('one'); Expected=[string[]]@('one')},
                @{Type='MultiString'; Value=[string[]]@(); Expected=[string[]]@()},
                @{Type='Binary'; Value=[byte[]]@(0,1,255); Expected='AAH/'},
                @{Type='Binary'; Value=[byte[]]@(); Expected=''}
            )
            foreach ($case in $cases) {
                $op = New-OSDAppRegistryOperation -Action Value -Path 'HKLM:\SOFTWARE\OSDApps\Test' -Name '' -Type $case.Type -Value $case.Value
                $op.Data | Should -Be $case.Expected
                $roundtrip = [pscustomobject]@{SchemaVersion=1;Operations=@($op)} | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                { Assert-OSDAppRegistryConfiguration -Configuration $roundtrip } | Should -Not -Throw
            }
            { New-OSDAppRegistryOperation -Action Value -Path 'HKLM:\SOFTWARE\Test' -Name N -Type DWord -Value '4294967296' } | Should -Throw
            { New-OSDAppRegistryOperation -Action Value -Path 'HKLM:\SOFTWARE\Test' -Name N -Type DWord -Value 1.5 } | Should -Throw
            { New-OSDAppRegistryOperation -Action Value -Path 'HKLM:\SOFTWARE\Test' -Name N -Type Binary -Value @(256) } | Should -Throw
        }
    }

    It 'never stages onto the preparation PC and WhatIf creates nothing' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            $target = Join-Path $TestDrive 'Unchanged'
            New-Item -ItemType Directory -Path $target | Out-Null
            { Add-OSDAppRegistryKey -Path 'HKLM:\SOFTWARE\OSDApps\Test' -WindowsPath $target } | Should -Throw '*WinPE*'
            Add-OSDAppRegistryKey -Path 'HKLM:\SOFTWARE\OSDApps\Test' -WindowsPath $target -WhatIf
            @(Get-ChildItem -LiteralPath $target -Recurse -Force).Count | Should -Be 0
        }
    }

    It 'creates one offline Script entry, separates views and replaces duplicate intent' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target = Join-Path $TestDrive 'OfflineWindows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $key = 'HKLM:\SOFTWARE\OSDApps\Tests\RegistryStageOnly\L1\L2\L3'
            Add-OSDAppRegistryKey -Path ($key + '\Empty') -Registry64 -WindowsPath $target | Out-Null
            Add-OSDAppRegistryValue -Path $key -Name 'Marker' -Type String -Value 'x64-old' -Registry64 -WindowsPath $target | Out-Null
            Add-OSDAppRegistryValue -Path $key -Name 'Marker' -Type String -Value 'x86' -Registry32 -WindowsPath $target | Out-Null
            $last = Add-OSDAppRegistryValue -Path $key.ToLowerInvariant() -Name 'marker' -Type String -Value 'x64-new' -Registry64 -WindowsPath $target
            $last.OperationCount | Should -Be 3
            $stage = Join-Path $target 'Windows\Temp\OSDApps'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 1
            $manifest.Apps[0].Id | Should -Be 'RegistrySettings'
            $manifest.Apps[0].PackageType | Should -Be 'Script'
            $manifest.Apps[0].RegistryOperationCount | Should -Be 3
            (Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure).OfflineReady | Should -BeTrue
            $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $stage 'Packages\RegistrySettings\Package.zip'))
            try {
                $reader = [IO.StreamReader]::new($zip.GetEntry('Package/config.json').Open())
                try { $config=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
                @($config.Operations | Where-Object { $_.Action -eq 'Value' -and $_.View -eq 'Registry64' })[0].Data | Should -Be 'x64-new'
                @($config.Operations | Where-Object { $_.Action -eq 'Value' -and $_.View -eq 'Registry32' })[0].Data | Should -Be 'x86'
            } finally { $zip.Dispose() }
            Test-Path -LiteralPath $key | Should -BeFalse
            # A damaged archive must not be accepted as prior registry intent.
            [IO.File]::AppendAllText((Join-Path $stage 'Packages\RegistrySettings\Package.zip'),'tampered')
            { Add-OSDAppRegistryKey -Path ($key + '\Another') -WindowsPath $target } | Should -Throw '*intact*'
        }
    }
    It 'executes its generated script through the real standalone runner' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'IntegrationWindows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $sub='SOFTWARE\OSDApps\Tests\RegistryRunner-' + [guid]::NewGuid().ToString('N')
            $resultPath=Join-Path $target 'Results\Latest.json'
            Set-OSDAppConfiguration -CleanupMode Never -PreventSleep $false -ResultPath $resultPath -LogPath (Join-Path $target 'Logs\Runtime.log')
            try {
                Add-OSDAppRegistryValue -Path ('HKLM:\'+$sub+'\One\Two\Three') -Name Value -Type DWord -Value 32 -Registry32 -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDApps'
                $runner=Join-Path $stage 'Invoke-OSDAppRunner.ps1'
                $engine=(Get-Process -Id $PID).Path
                & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                $result=Get-Content $resultPath -Raw | ConvertFrom-Json
                $result.Status | Should -Be 'Succeeded'
                $result.SuccessfulAppCount | Should -Be 1
                $result.Apps[0].Integrity | Should -Be 'Sha256Validated'
                $report=Get-Content (Join-Path $target 'Results\Registry-Result.json') -Raw | ConvertFrom-Json
                $report.DeploymentId | Should -Be $result.DeploymentId
                $report.SuccessfulOperationCount | Should -Be 1
                $report.Items[0].ResolvedView | Should -Be 'Registry32'
            } finally {
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry32)
                try { $base.DeleteSubKeyTree($sub,$false) } finally { $base.Dispose() }
            }
        }
    }

}
