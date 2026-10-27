Describe 'One-time Windows desktop configuration' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDAppDesktopSettings.ps1')
    }
    BeforeEach { Set-OSDAppConfiguration -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never }

    It 'preserves mixed pin order, Unicode and literal target environment variables' {
        $pins=@(ConvertTo-OSDAppDesktopPins -Pins @(
            @{desktopAppId='MSEdge'},@{packagedAppId='Contoso_123!App'},@{desktopAppLink='%ProgramData%\Tools\Café & Tools.lnk'}
        ))
        $pins.Count | Should -Be 3
        $pins[0].desktopAppId | Should -Be MSEdge
        $pins[2].desktopAppLink | Should -Be '%ProgramData%\Tools\Café & Tools.lnk'
        [xml]$xml=ConvertTo-OSDAppTaskbarXml -Pins $pins
        $nodes=$xml.SelectNodes("//*[local-name()='TaskbarPinList']/*")
        $nodes.Count | Should -Be 3
        $xml.SelectSingleNode("//*[local-name()='CustomTaskbarLayoutCollection']").GetAttribute('PinListPlacement') | Should -Be Replace
        foreach ($node in $nodes) { $node.GetAttribute('PinGeneration') | Should -Be '1' }
        $nodes[0].GetAttribute('DesktopApplicationID') | Should -Be MSEdge
        $nodes[1].GetAttribute('AppUserModelID') | Should -Be 'Contoso_123!App'
        $nodes[2].GetAttribute('DesktopApplicationLinkPath') | Should -Be '%ProgramData%\Tools\Café & Tools.lnk'
    }
    It 'allows an explicitly empty replacement layout' {
        @(ConvertTo-OSDAppDesktopPins -Pins @()).Count | Should -Be 0
        [xml]$xml=ConvertTo-OSDAppTaskbarXml -Pins @()
        $xml.SelectSingleNode("//*[local-name()='CustomTaskbarLayoutCollection']").GetAttribute('PinListPlacement') | Should -Be Replace
        $xml.SelectNodes("//*[local-name()='TaskbarPinList']/*").Count | Should -Be 1
        $xml.SelectSingleNode("//*[local-name()='TaskbarPinList']/*").GetAttribute('DesktopApplicationLinkPath') | Should -Be '#leaveempty'
    }
    It 'rejects ambiguous, unsafe, unsupported and duplicate pin inputs' {
        foreach ($pins in @(
            @(@{desktopAppId='MSEdge';packagedAppId='Other!App'}),
            @(@{secondaryTile='unsupported'}),@(@{desktopAppId='Microsoft Edge'}),
            @(@{desktopAppLink='\\server\share\tool.lnk'}),@(@{desktopAppLink='C:\Tools\run.exe'}),
            @(@{desktopAppLink='%Unknown%\Tools.lnk'}),@(@{desktopAppLink='C:\Tools\..\run.lnk'}),
            @(@{desktopAppId='MSEdge'},@{desktopAppId='msedge'}),@(@{desktopAppId=42}),@('MSEdge')
        )) { { ConvertTo-OSDAppDesktopPins -Pins $pins } | Should -Throw }
    }
    It 'rejects older builds, Home and Server instead of enforcing a recurring layout' {
        foreach ($platform in @(
            @{Build=22631;Revision=9999;InstallationType='Client';EditionId='Enterprise'},
            @{Build=26100;Revision=4769;InstallationType='Client';EditionId='Professional'},
            @{Build=26100;Revision=5000;InstallationType='Server';EditionId='ServerStandard'},
            @{Build=26100;Revision=5000;InstallationType='Client';EditionId='Core'}
        )) {
            { Assert-OSDAppStartPinsPlatform @platform } | Should -Throw
            { Assert-OSDAppTaskbarPinsPlatform @platform } | Should -Throw
        }
        { Assert-OSDAppStartPinsPlatform -Build 26100 -Revision 4770 -InstallationType Client -EditionId Professional } | Should -Not -Throw
        { Assert-OSDAppTaskbarPinsPlatform -Build 26100 -Revision 4770 -InstallationType Client -EditionId Professional } | Should -Not -Throw
        { Assert-OSDAppStartPinsPlatform -Build 26200 -Revision 1 -InstallationType Client -EditionId Enterprise } | Should -Not -Throw
    }
    It 'requires the file-based native ADMX mapping and rejects DTD content' {
        $dir=Join-Path $TestDrive 'Windows\PolicyDefinitions'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file=Join-Path $dir 'StartMenu.admx'
        '<policyDefinitions><policies><policy name="ConfigureStartPins" class="Both" key="Software\Policies\Microsoft\Windows\Explorer" valueName="ConfigureStartPins"><enabledValue><decimal value="1" /></enabledValue><elements><text id="ConfigureStartPins_Name" valueName="ConfigureStartPinsJSON" /></elements></policy></policies></policyDefinitions>' | Set-Content $file
        $mapping=Get-OSDAppStartPinsPolicy -WindowsDirectory (Split-Path $dir -Parent)
        $mapping.EnabledName | Should -Be ConfigureStartPins
        $mapping.FileName | Should -Be ConfigureStartPinsJSON
        '<policyDefinitions />' | Set-Content $file
        { Get-OSDAppStartPinsPolicy -WindowsDirectory (Split-Path $dir -Parent) } | Should -Throw
        '<!DOCTYPE test [<!ENTITY x SYSTEM "file:///missing">]><test>&x;</test>' | Set-Content $file
        { Get-OSDAppStartPinsPolicy -WindowsDirectory (Split-Path $dir -Parent) } | Should -Throw
    }
    It 'verifies the native Start Layout ADMX mapping used for taskbar replacement' {
        $dir=Join-Path $TestDrive 'TaskbarWindows\PolicyDefinitions'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file=Join-Path $dir 'StartMenu.admx'
        $valid='<policyDefinitions><policies><policy name="LockedStartLayout" class="Both" key="Software\Policies\Microsoft\Windows\Explorer" valueName="LockedStartLayout"><enabledValue><decimal value="1" /></enabledValue><elements><text id="StartLayout_Name" valueName="StartLayoutFile" expandable="true" /></elements></policy></policies></policyDefinitions>'
        $valid | Set-Content $file
        $mapping=Get-OSDAppTaskbarPinsPolicy -WindowsDirectory (Split-Path $dir -Parent)
        $mapping.Key | Should -Be 'Policies\Microsoft\Windows\Explorer'
        $mapping.FileName | Should -Be StartLayoutFile
        $mapping.EnabledName | Should -Be LockedStartLayout
        $mapping.FileKind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        $valid.Replace('<enabledValue><decimal value="1" /></enabledValue>','') | Set-Content $file
        (Get-OSDAppTaskbarPinsPolicy -WindowsDirectory (Split-Path $dir -Parent)).FileKind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        foreach ($invalid in @($valid.Replace('StartLayoutFile','WrongFile'),$valid.Replace('value="1"','value="0"'),$valid.Replace('class="Both"','class="User"'),'<!DOCTYPE test [<!ENTITY x SYSTEM "file:///missing">]><test>&x;</test>')) {
            $invalid | Set-Content $file
            { Get-OSDAppTaskbarPinsPolicy -WindowsDirectory (Split-Path $dir -Parent) } | Should -Throw
        }
    }
    It 'accepts the Start Layout mapping from the installed Windows ADMX' {
        $mapping=Get-OSDAppTaskbarPinsPolicy -WindowsDirectory $env:SystemRoot
        $mapping.EnabledName | Should -Be LockedStartLayout
        $mapping.FileName | Should -Be StartLayoutFile
        $mapping.FileKind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    It 'records each result independently without retrying failed settings' {
        Mock Set-OSDAppStartPinsConfiguration { throw 'Start policy failure fixture' }
        $config=[pscustomobject]@{SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\result.json';Operations=@(
            [pscustomobject]@{Kind='StartPins';Pins=@()},[pscustomobject]@{Kind='TaskbarPins';Pins=@()}
        )}
        $result=Invoke-OSDAppDesktopConfiguration -Configuration $config
        $result.Status | Should -Be Failed
        $result.SuccessfulOperationCount | Should -Be 1
        $result.Items[1].Detail.Outcome | Should -Be PreparedOffline
        $result.RebootRequested | Should -BeFalse
        Should -Invoke Set-OSDAppStartPinsConfiguration -Exactly 1
    }
    It 'stages both pin settings as one offline-ready queue entry and replaces only the requested list' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Assert-OSDAppOfflineStartPins { }
            Mock Set-OSDAppOfflineTaskbar {
                param($WindowsPath,$Pins,$Commit)
                $file=Join-Path $WindowsPath 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
                New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
                [IO.File]::WriteAllText($file,(ConvertTo-OSDAppTaskbarXml -Pins $Pins))
                & $Commit
            }
            $target=Join-Path $TestDrive 'Offline Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDAppStartPins -Pins @(@{desktopAppId='MSEdge'}) -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps') | Should -BeFalse
            Should -Invoke Assert-OSDAppOfflineStartPins -Exactly 0
            Add-OSDAppStartPins -Pins @(@{desktopAppId='MSEdge'}) -WindowsPath $target | Out-Null
            Add-OSDAppTaskbarPins -Pins @(@{desktopAppId='Microsoft.Windows.Explorer'}) -WindowsPath $target | Out-Null
            Add-OSDAppStartPins -Pins @(@{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}) -WindowsPath $target | Out-Null
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.AppCount | Should -Be 1
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $configPath=Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\DesktopSettings\config.json'
            $config=Get-Content $configPath -Raw | ConvertFrom-Json
            $config.Operations.Count | Should -Be 2
            ($config.Operations | Where-Object Kind -eq 'StartPins').Pins.Count | Should -Be 1
            { Remove-OSDAppStaging -Name DesktopSettings -WindowsPath $target -Confirm:$false } | Should -Throw '*already prepared*'
            $hash=(Get-FileHash $configPath).Hash
            Mock Add-OSDAppSetupComplete { throw 'fixture staging failure' }
            { Add-OSDAppStartPins -Pins @() -WindowsPath $target } | Should -Throw '*fixture*'
            (Get-FileHash $configPath).Hash | Should -Be $hash
            Add-Content $configPath 'tampered'
            { Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            { Add-OSDAppStartPins -Pins @() -WindowsPath $target } | Should -Throw '*not an intact*'
        }
    }
    It 'imports supported Start JSON, normalizes applyOnce, and rejects recurring configuration' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Save-OSDAppDesktopStaging { param($Operation) $Operation }
            $file=Join-Path $TestDrive 'pins.json'
            '{"pinnedList":[]}' | Set-Content $file
            $op=Add-OSDAppStartPins -JsonPath $file
            $op.Kind | Should -Be StartPins
            @($op.Pins).Count | Should -Be 0
            foreach ($json in @('{"applyOnce":false,"pinnedList":[]}','{"pinnedList":{}}','{"applyOnce":true}','{"pinnedList":[],"extra":1}')) {
                $json | Set-Content $file
                { Add-OSDAppStartPins -JsonPath $file } | Should -Throw
            }
        }
    }
    It 'rejects the preparation PC and disabled built-ins' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            { Add-OSDAppStartPins -Pins @() } | Should -Throw '*WinPE*'
            { Add-OSDAppTaskbarPins -Pins @() } | Should -Throw '*WinPE*'
            Mock Test-OSDAppWinPE { $true }
            Set-OSDAppConfiguration -EnableBuiltIns $false
            { Add-OSDAppStartPins -Pins @() } | Should -Throw '*disabled*'
        }
    }
    It 'runs the staged taskbar entry through preinstall and the packaged runner and rejects payload tampering' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Runner Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $results=Join-Path $TestDrive 'Results'
            Set-OSDAppConfiguration -LogPath (Join-Path $TestDrive 'Runtime.log') -ResultPath (Join-Path $results 'Latest.json') -PreventSleep $false
            # Native offline policy writes are covered separately with a disposable hive.
            Mock Set-OSDAppOfflineTaskbar {
                param($WindowsPath,$Pins,$Commit)
                $file=Join-Path $WindowsPath 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
                New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
                [IO.File]::WriteAllText($file,(ConvertTo-OSDAppTaskbarXml -Pins $Pins))
                & $Commit
            }
            try {
                Add-OSDAppTaskbarPins -Pins @(@{desktopAppId='Microsoft.Windows.Explorer'}) -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDApps'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppPreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                $report=Get-Content (Join-Path $results 'DesktopSettings-Result.json') -Raw | ConvertFrom-Json
                $report.Status | Should -Be Succeeded
                $report.Items[0].Detail.Outcome | Should -Be PreparedOffline
                $report.OperationCount | Should -Be 1
                $report.Items[0].Detail.PinCount | Should -Be 1
                Add-Content (Join-Path $stage 'BuiltIn\DesktopSettings\Install.ps1') '# tampered'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Not -Be 0
            }
            finally {
                Set-OSDAppConfiguration -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log' -ResultPath '%ProgramData%\OSDApps\Results\Latest.json' -PreventSleep $true }
        }
    }
}

Describe 'Desktop settings native registry and transaction boundaries' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDAppDesktopSettings.ps1')
    }
    It 'writes Start JSON and typed policy values into an isolated machine key' {
        $script:fixturePolicy='SOFTWARE\OSDAppsDesktopTest_' + [guid]::NewGuid().ToString('N')
        Mock Get-ItemProperty { [pscustomobject]@{CurrentBuildNumber='26100';UBR=4770;InstallationType='Client';EditionID='Enterprise'} }
        Mock Get-OSDAppStartPinsPolicy { [pscustomobject]@{Key=$script:fixturePolicy;EnabledName='ConfigureStartPins';FileName='ConfigureStartPinsJSON'} }
        $previousProgramData=$env:ProgramData
        try {
            $env:ProgramData=Join-Path $TestDrive 'ProgramData'
            $result=Set-OSDAppStartPinsConfiguration -Pins @(@{desktopAppId='MSEdge'},@{desktopAppId='Microsoft.Windows.Explorer'})
            $result.Outcome | Should -Be ConfiguredForFirstSignIn
            $json=Get-Content $result.Path -Raw | ConvertFrom-Json
            $json.applyOnce | Should -BeTrue
            $json.pinnedList[0].desktopAppId | Should -Be MSEdge
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
            $key=$base.OpenSubKey($script:fixturePolicy,$true)
            try {
                $key.GetValueKind('ConfigureStartPins').ToString() | Should -Be DWord
                $key.GetValue('ConfigureStartPins') | Should -Be 1
                $key.GetValueKind('ConfigureStartPinsJSON').ToString() | Should -Be String
                $key.GetValue('ConfigureStartPinsJSON') | Should -Be $result.Path
                $key.SetValue('Unrelated','preserved')
            }
            finally { $key.Dispose();$base.Dispose() }
            Set-OSDAppStartPinsConfiguration -Pins @() | Out-Null
            @((Get-Content $result.Path -Raw | ConvertFrom-Json).pinnedList).Count | Should -Be 0
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
            $key=$base.OpenSubKey($script:fixturePolicy,$true)
            try {
                $key.GetValue('Unrelated') | Should -Be preserved
                $key.SetValue('ConfigureStartPinsJSON','C:\Other\Layout.json')
            }
            finally { $key.Dispose();$base.Dispose() }
            $hash=(Get-FileHash $result.Path).Hash
            { Set-OSDAppStartPinsConfiguration -Pins @(@{desktopAppId='MSEdge'}) } | Should -Throw '*another configuration*'
            (Get-FileHash $result.Path).Hash | Should -Be $hash
        }
        finally {
            $env:ProgramData=$previousProgramData
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
            try { $base.DeleteSubKeyTree($script:fixturePolicy,$false) } finally { $base.Dispose() }
        }
    }
    It 'loads a disposable SOFTWARE hive, writes the future path and rolls back failed taskbar commits' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Hive Windows'
            $hive=Join-Path $target 'Windows\System32\Config\SOFTWARE'
            New-Item -ItemType Directory -Path (Split-Path $hive -Parent) -Force | Out-Null
            $fixture='OSDAppsHiveTest_' + [guid]::NewGuid().ToString('N')
            $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture)
            try {
                $cv=$key.CreateSubKey('Microsoft\Windows NT\CurrentVersion')
                try {
                    $cv.SetValue('InstallationType','Client');$cv.SetValue('CurrentBuildNumber','26100')
                    $cv.SetValue('SystemRoot','C:\Windows');$cv.SetValue('EditionID','Enterprise');$cv.SetValue('UBR',4770)
                }
                finally { $cv.Dispose() }
                $key.Flush()
                & reg.exe save ('HKCU\' + $fixture) $hive /y | Out-Null
                $LASTEXITCODE | Should -Be 0
            }
            finally { $key.Dispose();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($fixture,$false) }
            $admxDir=Join-Path $target 'Windows\PolicyDefinitions'
            New-Item -ItemType Directory -Path $admxDir -Force | Out-Null
            '<policyDefinitions><policies><policy name="LockedStartLayout" class="Both" key="Software\Policies\Microsoft\Windows\Explorer" valueName="LockedStartLayout"><enabledValue><decimal value="1" /></enabledValue><elements><text id="StartLayout_Name" valueName="StartLayoutFile" expandable="true" /></elements></policy></policies></policyDefinitions>' | Set-Content (Join-Path $admxDir 'StartMenu.admx')
            $pins=@(@{desktopAppId='MSEdge'},@{desktopAppId='Microsoft.Windows.Explorer'})
            # Initial failure must remove both policy values and the file.
            { Set-OSDAppOfflineTaskbar -WindowsPath $target -Pins $pins -Commit { throw 'first commit failed' } } | Should -Throw '*first commit failed*'
            Invoke-OSDAppOfflineSoftware -WindowsPath $target -Action {
                param($Software)
                $key=$Software.OpenSubKey('Policies\Microsoft\Windows\Explorer')
                try {
                    $key.GetValue('StartLayoutFile') | Should -BeNullOrEmpty
                    $key.GetValue('LockedStartLayout') | Should -BeNullOrEmpty
                } finally { $key.Dispose() }
            }
            Test-Path (Join-Path $target 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml') | Should -BeFalse
            Set-OSDAppOfflineTaskbar -WindowsPath $target -Pins $pins -Commit { }
            $file=Join-Path $target 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
            [IO.File]::ReadAllText($file) | Should -Be (ConvertTo-OSDAppTaskbarXml -Pins $pins)
            Invoke-OSDAppOfflineSoftware -WindowsPath $target -Action {
                param($Software)
                $key=$Software.OpenSubKey('Policies\Microsoft\Windows\Explorer')
                try {
                    $key.GetValue('StartLayoutFile') | Should -Be 'C:\Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
                    $key.GetValueKind('StartLayoutFile').ToString() | Should -Be ExpandString
                    $key.GetValue('LockedStartLayout') | Should -Be 1
                    $key.GetValueKind('LockedStartLayout').ToString() | Should -Be DWord
                } finally { $key.Dispose() }
                $Software.OpenSubKey('Microsoft\Windows\CurrentVersion\Explorer') | Should -BeNullOrEmpty
            }
            $hash=(Get-FileHash $file).Hash
            { Set-OSDAppOfflineTaskbar -WindowsPath $target -Pins @() -Commit { throw 'commit failed fixture' } } | Should -Throw '*commit failed fixture*'
            (Get-FileHash $file).Hash | Should -Be $hash
            Invoke-OSDAppOfflineSoftware -WindowsPath $target -Action {
                param($Software)
                $key=$Software.OpenSubKey('OSDApps\DesktopSettings')
                try { $key.GetValue('TaskbarSha256') | Should -Be $hash } finally { $key.Dispose() }
            }
            # Foreign policy is refused without touching layout, ownership or unrelated Start policy.
            Invoke-OSDAppOfflineSoftware -WindowsPath $target -Action {
                param($Software)
                $key=$Software.OpenSubKey('Policies\Microsoft\Windows\Explorer',$true)
                try {
                    $key.SetValue('StartLayoutFile','C:\Other\Layout.xml')
                    $key.SetValue('ConfigureStartPins',1,[Microsoft.Win32.RegistryValueKind]::DWord)
                } finally { $key.Dispose() }
            }
            { Set-OSDAppOfflineTaskbar -WindowsPath $target -Pins @() -Commit { } } | Should -Throw '*not an intact*'
            (Get-FileHash $file).Hash | Should -Be $hash
            Invoke-OSDAppOfflineSoftware -WindowsPath $target -Action {
                param($Software)
                $key=$Software.OpenSubKey('Policies\Microsoft\Windows\Explorer',$true)
                try {
                    $key.GetValue('StartLayoutFile') | Should -Be 'C:\Other\Layout.xml'
                    $key.GetValue('ConfigureStartPins') | Should -Be 1
                    $key.SetValue('StartLayoutFile','C:\Windows\OEM\OSDApps\TaskbarLayoutModification.xml',[Microsoft.Win32.RegistryValueKind]::ExpandString)
                } finally { $key.Dispose() }
            }
            Add-Content $file 'foreign edit'
            { Set-OSDAppOfflineTaskbar -WindowsPath $target -Pins @() -Commit { } } | Should -Throw '*not an intact*'
            # An exclusive file open proves the registry hive is no longer mounted.
            $stream=[IO.File]::Open($hive,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            $stream.Dispose()
        }
    }
}
