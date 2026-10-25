Describe 'Maintenance diagnostic bundle' {
    BeforeAll {
        $tool = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Test-OSDAppsMaintenance.ps1'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function Read-Bundle {
            param($Path)
            $zip=[IO.Compression.ZipFile]::OpenRead($Path)
            try {
                $reader=[IO.StreamReader]::new($zip.GetEntry('Bundle.json').Open())
                try { $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            } finally { $zip.Dispose() }
        }
    }
    BeforeEach {
        $case=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case | Out-Null
        $resultPath=Join-Path $case 'Latest.json'
        $logPath=Join-Path $case 'Runtime.log'
        $outputPath=Join-Path $case 'Bundle.zip'
        $now=[datetime]::UtcNow
        $result=@{DeploymentId='test-deployment';Status='Failed';LogPath=$logPath;StartedAtUtc=$now.AddMinutes(-5).ToString('o');CompletedAtUtc=$now.ToString('o');PreInstall=@{StartedAtUtc=$now.AddMinutes(-15).ToString('o')}}
        $result | ConvertTo-Json | Set-Content $resultPath
        Set-Content $logPath 'App failed'
        Set-Content "$logPath.1" 'Prior runtime lines'
        $installer=Join-Path $case 'PC-20261022-1200.log'
        Set-Content $installer 'Office download evidence'
        Set-Content (Join-Path $case 'unrelated.log') 'Not a selected installer'
        $before=@(Get-ChildItem $case -File | Get-FileHash)
    }
    It 'bundles correlated results, rotations and installer candidates without changing sources' {
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath -InstallerLogDirectory $case -DeploymentId test-deployment
        $report.Passed | Should -BeTrue
        $bundle=Read-Bundle $outputPath
        $bundle.RecordedStatus | Should -Be Failed
        @($bundle.Files | Where-Object Status -eq Copied).Count | Should -Be 4
        @($bundle.Files | Where-Object Kind -eq InstallerLogCandidate).Count | Should -Be 1
        foreach($file in $before){(Get-FileHash $file.Path).Hash | Should -Be $file.Hash}
    }
    It 'refuses another deployment and leaves no archive' {
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath -DeploymentId other
        $report.Status | Should -Be Failed
        Test-Path $outputPath | Should -BeFalse
    }
    It 'preserves existing output' {
        Set-Content $outputPath 'Original'
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath
        $report.Status | Should -Be Failed
        Get-Content $outputPath | Should -Be Original
    }
    It 'warns about missing results and still exports an explicit runtime log' {
        Remove-Item $resultPath
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -LogPath $logPath -OutputPath $outputPath -InstallerLogDirectory $case
        $report.Status | Should -Be ReviewRequired
        $bundle=Read-Bundle $outputPath
        @($bundle.Files | Where-Object Kind -eq InstallerLogCandidate).Count | Should -Be 0
    }
    It 'excludes older installer logs and unrelated standalone PreInstall records' {
        (Get-Item $installer).LastWriteTimeUtc=$now.AddDays(-2)
        @{DeploymentId='other'} | ConvertTo-Json | Set-Content (Join-Path $case 'PreInstall.json')
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath -InstallerLogDirectory $case
        $report.Status | Should -Be ReviewRequired
        $bundle=Read-Bundle $outputPath
        @($bundle.Files | Where-Object Kind -in @('InstallerLogCandidate','PreInstall')).Count | Should -Be 0
    }
    It 'reports oversized files without collecting them' {
        $large=Join-Path $case 'large.log'
        $stream=[IO.File]::Create($large); try{$stream.SetLength(21MB)}finally{$stream.Dispose()}
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath -InstallerLogDirectory $case -AdditionalLogPath $large
        $report.Status | Should -Be ReviewRequired
        $bundle=Read-Bundle $outputPath
        @($bundle.Files | Where-Object { $_.Source -eq $large -and $_.Status -eq 'Skipped' }).Count | Should -Be 1
    }
    It 'does not follow linked installer-log directories' {
        $link=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $type=if($env:OS -eq 'Windows_NT'){'Junction'}else{'SymbolicLink'}
        New-Item -ItemType $type -Path $link -Target $case | Out-Null
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -OutputPath $outputPath -InstallerLogDirectory $link
        $report.Status | Should -Be ReviewRequired
        @((Read-Bundle $outputPath).Files | Where-Object Kind -eq InstallerLogCandidate).Count | Should -Be 0
    }
    It 'collects a failed standalone PreInstall result when Runner never created Latest.json' {
        Remove-Item $resultPath
        @{DeploymentId='early-failure';Status='Failed';StartedAtUtc=$now.AddMinutes(-5).ToString('o');CompletedAtUtc=$now.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $case 'PreInstall.json')
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -LogPath $logPath -OutputPath $outputPath -InstallerLogDirectory $case -DeploymentId early-failure
        $report.Status | Should -Be ReviewRequired
        $bundle=Read-Bundle $outputPath
        $bundle.DeploymentId | Should -Be early-failure
        @($bundle.Files | Where-Object Kind -eq PreInstall).Count | Should -Be 1
    }
    It 'does not produce an empty evidence archive' {
        Remove-Item $resultPath,$logPath,"$logPath.1"
        $report=& $tool -Mode Diagnostics -ResultPath $resultPath -LogPath $logPath -OutputPath $outputPath -InstallerLogDirectory $case
        $report.Status | Should -Be Failed
        Test-Path $outputPath | Should -BeFalse
    }

}
