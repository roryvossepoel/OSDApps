BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'OSDStage.psd1') -Force
}
Describe 'Online app staging without prepared media' {
    It 'stages <Id> with no USB and correctly requires network' -ForEach @(@{Id='MicrosoftCompanyPortal'},@{Id='CMTraceOpen'}) {
        InModuleScope OSDStage -Parameters @{Id=$Id} {
            param($Id)
            $target = Join-Path $TestDrive $Id
            Mock Get-OSDStageCachePath { throw 'No USB' }
            Mock Resolve-OSDStageWindowsPath { $target }
            $result = & ('Add-OSDStage'+$Id) -WindowsPath $target -Confirm:$false
            $result.CacheAvailable | Should -BeFalse
            $manifest = Get-Content (Join-Path $target 'Windows/Temp/OSDStage/DeviceManifest.json') -Raw | ConvertFrom-Json
            Test-OSDStageOnlineAppIntent $manifest.Packages[0] | Should -BeTrue
            $check = Test-OSDStageDeployment -WindowsPath $target -MinimumFreeSpaceGB 0
            $check.Valid | Should -BeTrue
            $check.NetworkRequired | Should -BeTrue
            $check.OfflineReady | Should -BeFalse
            (Test-OSDStageDeployment -WindowsPath $target -MinimumFreeSpaceGB 0 -RequireOfflineReady).Valid | Should -BeFalse
        }
    }
    It 'does not mutate staging on WhatIf for <Id>' -ForEach @(@{Id='MicrosoftCompanyPortal'},@{Id='CMTraceOpen'}) {
        InModuleScope OSDStage -Parameters @{Id=$Id} {
            param($Id)
            $target = Join-Path $TestDrive ('whatif-'+$Id)
            Mock Get-OSDStageCachePath { throw 'No USB' }
            Mock Resolve-OSDStageWindowsPath { $target }
            & ('Add-OSDStage'+$Id) -WindowsPath $target -WhatIf
            Test-Path $target | Should -BeFalse
        }
    }
    It 'rejects payload fields attached to pending intent' {
        InModuleScope OSDStage {
            $app=[pscustomobject]@{Id='CMTraceOpen';Source='BuiltIn';Type='VendorMsi';PackageType='App';Architecture='x64';AcquisitionPending=$true;Package='elsewhere.msi'}
            Test-OSDStageOnlineAppIntent $app | Should -BeFalse
        }
    }
}

Describe 'Automatic CMTrace cache refresh' {
    BeforeEach {
        InModuleScope OSDStage {
            $script:releaseVersion='1.6.3'
            $script:releaseBytes='official MSI fixture'
            $script:cmCache=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:hashFile=Join-Path $TestDrive 'download.msi'
            [IO.File]::WriteAllText($script:hashFile,$script:releaseBytes)
            $script:releaseHash=(Get-FileHash $script:hashFile).Hash
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid'} }
            Mock Invoke-RestMethod {
                [pscustomobject]@{draft=$false;prerelease=$false;tag_name=('v'+$script:releaseVersion);assets=@(
                    [pscustomobject]@{name=('CMTrace-Open_'+$script:releaseVersion+'_x64.msi');digest=('sha256:'+$script:releaseHash);browser_download_url=('https://github.com/adamgell/cmtraceopen/releases/download/v'+$script:releaseVersion+'/CMTrace-Open_'+$script:releaseVersion+'_x64.msi')}
                )}
            }
            Mock Invoke-WebRequest { [IO.File]::WriteAllText($OutFile,$script:releaseBytes) }
        }
    }
    It 'downloads on empty media, reuses a checked release and refreshes a newer release' {
        InModuleScope OSDStage {
            (Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache).Updated | Should -BeTrue
            (Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache).Updated | Should -BeFalse
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            $script:releaseVersion='1.7.0'
            (Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache).Updated | Should -BeTrue
            $entry=Get-OSDStageOnlineAppCacheEntry -CachePath $script:cmCache -Id CMTraceOpen -Architecture x64 -VerifySignature
            $entry.Version | Should -Be '1.7.0'
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        }
    }
    It 'refreshes malformed legacy metadata rather than blocking' {
        InModuleScope OSDStage {
            $variant=Join-Path $script:cmCache 'BuiltIn/CMTraceOpen/x64'
            New-Item -ItemType Directory $variant -Force | Out-Null
            '{legacy' | Set-Content (Join-Path $variant 'CacheInfo.json')
            (Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache).Updated | Should -BeTrue
            (Get-OSDStageOnlineAppCacheEntry -CachePath $script:cmCache -Id CMTraceOpen -Architecture x64).Version | Should -Be '1.6.3'
        }
    }
    It 'preserves the previous generation when a new download has a bad digest' {
        InModuleScope OSDStage {
            Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache | Out-Null
            $script:releaseVersion='1.7.0'
            $script:releaseBytes='tampered'
            { Sync-OSDStageCMTraceOpenGeneration -CachePath $script:cmCache } | Should -Throw '*hash*'
            (Get-OSDStageOnlineAppCacheEntry -CachePath $script:cmCache -Id CMTraceOpen -Architecture x64).Version | Should -Be '1.6.3'
        }
    }
}

Describe 'Standalone online app PreInstall routing' {
    BeforeAll {
        . (Join-Path $root 'Runtime/OSDStagePayloadFile.ps1')
        . (Join-Path $root 'Runtime/OSDStageOnlineApps.ps1')
        $t=$null;$e=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime/Invoke-OSDStagePreInstall.ps1'),[ref]$t,[ref]$e)
        foreach($name in @('Sync-PreInstallOnlineApp','Set-PreInstallAcquisitionResult','Get-PreInstallFailureType')) {
            $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
            . ([scriptblock]::Create($fn.Extent.Text))
        }
        function Save-PreInstallDownload { param($Uri,$DestinationDirectory,$ExpectedExtension,$Id,$Description,$TimeoutMinutes) }
    }
    BeforeEach {
        $script:StagedPath=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $StagedPath -Force | Out-Null
        $script:usbRoot=$null
        $script:networkAvailable=$true
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid'} }
        Mock Sync-OSDStageCMTraceOpenGeneration {
            $variant=Join-Path $CachePath 'BuiltIn/CMTraceOpen/x64'
            New-Item -ItemType Directory $variant -Force | Out-Null
            $file=Join-Path $variant 'CMTrace-Open_1.7.0_x64.msi'
            'valid generation' | Set-Content $file
            @{Id='CMTraceOpen';Version='1.7.0';Architecture='x64';PayloadFileName=(Split-Path $file -Leaf);Sha256=(Get-FileHash $file).Hash} | ConvertTo-Json | Set-Content (Join-Path $variant 'CacheInfo.json')
            [pscustomobject]@{Updated=$true}
        }
    }
    It 'acquires without USB and replaces pending intent with validated install paths' {
        $app=[pscustomobject]@{Id='CMTraceOpen';Source='BuiltIn';Type='VendorMsi';Architecture='x64';AcquisitionPending=$true;MsiProperties=@('DISABLEUPDATECHECKS=1');InstallTimeoutMinutes=12}
        $a=@{}
        Sync-PreInstallOnlineApp -App $app -Acquisition $a
        $a.Outcome | Should -Be 'Downloaded'
        $app.Version | Should -Be '1.7.0'
        $app.PSObject.Properties.Name | Should -Not -Contain 'AcquisitionPending'
        Test-Path (Join-Path $StagedPath $app.Package) | Should -BeTrue
        $app.MsiProperties | Should -Contain 'DISABLEUPDATECHECKS=1'
        $app.InstallTimeoutMinutes | Should -Be 12
    }
    It 'populates USB cache and copies validated content locally' {
        $script:usbRoot=Join-Path $TestDrive 'usb-cache'
        $app=[pscustomobject]@{Id='CMTraceOpen';Architecture='x64';AcquisitionPending=$true}
        $a=@{}
        Sync-PreInstallOnlineApp -App $app -Acquisition $a
        Test-Path (Join-Path $usbRoot $app.Package) | Should -BeTrue
        Test-Path (Join-Path $StagedPath $app.Package) | Should -BeTrue
    }
    It 'uses verified offline content and rejects corrupt offline content' {
        Sync-OSDStageCMTraceOpenGeneration -CachePath $StagedPath | Out-Null
        $script:networkAvailable=$false
        $app=[pscustomobject]@{Id='CMTraceOpen';Architecture='x64';AcquisitionPending=$true}
        $a=@{}
        Sync-PreInstallOnlineApp -App $app -Acquisition $a
        $a.Outcome | Should -Be 'OfflineCacheUsed'
        'tampered' | Set-Content (Join-Path $StagedPath $app.Package)
        { Sync-PreInstallOnlineApp -App $app -Acquisition @{} } | Should -Throw '*no valid cache*'
    }
    It 'reports failed online refresh as fallback, never as current-version reuse' {
        Sync-OSDStageCMTraceOpenGeneration -CachePath $StagedPath | Out-Null
        Mock Sync-OSDStageCMTraceOpenGeneration { throw 'release service unavailable' }
        $app=[pscustomobject]@{Id='CMTraceOpen';Architecture='x64'}
        $a=@{}
        Sync-PreInstallOnlineApp -App $app -Acquisition $a
        $a.Outcome | Should -Be 'FallbackCacheUsed'
        $a.RefreshError | Should -Match 'release service unavailable'
    }
    It 'prepares Company Portal bundle, license and dependencies with USB=<UseUsb>' -ForEach @(@{UseUsb=$false},@{UseUsb=$true}) {
        if($UseUsb){$script:usbRoot=Join-Path $TestDrive 'portal-usb'}
        Mock Sync-OSDStageMicrosoftCompanyPortalGeneration {
            $variant=Join-Path $CachePath 'BuiltIn/MicrosoftCompanyPortal/x64'
            New-Item -ItemType Directory (Join-Path $variant 'Dependencies') -Force | Out-Null
            $paths=@('Portal.appxbundle','Portal_License1.xml','Dependencies\one.appx','Dependencies\two.appx','Dependencies\three.appx','Dependencies\four.appx','Dependencies\five.appx')
            $files=@(foreach($path in $paths){
                $file=Join-Path $variant $path
                'verified kit content' | Set-Content $file
                @{Path=$path;Sha256=(Get-FileHash $file).Hash}
            })
            @{Id='MicrosoftCompanyPortal';Architecture='x64';Version='11.2.1495.0';PayloadFileName='Portal.appxbundle';LicenseFileName='Portal_License1.xml';DependencyCount=5;Files=$files} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $variant 'CacheInfo.json')
            [pscustomobject]@{Updated=$true;CacheReused=$false}
        }
        $app=[pscustomobject]@{Id='MicrosoftCompanyPortal';Source='BuiltIn';Type='CompanyPortalAppxBundle';PackageType='App';Architecture='x64';AcquisitionPending=$true}
        $a=@{}
        Sync-PreInstallOnlineApp -App $app -Acquisition $a
        $a.Outcome | Should -Be 'Downloaded'
        Test-OSDStageCompanyPortalDefinition $app | Should -BeTrue
        { Assert-OSDStageCompanyPortalFiles -App $app -StagedPath $StagedPath } | Should -Not -Throw
        if($UseUsb){ Assert-OSDStageCompanyPortalFiles -App $app -StagedPath $usbRoot }
        $app.PSObject.Properties.Name | Should -Not -Contain 'AcquisitionPending'
        Should -Invoke Sync-OSDStageMicrosoftCompanyPortalGeneration -Exactly 1 -ParameterFilter { $NoFallback -and $null -ne $Download }
    }

}

Describe 'Runner handling of unsuccessful online preparation' {
    It 'skips installation for both apps after failed acquisition' -Skip:($env:OS -ne 'Windows_NT') {
        $stage=Join-Path $TestDrive 'pending-runner'
        $resultPath=Join-Path $stage 'Results/Latest.json'
        New-Item -ItemType Directory (Split-Path $resultPath -Parent) -Force | Out-Null
        $deploymentId=[guid]::NewGuid().Guid
        $packages=@(
            @{Id='MicrosoftCompanyPortal';Source='BuiltIn';Type='CompanyPortalAppxBundle';PackageType='App';Architecture='x64';AcquisitionPending=$true},
            @{Id='CMTraceOpen';Source='BuiltIn';Type='VendorMsi';PackageType='App';Architecture='x64';AcquisitionPending=$true}
        )
        @{SchemaVersion=2;DeploymentId=$deploymentId;Packages=$packages;Runtime=@{CleanupMode='Never';PreventSleep=$false;ResultPath=$resultPath;LogPath=(Join-Path $stage 'Runtime.log')}} |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
        @{DeploymentId=$deploymentId;Phase='PreInstall';Status='CompletedWithErrors';Packages=@(
            @{Id='MicrosoftCompanyPortal';Status='Failed';AcquisitionOutcome='Failed';Error='No source available';FailureType='RemoteAcquisition'},
            @{Id='CMTraceOpen';Status='Failed';AcquisitionOutcome='Failed';Error='No source available';FailureType='RemoteAcquisition'}
        )} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path (Split-Path $resultPath -Parent) 'PreInstall.json') -Encoding UTF8
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=(Get-Process -Id $PID).Path
        $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -StagedPath "{1}"' -f (Join-Path $root 'Runtime/Invoke-OSDStageRunner.ps1'),$stage
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
        try {
            [void]$process.Start()
            $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(30000)){ $process.Kill(); throw 'Runner timed out.' }
            [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)
            $process.ExitCode | Should -Be 1
        } finally { if(-not $process.HasExited){$process.Kill()}; $process.Dispose() }
        $result=Get-Content $resultPath -Raw | ConvertFrom-Json
        $result.FailedPackageCount | Should -Be 0
        $result.SkippedPackageCount | Should -Be 2
        @($result.Packages | Where-Object AcquisitionOutcome -eq Failed).Count | Should -Be 2
        @($result.Packages | Where-Object FailureType -eq RemoteAcquisition).Count | Should -Be 2
    }
}
