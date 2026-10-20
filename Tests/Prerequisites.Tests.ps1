BeforeAll {
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function global:Get-AuthenticodeSignature { param([string]$LiteralPath) throw 'Windows trust evaluation is unavailable.' }
    }
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force
}
Describe 'Runtime selection and staging' {
    It 'preserves x86/x64 and multiple .NET variants, de-duplicates and orders prerequisites first' {
        InModuleScope OSDApps {
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            Mock Get-OSDAppPrerequisiteRelease { throw 'Must not download in WinPE' }
            $windows = Join-Path $TestDrive 'Windows'
            New-Item -ItemType Directory $windows -Force | Out-Null
            Add-OSDAppVisualStudioCode -WindowsPath $windows
            Add-OSDAppVisualCppRedist -WindowsPath $windows
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 8.0 -RuntimeType Runtime
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 10.0 -RuntimeType Desktop
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 10.0 -RuntimeType Runtime -Architecture x86
            Add-OSDAppVisualCppRedist -WindowsPath $windows -Architecture x64
            $stage = Join-Path $windows 'Windows/Temp/OSDApps'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 6
            @($manifest.Apps.Id | Select-Object -Unique).Count | Should -Be 6
            $manifest.Apps[-1].Id | Should -Be 'VisualStudioCode'
            $manifest.Apps.Id | Should -Contain 'VisualCppRedist-x86'
            $manifest.Apps.Id | Should -Contain 'VisualCppRedist-x64'
            $manifest.Apps.Id | Should -Contain 'DotNetRuntime-Runtime-8.0-x64'
            $manifest.Apps.Id | Should -Contain 'DotNetRuntime-Desktop-10.0-x64'
            Test-Path (Join-Path $stage 'OSDAppPrerequisite.ps1') | Should -BeTrue
            Should -Invoke Get-OSDAppPrerequisiteRelease -Times 0 -Exactly
        }
    }
    It 'does not stage with WhatIf' {
        InModuleScope OSDApps {
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            $windows = Join-Path $TestDrive 'WhatIf'
            Add-OSDAppVisualCppRedist -WindowsPath $windows -WhatIf
            Add-OSDAppDotNetRuntime -WindowsPath $windows -WhatIf
            Test-Path $windows | Should -BeFalse
        }
    }
    It 'rejects unsafe and preview channel strings' {
        { Add-OSDAppDotNetRuntime -Channel '../10.0' } | Should -Throw
        { Add-OSDAppDotNetRuntime -Channel '11.0-preview' } | Should -Throw
    }
}
Describe 'Runtime release selection and transaction integrity' {
    BeforeEach {
        InModuleScope OSDApps {
            $script:spec = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -RuntimeType Desktop -Channel 10.0
            $script:payload = [Text.Encoding]::UTF8.GetBytes('runtime fixture')
            $sha = [Security.Cryptography.SHA512]::Create()
            try { $script:hash = ([BitConverter]::ToString($sha.ComputeHash($script:payload))).Replace('-','') } finally { $sha.Dispose() }
            $script:component = [pscustomobject]@{ version='10.0.1'; files=@([pscustomobject]@{name='windowsdesktop-runtime-win-x64.exe';rid='win-x64';url='https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.1/windowsdesktop-runtime-10.0.1-win-x64.exe';hash=$script:hash}) }
            $script:metadata = [pscustomobject]@{ 'channel-version'='10.0';'support-phase'='active';'latest-runtime'='10.0.1';releases=@([pscustomobject]@{'release-version'='10.0.1';windowsdesktop=$script:component;runtime=$script:component}) }
            Mock Invoke-RestMethod { $script:metadata }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'}} }
            Mock Assert-OSDAppTransactionSpace { }
            $script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:downloadCount = 0
            $script:download = {param($uri,$path) $script:downloadCount++; [IO.File]::WriteAllBytes($path,$script:payload)}
        }
    }
    It 'selects desktop and standalone EXEs using separate official metadata fields' {
        InModuleScope OSDApps {
            (Get-OSDAppPrerequisiteRelease -Spec $script:spec).PackageUri | Should -Match '/WindowsDesktop/'
            $script:metadata.releases[0].runtime = [pscustomobject]@{version='10.0.1';files=@([pscustomobject]@{name='dotnet-runtime-win-x86.exe';rid='win-x86';url='https://builds.dotnet.microsoft.com/dotnet/Runtime/10.0.1/dotnet-runtime-10.0.1-win-x86.exe';hash=$script:hash})}
            $runtime = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x86 -RuntimeType Runtime -Channel 10.0
            (Get-OSDAppPrerequisiteRelease -Spec $runtime).PackageUri | Should -Match '/Runtime/10.0.1/dotnet-runtime-10.0.1-win-x86.exe$'
        }
    }
    It 'rejects preview, foreign URL, missing digest and duplicate installers' {
        InModuleScope OSDApps {
            $script:metadata.'support-phase'='preview'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*Preview*'
            $script:metadata.'support-phase'='active';$script:metadata.'latest-runtime'='10.0.2-rc.1'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*stable*'
            $script:metadata.'latest-runtime'='10.0.1';$script:component.files[0].url='https://example.com/runtime.exe'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*URL*'
            $script:component.files[0].hash=''
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*SHA-512*'
            $script:component.files[0].hash=$script:hash; $script:component.files=@($script:component.files[0],$script:component.files[0])
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*one*'
        }
    }
    It 'warns for EOL while acquiring and reusing a fully verified stable generation' {
        InModuleScope OSDApps {
            $script:metadata.'support-phase'='eol'
            $first = Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download -WarningVariable warnings -WarningAction SilentlyContinue
            $first.Updated | Should -BeTrue
            $first.SupportWarning | Should -Match 'end of support'
            ($warnings -join ' ') | Should -Match 'end of support'
            $second = Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download -WarningAction SilentlyContinue
            $second.Updated | Should -BeFalse
            $second.Version | Should -Be '10.0.1'
            $script:downloadCount | Should -Be 1
        }
    }
    It 'tolerates missing or unknown lifecycle status under strict mode without relaxing channel checks' {
        InModuleScope OSDApps {
            Set-StrictMode -Version Latest
            $script:metadata.PSObject.Properties.Remove('support-phase')
            (Get-OSDAppPrerequisiteRelease -Spec $script:spec -WarningAction SilentlyContinue).SupportWarning | Should -Match 'could not be confirmed'
            $script:metadata | Add-Member -NotePropertyName 'support-phase' -NotePropertyValue 'future-status'
            (Get-OSDAppPrerequisiteRelease -Spec $script:spec -WarningAction SilentlyContinue).Version | Should -Be '10.0.1'
            $script:metadata.'channel-version'='9.0'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*requested channel*'
        }
    }
    It 'still rejects a corrupt candidate for an EOL channel' {
        InModuleScope OSDApps {
            $script:metadata.'support-phase'='eol'
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download {param($u,$p) Set-Content $p 'wrong'} -WarningAction SilentlyContinue } | Should -Throw '*SHA-512*'
            Test-Path $script:cache | Should -BeFalse
        }
    }
    It 'reuses a verified generation and rejects content or selection mismatch' {
        InModuleScope OSDApps {
            (Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download).Updated | Should -BeTrue
            (Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download).Updated | Should -BeFalse
            $script:downloadCount | Should -Be 1
            $other = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x86 -Channel 10.0
            { Assert-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $other } | Should -Throw '*incompatible*'
            Add-Content (Join-Path $script:cache 'Package.exe') 'corrupt'
            { Assert-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec } | Should -Throw '*SHA-256*'
        }
    }
    It 'preserves the old generation after a bad candidate digest and removes temporary folders' {
        InModuleScope OSDApps {
            Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $before = (Get-FileHash (Join-Path $script:cache 'Package.exe')).Hash
            $script:metadata.'latest-runtime'='10.0.2';$script:metadata.releases[0].'release-version'='10.0.2';$script:component.version='10.0.2';$script:component.files[0].url=$script:component.files[0].url.Replace('10.0.1','10.0.2')
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download {param($u,$p) Set-Content $p 'wrong'} } | Should -Throw '*SHA-512*'
            (Get-FileHash (Join-Path $script:cache 'Package.exe')).Hash | Should -Be $before
            @(Get-ChildItem (Split-Path $script:cache) -Filter "$(Split-Path $script:cache -Leaf).osdapps-*").Count | Should -Be 0
        }
    }
    It 'rejects an untrusted publisher before promotion' {
        InModuleScope OSDApps {
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Other Corporation'}} }
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download } | Should -Throw '*Microsoft Corporation*'
            Test-Path $script:cache | Should -BeFalse
        }
    }
}

Describe 'Runtime PreInstall and Runner dispatch' {
    BeforeAll {
        $script:runtimeRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime'
        . (Join-Path $runtimeRoot 'OSDAppPrerequisite.ps1')
        . (Join-Path $runtimeRoot 'Assert-OSDAppTransactionSpace.ps1')
        . (Join-Path $runtimeRoot 'Restore-OSDAppCacheGeneration.ps1')
        . (Join-Path $runtimeRoot 'Invoke-OSDAppBuiltInCacheTransaction.ps1')
        $tokens=$null;$errors=$null
        $preAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtimeRoot 'Invoke-OSDAppPreInstall.ps1'),[ref]$tokens,[ref]$errors)
        foreach($f in $preAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($f.Extent.Text)) }
        $switch=$preAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Extent.Text -like '*PrerequisiteExe*' }).Count -gt 0},$true)
        $script:preCase=[scriptblock]::Create(@($switch.Clauses | Where-Object { $_.Item1.Extent.Text -like '*PrerequisiteExe*' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
        $runAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtimeRoot 'Invoke-OSDAppRunner.ps1'),[ref]$tokens,[ref]$errors)
        $switch=$runAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Value -eq 'PrerequisiteExe' }).Count -gt 0},$true)
        $runText=@($switch.Clauses | Where-Object { $_.Item1.Value -eq 'PrerequisiteExe' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
        # The real helper is loaded above. Keep the Windows registry boundary mocked.
        $runText=$runText.Replace(". (Join-Path `$PSScriptRoot 'OSDAppPrerequisite.ps1')",'')
        $script:runCase=[scriptblock]::Create($runText)
        function Write-RunnerLog { param($LogPath,$Event,$Message,$Data,$Level) }
        function New-PrerequisiteFixture {
            param($Path,$Spec)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Set-Content (Join-Path $Path 'Package.exe') 'runtime fixture'
            $version=if($Spec.Family -eq 'VisualCppRedist'){'14.50.1.0'}else{'10.0.1'}
            $uri=if($Spec.Family -eq 'VisualCppRedist'){"https://aka.ms/vc14/vc_redist.$($Spec.Architecture).exe"}else{'https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.1/windowsdesktop-runtime-10.0.1-win-x64.exe'}
            @{ Id=$Spec.Family;VariantId=$Spec.Id;Architecture=$Spec.Architecture;RuntimeType=$Spec.RuntimeType;Channel=$Spec.Channel;Version=$version;PackageUri=$uri;Size=(Get-Item (Join-Path $Path 'Package.exe')).Length;Sha256=(Get-FileHash (Join-Path $Path 'Package.exe')).Hash;Sha512=(Get-FileHash (Join-Path $Path 'Package.exe') -Algorithm SHA512).Hash } | ConvertTo-Json | Set-Content (Join-Path $Path 'CacheInfo.json')
        }
    }
    BeforeEach {
        $script:spec=Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -Channel 10.0
        $script:app=[pscustomobject]@{Id=$spec.Id;Family=$spec.Family;Architecture=$spec.Architecture;RuntimeType=$spec.RuntimeType;Channel=$spec.Channel;Type='PrerequisiteExe';Package=(Join-Path $spec.RelativeRoot 'Package.exe');DisplayName=$spec.DisplayName;InstallTimeoutMinutes=10}
        $script:StagedPath=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:logPath=Join-Path $StagedPath 'runtime.log'
        $script:usbRoot=$null;$script:networkAvailable=$true;$script:acquisition=@{}
        $script:installerStarted=$false
        Mock Write-RunnerLog { }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}} }
        Mock Get-OSDAppPrerequisiteRelease { throw 'Metadata unavailable' }
        Mock Get-OSDAppInstalledPrerequisiteVersion { if($script:installerStarted){[version]'10.0.1'} }
        Mock Start-Process { $script:installerStarted=$true; [pscustomobject]@{HasExited=$true;ExitCode=0} }
    }
    It 'records valid fallback and offline use without claiming confirmed currency' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        & $script:preCase
        $acquisition.Outcome | Should -Be 'FallbackCacheUsed'
        $script:networkAvailable=$false
        & $script:preCase
        $acquisition.Outcome | Should -Be 'OfflineCacheUsed'
        Should -Invoke Get-OSDAppPrerequisiteRelease -Times 1 -Exactly
    }
    It 'fails without valid content and does not accept another requested variant' {
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        $app.Architecture='x86'
        { & $script:preCase } | Should -Throw '*identity*'
    }
    It 'rejects corrupt, wrong-channel and untrusted staged fallback during a metadata outage' {
        $root = Join-Path $StagedPath $spec.RelativeRoot
        New-PrerequisiteFixture $root $spec
        Add-Content (Join-Path $root 'Package.exe') 'corrupt'
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        New-PrerequisiteFixture $root $spec
        $info = Get-Content (Join-Path $root 'CacheInfo.json') -Raw | ConvertFrom-Json
        $info.Channel='9.0'
        $info | ConvertTo-Json | Set-Content (Join-Path $root 'CacheInfo.json')
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        New-PrerequisiteFixture $root $spec
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Other Corporation'}} }
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'persists the advisory lifecycle warning in the deployment log' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Mock Sync-OSDAppPrerequisiteGeneration { [pscustomobject]@{Updated=$false;SupportWarning='.NET 10.0 is end of support.'} }
        Mock Write-PreInstallLog { }
        & $script:preCase
        $acquisition.Outcome | Should -Be 'CacheReused'
        Should -Invoke Write-PreInstallLog -Times 1 -Exactly -ParameterFilter { $Event -eq 'RuntimeSupportWarning' -and $Level -eq 'Warning' }
    }
    It 'uses silent install without reboot and confirms the installed version' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -eq '/install /quiet /norestart' }
        Should -Invoke Get-OSDAppInstalledPrerequisiteVersion -Times 2 -Exactly
    }
    It 'preserves newer installed runtime versions without starting the installer' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Mock Get-OSDAppInstalledPrerequisiteVersion { [version]'10.0.2' }
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'does not report success when exit code is zero but installation is absent' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Mock Get-OSDAppInstalledPrerequisiteVersion { $null }
        { & $script:runCase } | Should -Throw '*not detected*'
    }
    It 'rejects corrupted content before launching any executable' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Add-Content (Join-Path $StagedPath $app.Package) 'corruption'
        { & $script:runCase } | Should -Throw '*SHA-256*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'keeps x86 Visual C++ distinct when x64 is already installed' {
        $script:spec=Get-OSDAppPrerequisiteSpec -Family VisualCppRedist -Architecture x86
        $app.Id=$spec.Id;$app.Family=$spec.Family;$app.Architecture=$spec.Architecture;$app.Channel=$spec.Channel;$app.RuntimeType=$spec.RuntimeType;$app.Package=Join-Path $spec.RelativeRoot 'Package.exe'
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Mock Get-OSDAppInstalledPrerequisiteVersion { if($Spec.Architecture -eq 'x64' -or $script:installerStarted){[version]'14.50.1.0'} }
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly
    }
}
