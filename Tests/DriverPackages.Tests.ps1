Describe 'Repository driver packages' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\OSDAppDriver.ps1')
        $script:source=Join-Path $TestDrive 'Vendor Payload'
        foreach($folder in @('Network','Audio')) {
            $path=Join-Path $script:source $folder
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Set-Content (Join-Path $path 'device.inf') 'fixture INF; native validation is separate' -Encoding ASCII
            Set-Content (Join-Path $path 'device.cat') ($folder+' catalog') -Encoding ASCII
            Set-Content (Join-Path $path 'driver.sys') ($folder+' sys') -Encoding ASCII
            Set-Content (Join-Path $path 'support.dll') ($folder+' dll') -Encoding ASCII
        }
        $script:hidden=Join-Path $script:source 'Network\hidden.dat'
        Set-Content $script:hidden 'required hidden support file' -Encoding ASCII
        (Get-Item $script:hidden).Attributes=[IO.FileAttributes]::Hidden
        Set-Content (Join-Path $script:source 'Install.ps1') 'throw "Vendor scripts must not be launched by OSDApps"'
        $script:package=New-OSDAppPackage -Id WorkstationDrivers -Version 1.0.0 -PackageType Driver -SourcePath $script:source -OutputPath (Join-Path $TestDrive 'Build')
    }
    BeforeEach { Set-OSDAppConfiguration -EnableRepository $true -CleanupMode Never }

    It 'preserves nested INFs and all sibling files including hidden support files' {
        $check=Test-OSDAppPackage -PackagePath $script:package.PackagePath -PackageType Driver
        $check.Valid | Should -BeTrue
        $check.DriverInfCount | Should -Be 2
        $extract=Join-Path $TestDrive 'Extract'
        [IO.Compression.ZipFile]::ExtractToDirectory($script:package.PackagePath,$extract)
        foreach($source in @(Get-ChildItem $script:source -File -Recurse -Force)) {
            $relative=$source.FullName.Substring($script:source.Length+1)
            $destination=Join-Path (Join-Path $extract 'Package') $relative
            Test-Path -LiteralPath $destination -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $destination).Hash | Should -Be (Get-FileHash -LiteralPath $source.FullName).Hash
        }
    }
    It 'requires an INF and leaves the destination unchanged with WhatIf' {
        $empty=Join-Path $TestDrive 'NoInf'
        New-Item -ItemType Directory -Path $empty | Out-Null
        Set-Content (Join-Path $empty 'setup.exe') 'not an INF'
        {New-OSDAppPackage -Id NoInf -Version 1 -PackageType Driver -SourcePath $empty -OutputPath (Join-Path $TestDrive 'BadBuild')} | Should -Throw '*at least one .inf*'
        $output=Join-Path $TestDrive 'PreviewBuild'
        New-OSDAppPackage -Id Preview -Version 1 -PackageType Driver -SourcePath $script:source -OutputPath $output -WhatIf
        Test-Path $output | Should -BeFalse
    }
    It 'rejects source junctions before following them' {
        $source=Join-Path $TestDrive 'JunctionSource'
        New-Item -ItemType Directory -Path $source | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $source 'VendorLink') -Target $script:source | Out-Null
        {Get-OSDAppDriverInfFiles -PayloadRoot $source} | Should -Throw '*reparse*'
    }
    It 'preserves the Driver type through publication cache and offline staging without extracting in WinPE' {
        InModuleScope OSDApps -Parameters @{PackagePath=$script:package.PackagePath} {
            param($PackagePath)
            $repo=Join-Path $TestDrive 'DriverRepo'
            $cache=Join-Path $TestDrive 'DriverCache'
            $target=Join-Path $TestDrive 'Offline'
            New-OSDAppRepository -Path $repo | Out-Null
            $parameters=@{Id='WorkstationDrivers';DisplayName='Workstation drivers';Version='1.0.0';Architecture='x64';PackageType='Driver';PackagePath=$PackagePath;RepositoryPath=$repo}
            Add-OSDAppPackage @parameters | Out-Null
            (Add-OSDAppPackage -Id WorkstationDrivers -DisplayName 'Workstation drivers' -Version 1.0.0 -Architecture x64 -PackagePath $PackagePath -RepositoryPath $repo).PackageType | Should -Be Driver
            @(Test-OSDAppRepository -RepositoryPath $repo)[0].Valid | Should -BeTrue
            Sync-OSDAppCache -CatalogPath (Join-Path $repo 'catalog.json') -CachePath $cache -Architecture x64 -Confirm:$false | Out-Null
            (Get-Content (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json).Packages[0].PackageType | Should -Be Driver
            Mock Get-OSDAppCachePath {$cache}
            Mock Test-OSDAppPackage {throw 'Do not extract driver payloads during WinPE staging'}
            Mock Invoke-OSDAppPnPUtil {throw 'Do not import on the staging host'}
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDApp -Name WorkstationDrivers -WindowsPath $target -SkipCacheRefresh | Out-Null
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $stage=Join-Path $target 'Windows\Temp\OSDApps'
            (Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json).Apps[0].PackageType | Should -Be Driver
            Test-Path (Join-Path $stage 'OSDAppDriver.ps1') | Should -BeTrue
            Should -Invoke Test-OSDAppPackage -Times 0 -Exactly
            Should -Invoke Invoke-OSDAppPnPUtil -Times 0 -Exactly
            Add-Content (Join-Path $stage 'Packages\WorkstationDrivers\Package.zip') 'tampered'
            {Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure} | Should -Throw
        }
    }
    It 'stages only Driver Ids with the existing cache controls and honors WhatIf' {
        InModuleScope OSDApps {
            Mock Get-OSDApp {[pscustomobject]@{Id='WorkstationDrivers';Source='Repository';PackageType='Driver'}}
            Mock Add-OSDApp {[pscustomobject]@{PackageType='Driver'}}
            (Add-OSDAppDriver -Id WorkstationDrivers -SkipCacheRefresh).PackageType | Should -Be Driver
            Should -Invoke Get-OSDApp -Times 1 -Exactly -ParameterFilter {$Offline}
            Should -Invoke Add-OSDApp -Times 1 -Exactly -ParameterFilter {$Name -eq 'WorkstationDrivers' -and $SkipCacheRefresh}
            Add-OSDAppDriver -Id WorkstationDrivers -WhatIf
            Should -Invoke Add-OSDApp -Times 1 -Exactly
            Mock Get-OSDApp {[pscustomobject]@{Id='WorkstationDrivers';Source='Repository';PackageType='App'}}
            {Add-OSDAppDriver -Id WorkstationDrivers} | Should -Throw '*not Driver*'
        }
    }
    It 'reports successful store operations without claiming an unreported device binding' {
        Mock Invoke-OSDAppPnPUtil {
            param($InfPath,$Install)
            [pscustomobject]@{Command='fixture';ExitCode=0;StandardOutput='Already present / Bereits vorhanden';StandardError=''}
        }
        $reportPath=Join-Path $TestDrive 'Successful.json'
        $execution=Invoke-OSDAppDriverPackage -PayloadRoot $script:source -PackageId WorkstationDrivers -DeploymentId 'test' -ResultPath $reportPath
        $execution.ExitCode | Should -Be 0
        $report=Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.SuccessfulInfCount | Should -Be 2
        $report.DriverStoreReadyCount | Should -Be 2
        @($report.Items | Where-Object DeviceBindingConfirmed -ne $null).Count | Should -Be 0
        $report.Items[0].DriverStoreStatus | Should -Be AddedOrAlreadyPresent
        $report.Items[0].InstallCommand.StandardOutput | Should -Match 'Bereits vorhanden'
        $report.RebootRequested | Should -BeFalse
        Should -Invoke Invoke-OSDAppPnPUtil -Times 2 -Exactly -ParameterFilter {-not $Install}
        Should -Invoke Invoke-OSDAppPnPUtil -Times 2 -Exactly -ParameterFilter {$Install}
    }
    It 'accepts no matching device after verified store success and records reboot requirements without acting on them' {
        Mock Invoke-OSDAppPnPUtil {
            param($InfPath,$Install)
            $code=if(-not $Install){0}elseif($InfPath -match 'Audio'){259}else{3010}
            [pscustomobject]@{Command='fixture';ExitCode=$code;StandardOutput='native result';StandardError=''}
        }
        $reportPath=Join-Path $TestDrive 'Applicability.json'
        (Invoke-OSDAppDriverPackage -PayloadRoot $script:source -PackageId WorkstationDrivers -DeploymentId 'test' -ResultPath $reportPath).ExitCode | Should -Be 3010
        $report=Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.FailedInfCount | Should -Be 0
        $report.NoDeviceChangeCount | Should -Be 1
        $report.RestartNeeded | Should -BeTrue
        $report.RebootRequested | Should -BeFalse
        $report.Items[0].DeviceBindingConfirmed | Should -BeFalse
        $report.Items[1].DeviceBindingConfirmed | Should -BeTrue
    }
    It 'continues after store failure and never installs an INF whose store phase failed' {
        Mock Invoke-OSDAppPnPUtil {
            param($InfPath,$Install)
            $code=if($InfPath -match 'Audio'){5}else{0}
            [pscustomobject]@{Command='fixture';ExitCode=$code;StandardOutput='native detail';StandardError='native error detail'}
        }
        $reportPath=Join-Path $TestDrive 'Mixed.json'
        (Invoke-OSDAppDriverPackage -PayloadRoot $script:source -PackageId WorkstationDrivers -DeploymentId 'test' -ResultPath $reportPath).ExitCode | Should -Be 1
        $report=Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.SuccessfulInfCount | Should -Be 1
        $report.FailedInfCount | Should -Be 1
        $report.Items[0].InstallCommand | Should -BeNullOrEmpty
        $report.Items[0].StoreCommand.StandardError | Should -Be 'native error detail'
        Should -Invoke Invoke-OSDAppPnPUtil -Times 0 -Exactly -ParameterFilter {$Install -and $InfPath -match 'Audio'}
    }
    It 'keeps store success visible when device installation fails and attempts remaining INFs' {
        Mock Invoke-OSDAppPnPUtil {
            param($InfPath,$Install)
            $code=if($Install -and $InfPath -match 'Audio'){87}else{0}
            [pscustomobject]@{Command='fixture';ExitCode=$code;StandardOutput='detail';StandardError=''}
        }
        $reportPath=Join-Path $TestDrive 'DeviceFailure.json'
        (Invoke-OSDAppDriverPackage -PayloadRoot $script:source -PackageId WorkstationDrivers -DeploymentId 'test' -ResultPath $reportPath).ExitCode | Should -Be 1
        $report=Get-Content $reportPath -Raw | ConvertFrom-Json
        $report.DriverStoreReadyCount | Should -Be 2
        $report.FailedInfCount | Should -Be 1
        $report.Items[0].DeviceInstallStatus | Should -Be Failed
        Should -Invoke Invoke-OSDAppPnPUtil -Times 4 -Exactly
    }
    It 'records process launch errors and continues without retrying' {
        Mock Invoke-OSDAppPnPUtil {throw 'native launch failed'}
        $reportPath=Join-Path $TestDrive 'LaunchFailure.json'
        (Invoke-OSDAppDriverPackage -PayloadRoot $script:source -PackageId WorkstationDrivers -DeploymentId 'test' -ResultPath $reportPath).ExitCode | Should -Be 1
        (Get-Content $reportPath -Raw | ConvertFrom-Json).FailedInfCount | Should -Be 2
        Should -Invoke Invoke-OSDAppPnPUtil -Times 2 -Exactly
    }
    It 'uses real PnPUtil to reject invalid INF content while capturing output and exit code' {
        $inf=Join-Path $TestDrive 'invalid driver.inf'
        Set-Content $inf 'This is deliberately not an INF file.' -Encoding ASCII
        $result=Invoke-OSDAppPnPUtil -InfPath $inf
        $result.ExitCode | Should -Not -Be 0
        $result.Command | Should -Match '/add-driver "'
        $result.Command | Should -Not -Match '/reboot|/force|/install'
        ($result.StandardOutput+$result.StandardError).Length | Should -BeGreaterThan 0
        ($result.StandardOutput+$result.StandardError) | Should -Not -Match ([string][char]0)
    }
    It 'routes a real driver ZIP through the runner and reports native failure without executing Install.ps1' {
        $source=Join-Path $TestDrive 'RuntimeSource'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content (Join-Path $source 'invalid.inf') 'This is deliberately not a valid INF.' -Encoding ASCII
        $marker=Join-Path $TestDrive 'must-not-run.txt'
        Set-Content (Join-Path $source 'Install.ps1') ("Set-Content -LiteralPath '"+$marker.Replace("'","''")+"' -Value executed")
        $package=New-OSDAppPackage -Id InvalidDrivers -Version 1.0.0 -PackageType Driver -SourcePath $source -OutputPath (Join-Path $TestDrive 'RuntimeBuild')
        $stage=Join-Path $TestDrive 'RuntimeStage'
        $packageRoot=Join-Path $stage 'Packages\InvalidDrivers'
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        Copy-Item $package.PackagePath (Join-Path $packageRoot 'Package.zip')
        $resultPath=Join-Path $TestDrive 'RuntimeResults\Latest.json'
        @{
            SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid
            Runtime=@{CleanupMode='Never';CacheVolumeLabel='OSDCloud';LogPath=(Join-Path $TestDrive 'Runtime.log');ResultPath=$resultPath}
            Apps=@(@{Id='InvalidDrivers';DisplayName='Invalid driver fixture';Source='Repository';Type='RepositoryPackage';PackageType='Driver';Version='1.0.0';Architecture='x64';Archive=@{Sha256=$package.Sha256};SuccessCodes=@(0,1,3010)})
        } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:root 'Runtime\Invoke-OSDAppRunner.ps1') -StagedPath $stage
        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $marker | Should -BeFalse
        $latest=Get-Content $resultPath -Raw | ConvertFrom-Json
        $latest.Status | Should -Be Failed
        $latest.Apps[0].PackageType | Should -Be Driver
        $report=Get-Content (Join-Path $TestDrive 'RuntimeResults\Driver-InvalidDrivers-Result.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be Failed
        $report.FailedInfCount | Should -Be 1
        $report.Items[0].DriverStoreStatus | Should -Be Failed
        $report.Items[0].InstallCommand | Should -BeNullOrEmpty
    }
    It 'labels Driver packages in the UI' {
        InModuleScope OSDApps {
            Get-OSDAppUIPackageType -App ([pscustomobject]@{Source='Repository';PackageType='Driver'}) | Should -Be Driver
        }
    }
}
