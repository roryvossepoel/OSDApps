Describe 'Repository images and Windows background modes' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        $script:png=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5foAAAAASUVORK5CYII=')
        $script:source=Join-Path $TestDrive 'Source'
        New-Item -ItemType Directory -Path $script:source | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $script:source 'background.png'),$script:png)
        $script:package=New-OSDAppPackage -Id TestImage -Version 1.0.0 -PackageType Image -SourcePath $script:source -OutputPath (Join-Path $TestDrive 'Build')
    }
    It 'round trips Image through publication cache and repository validation' {
        InModuleScope OSDApps -Parameters @{PackagePath=$script:package.PackagePath} {
            param($PackagePath)
            $repo=Join-Path $TestDrive 'Repo';$cache=Join-Path $TestDrive 'Cache'
            New-OSDAppRepository -Path $repo | Out-Null
            Add-OSDAppPackage -Id TestImage -DisplayName 'Test image' -Version 1.0.0 -PackageType Image -Architecture any -PackagePath $PackagePath -RepositoryPath $repo | Out-Null
            @(Test-OSDAppRepository -RepositoryPath $repo)[0].Valid | Should -BeTrue
            Sync-OSDAppCache -CatalogPath (Join-Path $repo 'catalog.json') -CachePath $cache -Confirm:$false | Out-Null
            (Get-Content (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json).Packages[0].PackageType | Should -Be Image
            @(Test-OSDAppRepositoryCache -CachePath $cache -Name TestImage)[0].Valid | Should -BeTrue
            {Copy-OSDAppContent -Name TestImage -CachePath $cache -WindowsPath (Join-Path $TestDrive 'NoScriptTarget')} | Should -Throw '*cannot be queued as scripts*'
            Test-Path (Join-Path $TestDrive 'NoScriptTarget') | Should -BeFalse
            Add-Content (Join-Path $cache 'Packages\TestImage\Package.zip') 'corrupt'
            @(Test-OSDAppRepositoryCache -CachePath $cache -Name TestImage)[0].Valid | Should -BeFalse
        }
    }
    It 'rejects executable siblings and invalid image bytes before packaging' {
        $bad=Join-Path $TestDrive 'Bad';New-Item -ItemType Directory -Path $bad | Out-Null
        Copy-Item (Join-Path $script:source 'background.png') $bad
        Set-Content (Join-Path $bad 'Install.ps1') 'throw "must never execute"'
        {New-OSDAppPackage -Id Bad -Version 1 -PackageType Image -SourcePath $bad -OutputPath (Join-Path $TestDrive 'BadOutput')} | Should -Throw '*exactly one*'
        Remove-Item (Join-Path $bad 'Install.ps1')
        Set-Content (Join-Path $bad 'background.png') ('not an image '*10)
        {New-OSDAppPackage -Id Bad -Version 1 -PackageType Image -SourcePath $bad -OutputPath (Join-Path $TestDrive 'BadOutput')} | Should -Throw '*PNG*'
    }
    It 'rejects archive traversal before extracting' {
        InModuleScope OSDApps {
            $path=Join-Path $TestDrive 'Traversal.zip'
            $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
            try { $entry=$zip.CreateEntry('../escaped.png');$stream=$entry.Open();try { $stream.Write([byte[]]::new(64),0,64) } finally { $stream.Dispose() } } finally { $zip.Dispose() }
            {Assert-OSDAppImageArchive -Path $path} | Should -Throw '*traversal*'
            Test-Path (Join-Path $TestDrive 'escaped.png') | Should -BeFalse
        }
    }
    It 'rejects junction sources without following them' {
        $path=Join-Path $TestDrive 'Junction';New-Item -ItemType Junction -Path $path -Target $script:source | Out-Null
        {New-OSDAppPackage -Id Link -Version 1 -PackageType Image -SourcePath $path -OutputPath (Join-Path $TestDrive 'LinkOutput')} | Should -Throw '*reparse*'
    }
    It 'does not inspect targets acquire content or stage on WhatIf' {
        InModuleScope OSDApps {
            Mock Save-OSDAppBackground {throw 'must not run'}
            Add-OSDAppWallpaper -Id TestImage -WhatIf
            Add-OSDAppLockScreen -Id TestImage -Enforce -WhatIf
            Should -Invoke Save-OSDAppBackground -Times 0 -Exactly
        }
    }
    It 'passes the two independent enforcement choices through the public interface' {
        InModuleScope OSDApps {
            Mock Save-OSDAppBackground {}
            Add-OSDAppWallpaper -Id Finance -SkipCacheRefresh
            Add-OSDAppLockScreen -Id Operations -Enforce
            Should -Invoke Save-OSDAppBackground -Times 1 -Exactly -ParameterFilter {$Kind -eq 'Wallpaper' -and -not $Enforce -and $SkipCacheRefresh}
            Should -Invoke Save-OSDAppBackground -Times 1 -Exactly -ParameterFilter {$Kind -eq 'LockScreen' -and $Enforce}
        }
    }
    It 'keeps Pro support limited to default wallpaper' {
        InModuleScope OSDApps {
            Assert-OSDAppBackgroundPlatform -Build 26100 -InstallationType Client -EditionId Professional -Operation @{Kind='Wallpaper';Enforce=$false}
            foreach ($op in @(@{Kind='Wallpaper';Enforce=$true},@{Kind='LockScreen';Enforce=$false},@{Kind='LockScreen';Enforce=$true})) {
                {Assert-OSDAppBackgroundPlatform -Build 26100 -InstallationType Client -EditionId Professional -Operation $op} | Should -Throw '*Enterprise/Education*'
                Assert-OSDAppBackgroundPlatform -Build 26100 -InstallationType Client -EditionId Enterprise -Operation $op
            }
            {Assert-OSDAppBackgroundPlatform -Build 20348 -InstallationType Server -EditionId ServerStandard -Operation @{Kind='Wallpaper';Enforce=$false}} | Should -Throw '*Windows 11 client*'
        }
    }
    It 'merges default wallpaper without changing existing OOBE language or color settings' {
        InModuleScope OSDApps {
            $old='<unattend xmlns="urn:schemas-microsoft-com:unattend"><settings pass="oobeSystem"><component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"><OOBE><HideEULAPage>true</HideEULAPage></OOBE><Themes><ThemeName>Existing name</ThemeName><WindowColor>Automatic</WindowColor></Themes></component><component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"><UILanguage>nl-NL</UILanguage></component></settings></unattend>'
            [xml]$new=ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml $old -ImagePath 'C:\Windows\OEM\OSDApps\Branding\Finance\image.png' -Architecture amd64
            $new.OuterXml | Should -Match 'HideEULAPage>true'
            $new.OuterXml | Should -Match 'UILanguage>nl-NL'
            $new.OuterXml | Should -Match 'ThemeName>Existing name'
            $new.OuterXml | Should -Match 'WindowColor>Automatic'
            $new.OuterXml | Should -Match 'DesktopBackground>C:\\Windows'
            $new.OuterXml | Should -Not -Match 'UWPAppsUseLightTheme'
            {ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml $new.OuterXml -ImagePath 'C:\other.png' -Architecture amd64} | Should -Throw '*already defines*'
            {ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml $old -ImagePath 'C:\other.png' -Architecture arm64} | Should -Throw '*architecture*'
        }
    }
    It 'rejects DTD and processed answer files' {
        InModuleScope OSDApps {
            {ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml '<!DOCTYPE unattend [<!ENTITY a "bad">]><unattend xmlns="urn:schemas-microsoft-com:unattend" />' -ImagePath 'C:\image.png' -Architecture amd64} | Should -Throw
            {ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml '<unattend xmlns="urn:schemas-microsoft-com:unattend"><settings pass="oobeSystem" wasPassProcessed="true" /></unattend>' -ImagePath 'C:\image.png' -Architecture amd64} | Should -Throw '*already processed*'
        }
    }
    It 'restores exact answer-file bytes and removes a new image when staging commit fails' {
        InModuleScope OSDApps -Parameters @{Source=$script:source} {
            param($Source)
            $target=Join-Path $TestDrive 'RollbackTarget';$answer=Join-Path $target 'Windows\Panther\unattend.xml'
            New-Item -ItemType Directory -Path (Split-Path $answer -Parent) -Force | Out-Null
            $original='<unattend xmlns="urn:schemas-microsoft-com:unattend" />'
            [IO.File]::WriteAllText($answer,$original,[Text.UnicodeEncoding]::new($false,$true))
            $bytes=[Convert]::ToBase64String([IO.File]::ReadAllBytes($answer))
            Mock Get-OSDAppBackgroundTarget {[pscustomobject]@{SystemRoot='C:\Windows'}}
            Mock Get-OSDAppBackgroundAnswerFile {$answer}
            Mock Get-OSDAppBackgroundArchitecture {'amd64'}
            $sourceFile=Join-Path $Source 'background.png';$hash=(Get-FileHash $sourceFile).Hash
            $op=[pscustomobject]@{Kind='Wallpaper';Id='Test';FutureSystemRoot='C:\Windows';Enforce=$false;ImageSha256=$hash;Extension='.png';ImageRelativePath=('OEM\OSDApps\Branding\Test\'+$hash+'.png')}
            {Set-OSDAppOfflineBackground -WindowsPath $target -Operation $op -SourcePath $sourceFile -Commit {throw 'simulated manifest failure'}} | Should -Throw '*simulated manifest failure*'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($answer)) | Should -Be $bytes
            Test-Path (Join-Path (Join-Path $target 'Windows') $op.ImageRelativePath) | Should -BeFalse
        }
    }
    It 'uses native installed ADMX for the default lock screen mapping' {
        InModuleScope OSDApps {
            $mapping=Get-OSDAppLockScreenPolicy
            $mapping.Name | Should -Be 'LockScreenImage'
            $mapping.Key | Should -Be 'Policies\Microsoft\Windows\Personalization'
        }
    }
    It 'refuses conflicting native policies and disposes test registry handles' {
        InModuleScope OSDApps {
            $name='Software\OSDAppsBackgroundTest_'+[guid]::NewGuid().ToString('N')
            $software=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($name)
            try {
                $key=$software.CreateSubKey('Policies\Microsoft\Windows\Personalization')
                try { $key.SetValue('NoChangingLockScreen',1,[Microsoft.Win32.RegistryValueKind]::DWord) } finally { $key.Dispose() }
                {Assert-OSDAppBackgroundPolicyState -Software $software -Operation @{Kind='LockScreen'}} | Should -Throw '*conflicts*'
                Assert-OSDAppBackgroundPolicyState -Software $software -Operation @{Kind='Wallpaper'}
            }
            finally { $software.Dispose();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($name,$false) }
        }
    }
    It 'changes only the requested CSP property and reads status instead of writing success' {
        InModuleScope OSDApps {
            $script:csp=[Microsoft.Management.Infrastructure.CimInstance]::new('MDM_Personalization')
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageUrl','',[Microsoft.Management.Infrastructure.CimType]::String,[Microsoft.Management.Infrastructure.CimFlags]::None))
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageStatus',[int]1,[Microsoft.Management.Infrastructure.CimType]::SInt32,[Microsoft.Management.Infrastructure.CimFlags]::None))
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('LockScreenImageUrl','file:///C:/keep.png',[Microsoft.Management.Infrastructure.CimType]::String,[Microsoft.Management.Infrastructure.CimFlags]::None))
            Mock Get-CimInstance {$script:csp}
            Mock Set-CimInstance {param($Property) $script:csp.CimInstanceProperties['DesktopImageUrl'].Value=$Property.DesktopImageUrl}
            Mock New-CimInstance {throw 'must preserve existing instance'}
            $result=Set-OSDAppBackgroundCsp -Operation @{Kind='Wallpaper'} -ImagePath 'C:\Windows\OEM\OSDApps\Branding\wall.png'
            $result.Outcome | Should -Be Applied
            $script:csp.LockScreenImageUrl | Should -Be 'file:///C:/keep.png'
            Should -Invoke Set-CimInstance -Times 1 -Exactly -ParameterFilter {$Property.Count -eq 1 -and $Property.ContainsKey('DesktopImageUrl')}
        }
    }
    It 'does not overwrite an existing CSP image' {
        InModuleScope OSDApps {
            Mock Get-CimInstance {[pscustomobject]@{DesktopImageUrl='https://example.test/managed.png'}}
            Mock Set-CimInstance {throw 'must not write'}
            {Set-OSDAppBackgroundCsp -Operation @{Kind='Wallpaper'} -ImagePath 'C:\new.png'} | Should -Throw '*already configured*'
            Should -Invoke Set-CimInstance -Times 0 -Exactly
        }
    }
    It 'rolls back a failed CSP image without retrying' {
        InModuleScope OSDApps {
            $script:csp=[Microsoft.Management.Infrastructure.CimInstance]::new('MDM_Personalization')
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageUrl','',[Microsoft.Management.Infrastructure.CimType]::String,[Microsoft.Management.Infrastructure.CimFlags]::None))
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageStatus',[int]3,[Microsoft.Management.Infrastructure.CimType]::SInt32,[Microsoft.Management.Infrastructure.CimFlags]::None))
            Mock Get-CimInstance {$script:csp}
            Mock Set-CimInstance {param($Property) $script:csp.CimInstanceProperties['DesktopImageUrl'].Value=$Property.DesktopImageUrl}
            {Set-OSDAppBackgroundCsp -Operation @{Kind='Wallpaper'} -ImagePath 'C:\new.png'} | Should -Throw '*status*'
            $script:csp.DesktopImageUrl | Should -Be ''
            Should -Invoke Set-CimInstance -Times 2 -Exactly
        }
    }
    It 'reports a provider copy in progress without claiming a rendered image' {
        InModuleScope OSDApps {
            $script:csp=[Microsoft.Management.Infrastructure.CimInstance]::new('MDM_Personalization')
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageUrl','',[Microsoft.Management.Infrastructure.CimType]::String,[Microsoft.Management.Infrastructure.CimFlags]::None))
            $script:csp.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('DesktopImageStatus',[int]2,[Microsoft.Management.Infrastructure.CimType]::SInt32,[Microsoft.Management.Infrastructure.CimFlags]::None))
            Mock Get-CimInstance {$script:csp}
            Mock Set-CimInstance {param($Property) $script:csp.CimInstanceProperties['DesktopImageUrl'].Value=$Property.DesktopImageUrl}
            (Set-OSDAppBackgroundCsp -Operation @{Kind='Wallpaper'} -ImagePath 'C:\new.png').Outcome | Should -Be Submitted
        }
    }
    It 'stages both images in the shared desktop queue and detects persistent image tampering' {
        InModuleScope OSDApps -Parameters @{PackagePath=$script:package.PackagePath} {
            param($PackagePath)
            $repo=Join-Path $TestDrive 'StageRepo';$cache=Join-Path $TestDrive 'StageCache';$target=Join-Path $TestDrive 'StageTarget'
            New-OSDAppRepository -Path $repo | Out-Null
            Add-OSDAppPackage -Id TestImage -DisplayName 'Test image' -Version 1.0.0 -PackageType Image -Architecture any -PackagePath $PackagePath -RepositoryPath $repo | Out-Null
            Sync-OSDAppCache -CatalogPath (Join-Path $repo 'catalog.json') -CachePath $cache -Confirm:$false | Out-Null
            $script:backgroundCache=$cache;$script:backgroundTarget=$target
            Mock Test-OSDAppWinPE {$true};Mock Get-OSDAppCachePath {$script:backgroundCache}
            Mock Get-OSDAppBackgroundTarget {[pscustomobject]@{SystemRoot='C:\Windows'}}
            Mock Get-OSDAppLockScreenPolicy {[pscustomobject]@{Key='Policies\Microsoft\Windows\Personalization';Name='LockScreenImage'}}
            Mock Get-OSDAppBackgroundAnswerFile {Join-Path $script:backgroundTarget 'Windows\Panther\unattend.xml'}
            Mock Get-OSDAppBackgroundArchitecture {'amd64'}
            New-Item -ItemType Directory -Path $target | Out-Null
            Set-OSDAppConfiguration -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never
            Add-OSDAppWallpaper -Id TestImage -WindowsPath $target -SkipCacheRefresh | Out-Null
            Add-OSDAppLockScreen -Id TestImage -Enforce -WindowsPath $target -SkipCacheRefresh | Out-Null
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.AppCount | Should -Be 1
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $config=Get-Content (Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\DesktopSettings\config.json') -Raw | ConvertFrom-Json
            $config.Operations.Count | Should -Be 2
            $config.Operations[0].Enforce | Should -BeFalse
            $config.Operations[1].Enforce | Should -BeTrue
            {Add-OSDAppWallpaper -Id TestImage -WindowsPath $target -SkipCacheRefresh} | Should -Throw '*already staged*'
            $image=Join-Path (Join-Path $target 'Windows') $config.Operations[0].ImageRelativePath
            Add-Content $image 'tampered'
            {Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure} | Should -Throw
        }
    }
}

Describe 'Background documentation' {
    It 'validates links and public command examples' {
        $root=Split-Path $PSScriptRoot -Parent
        & (Join-Path $root 'build\Test-Documentation.ps1') -Root $root -Files @((Join-Path $root 'docs\wallpaper-lockscreen-design.md'))
    }
}
