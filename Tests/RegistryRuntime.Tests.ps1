Describe 'Registry execution in isolated Windows hosts' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $script:root 'Runtime\OSDStageRegistry.ps1')
        $script:runtime = Join-Path $script:root 'Runtime\Invoke-OSDStageRegistry.ps1'
        function Invoke-RegistryTestHost {
            param([string]$HostPath,[string]$ConfigPath,[string]$ReportPath)
            $si = [Diagnostics.ProcessStartInfo]::new()
            $si.FileName = $HostPath
            $si.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ConfigurationPath "{1}" -ResultPath "{2}"' -f $script:runtime,$ConfigPath,$ReportPath
            $si.UseShellExecute=$false; $si.CreateNoWindow=$true
            $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
            $p = [Diagnostics.Process]::new(); $p.StartInfo=$si
            try {
                [void]$p.Start()
                $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
                if (-not $p.WaitForExit(45000)) { $p.Kill(); throw 'Registry test host timed out.' }
                if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) { throw 'Registry host output did not close.' }
                $output = $stdout.Result + $stderr.Result
                $p.ExitCode | Should -Be 0 -Because $output
            } finally { $p.Dispose() }
            Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        function Read-RegistryTestKey {
            param([string]$SubKey,[string]$View)
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$View)))
            try { $base.OpenSubKey($SubKey,$false) } finally { $base.Dispose() }
        }
    }

    It 'separates both views, creates keys, preserves data and resolves Default in a <Bits>-bit host' -Skip:($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) -TestCases @(@{Bits=64;Folder='System32'},@{Bits=32;Folder='SysWOW64'}) {
        param($Bits,$Folder)
        $hostPath=Join-Path $env:SystemRoot ($Folder + '\WindowsPowerShell\v1.0\powershell.exe')
        Test-Path $hostPath | Should -BeTrue
        $leaf='RegistryCI-' + [guid]::NewGuid().ToString('N')
        $sub='SOFTWARE\OSDStage\Tests\' + $leaf
        $path='HKLM:\' + $sub + '\Level1\Level2\Level3'
        $ops=@()
        foreach ($view in @('Registry32','Registry64','Default')) {
            $flags=@{}
            if ($view -ne 'Default') { $flags[$view]=$true }
            $p=if ($view -eq 'Default') { $path + '\Default' } else { $path }
            $number=if ($view -eq 'Registry32') {32} elseif ($view -eq 'Registry64') {64} else {0}
            $ops+=New-OSDStageRegistryOperation -Action Key -Path ($p+'\Empty') @flags
            $ops+=New-OSDStageRegistryOperation -Action Value -Path $p -Name Marker -Type String -Value $view @flags
            $ops+=New-OSDStageRegistryOperation -Action Value -Path $p -Name Number -Type DWord -Value $number @flags
        }
        $ops+=New-OSDStageRegistryOperation -Action Value -Path $path -Name Expanded -Type ExpandString -Value '%SystemRoot%\Temp' -Registry64
        $ops+=New-OSDStageRegistryOperation -Action Value -Path $path -Name Multi -Type MultiString -Value @('first','second') -Registry32
        $ops+=New-OSDStageRegistryOperation -Action Value -Path $path -Name Bytes -Type Binary -Value ([byte[]]@(0,17,255)) -Registry64
        $ops+=New-OSDStageRegistryOperation -Action Value -Path $path -Name '' -Type String -Value 'unnamed' -Registry64
        $ops+=New-OSDStageRegistryOperation -Action Value -Path $path -Name MaxQWord -Type QWord -Value '18446744073709551615' -Registry64
        $config=[pscustomobject]@{SchemaVersion=2;Operations=@($ops);DeploymentId=[guid]::NewGuid().Guid}
        $configPath=Join-Path $TestDrive ($leaf+'.json'); $reportPath=Join-Path $TestDrive ($leaf+'-result.json')
        try {
            $config | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $configPath -Encoding UTF8
            $first=Invoke-RegistryTestHost -HostPath $hostPath -ConfigPath $configPath -ReportPath $reportPath
            $first.Status | Should -Be 'Succeeded'
            $first.OperationCount | Should -Be 14
            @($first.Items | Where-Object Outcome -ne 'Created').Count | Should -Be 0
            $first.Process64Bit | Should -Be ($Bits -eq 64)
            $second=Invoke-RegistryTestHost -HostPath $hostPath -ConfigPath $configPath -ReportPath $reportPath
            @($second.Items | Where-Object Outcome -ne 'Unchanged').Count | Should -Be 0
            foreach ($view in @('Registry32','Registry64')) {
                $key=Read-RegistryTestKey -SubKey ($sub+'\Level1\Level2\Level3') -View $view
                try {
                    $key.GetValue('Marker') | Should -Be $view
                    $key.GetValue('Number') | Should -Be $(if($view -eq 'Registry32'){32}else{64})
                    $empty=$key.OpenSubKey('Empty')
                    try { $empty.ValueCount | Should -Be 0; $empty.SubKeyCount | Should -Be 0 } finally { $empty.Dispose() }
                } finally { $key.Dispose() }
            }
            $defaultView=if($Bits -eq 64){'Registry64'}else{'Registry32'}
            $dkey=Read-RegistryTestKey -SubKey ($sub+'\Level1\Level2\Level3\Default') -View $defaultView
            try { $dkey.GetValue('Marker') | Should -Be 'Default' } finally { $dkey.Dispose() }
            # Change only a 32-bit value; a key-only request must preserve it later.
            $changed=New-OSDStageRegistryOperation -Action Value -Path $path -Name Marker -Type String -Value 'Changed32' -Registry32
            (Invoke-OSDStageRegistryOperation -Operation $changed).Outcome | Should -Be 'Updated'
            $keyOnly=New-OSDStageRegistryOperation -Action Key -Path $path -Registry32
            (Invoke-OSDStageRegistryOperation -Operation $keyOnly).Outcome | Should -Be 'Unchanged'
            $key=Read-RegistryTestKey -SubKey ($sub+'\Level1\Level2\Level3') -View Registry64
            try { $key.GetValue('Marker') | Should -Be 'Registry64' } finally { $key.Dispose() }
            $key=Read-RegistryTestKey -SubKey ($sub+'\Level1\Level2\Level3') -View Registry32
            try { $key.GetValue('Marker') | Should -Be 'Changed32'; $key.GetValue('Multi').Count | Should -Be 2 } finally { $key.Dispose() }
        }
        finally {
            # Delete only this test's GUID-named subtree; never the user's registry content.
            foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)) {
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
                try { $base.DeleteSubKeyTree($sub,$false) } finally { $base.Dispose() }
            }
        }
    }

    It 'refuses an unloaded HKU hive without creating it' -Skip:($env:OS -ne 'Windows_NT') {
        $op=New-OSDStageRegistryOperation -Action Key -Path 'HKU:\S-1-5-21-999999999-999999999-999999999-9999\Software\OSDStage'
        { Invoke-OSDStageRegistryOperation -Operation $op } | Should -Throw '*not loaded*'
    }
}
