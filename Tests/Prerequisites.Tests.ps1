BeforeAll {
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function global:Get-AuthenticodeSignature { param([string]$LiteralPath) throw 'Windows trust evaluation is unavailable.' }
    }
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force
}
Describe 'Runtime selection and staging' {
    BeforeEach { InModuleScope OSDApps { Mock Get-Date { [datetime]'2026-10-21T12:00:00Z' } } }
    It 'preserves x86/x64 and multiple .NET variants, de-duplicates and orders prerequisites first' {
        InModuleScope OSDApps {
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            Mock Get-OSDAppPrerequisiteRelease { throw 'Must not download in WinPE' }
            $windows = Join-Path $TestDrive 'Windows'
            New-Item -ItemType Directory $windows -Force | Out-Null
            Add-OSDAppVisualStudioCode -WindowsPath $windows
            Add-OSDAppVisualCRedist -WindowsPath $windows -Architecture x86
            Add-OSDAppVisualCRedist -WindowsPath $windows -Architecture x64
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 8.0 -RuntimeType Runtime -Architecture x64
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 10.0 -RuntimeType Desktop -Architecture x64
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Channel 10.0 -RuntimeType Runtime -Architecture x86
            Add-OSDAppVisualCRedist -WindowsPath $windows -Architecture x64
            $stage = Join-Path $windows 'Windows/Temp/OSDApps'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 6
            @($manifest.Apps.Id | Select-Object -Unique).Count | Should -Be 6
            $manifest.Apps[-1].Id | Should -Be 'VisualStudioCode'
            $manifest.Apps.Id | Should -Contain 'VisualCRedist-x86'
            $manifest.Apps.Id | Should -Contain 'VisualCRedist-x64'
            foreach ($arch in @('x86','x64')) {
                $entry = $manifest.Apps | Where-Object Id -eq "VisualCRedist-$arch"
                $entry.Family | Should -Be 'VisualCRedist'
                $entry.Package | Should -BeNullOrEmpty
                $entry.PayloadRoot.Replace('\','/') | Should -Be "BuiltIn/VisualCRedist/$arch"
                $entry.PayloadExtension | Should -Be '.exe'
            }
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
            Add-OSDAppVisualCRedist -WindowsPath $windows -Architecture x64 -WhatIf
            Add-OSDAppDotNetRuntime -WindowsPath $windows -Architecture x64 -WhatIf
            Test-Path $windows | Should -BeFalse
        }
    }
    It 'rejects unsafe and preview channel strings' {
        { Add-OSDAppDotNetRuntime -Architecture x64 -Channel '../10.0' } | Should -Throw
        { Add-OSDAppDotNetRuntime -Architecture x64 -Channel '11.0-preview' } | Should -Throw
    }
}
Describe 'Runtime release selection and transaction integrity' {
    BeforeEach {
        InModuleScope OSDApps {
            Mock Get-Date { [datetime]'2026-10-21T12:00:00Z' }
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
            $script:download = {param($uri,$directory) $script:downloadCount++; $path=Join-Path $directory ([IO.Path]::GetFileName(([uri]$uri).AbsolutePath)); [IO.File]::WriteAllBytes($path,$script:payload); Get-Item -LiteralPath $path}
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
    It 'rejects EOL metadata without downloading or replacing an existing valid generation' {
        InModuleScope OSDApps {
            Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $before = (Get-FileHash (Join-Path $script:cache 'windowsdesktop-runtime-10.0.1-win-x64.exe')).Hash
            $script:metadata.'support-phase'='eol'
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download } | Should -Throw '*not a supported stable channel*'
            (Get-FileHash (Join-Path $script:cache 'windowsdesktop-runtime-10.0.1-win-x64.exe')).Hash | Should -Be $before
            $script:downloadCount | Should -Be 1
        }
    }
    It 'rejects missing or unknown online support metadata and mismatched channels' {
        InModuleScope OSDApps {
            Set-StrictMode -Version Latest
            $script:metadata.PSObject.Properties.Remove('support-phase')
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*Cannot confirm*'
            $script:metadata | Add-Member -NotePropertyName 'support-phase' -NotePropertyValue 'future-status'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*Cannot confirm*'
            $script:metadata.'channel-version'='9.0'
            { Get-OSDAppPrerequisiteRelease -Spec $script:spec } | Should -Throw '*requested channel*'
        }
    }
    It 'enforces the support deadline offline for staging, cached content and acquisition' {
        InModuleScope OSDApps {
            foreach ($channel in @('8.0','9.0')) {
                Mock Get-Date { [datetime]'2026-11-10T23:59:59Z' }
                { Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -Channel $channel } | Should -Not -Throw
                Mock Get-Date { [datetime]'2026-11-11T00:00:00Z' }
                { Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -Channel $channel } | Should -Throw '*support ended*'
            }
            Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            Mock Get-Date { [datetime]'2028-11-15T00:00:00Z' }
            { Assert-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec } | Should -Throw '*support ended*'
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download } | Should -Throw '*support ended*'
            { Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -Channel 7.0 } | Should -Throw '*not offered*'
        }
    }
    It 'reuses a verified generation and rejects content or selection mismatch' {
        InModuleScope OSDApps {
            $first = Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $first.Updated | Should -BeTrue
            $first.CacheDecisionReason | Should -Match 'could not be reused'
            $reused = Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $reused.Updated | Should -BeFalse
            $reused.CacheDecisionReason | Should -Match 'passed integrity.*current official release'
            $script:downloadCount | Should -Be 1
            $other = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x86 -Channel 10.0
            { Assert-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $other } | Should -Throw '*incompatible*'
            Add-Content (Join-Path $script:cache 'windowsdesktop-runtime-10.0.1-win-x64.exe') 'corrupt'
            { Assert-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec } | Should -Throw '*SHA-256*'
            $repaired = Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $repaired.Updated | Should -BeTrue
            $repaired.CacheDecisionReason | Should -Match 'size or SHA-256 mismatch'
        }
    }
    It 'preserves the old generation after a bad candidate digest and removes temporary folders' {
        InModuleScope OSDApps {
            Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download $script:download
            $before = (Get-FileHash (Join-Path $script:cache 'windowsdesktop-runtime-10.0.1-win-x64.exe')).Hash
            $script:metadata.'latest-runtime'='10.0.2';$script:metadata.releases[0].'release-version'='10.0.2';$script:component.version='10.0.2';$script:component.files[0].url=$script:component.files[0].url.Replace('10.0.1','10.0.2')
            { Sync-OSDAppPrerequisiteGeneration -Root $script:cache -Spec $script:spec -Download {param($u,$directory) $path=Join-Path $directory ([IO.Path]::GetFileName(([uri]$u).AbsolutePath)); Set-Content $path 'wrong'; Get-Item -LiteralPath $path} } | Should -Throw '*SHA-512*'
            (Get-FileHash (Join-Path $script:cache 'windowsdesktop-runtime-10.0.1-win-x64.exe')).Hash | Should -Be $before
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
            $version=if($Spec.Family -eq 'VisualCRedist'){'14.50.1.0'}else{'10.0.1'}
            $uri=if($Spec.Family -eq 'VisualCRedist'){"https://aka.ms/vc14/vc_redist.$($Spec.Architecture).exe"}else{'https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.1/windowsdesktop-runtime-10.0.1-win-x64.exe'}
            $name = [IO.Path]::GetFileName(([uri]$uri).AbsolutePath)
            $payload = Join-Path $Path $name
            Set-Content -LiteralPath $payload 'runtime fixture'
            @{ Id=$Spec.Family;VariantId=$Spec.Id;Architecture=$Spec.Architecture;RuntimeType=$Spec.RuntimeType;Channel=$Spec.Channel;Version=$version;PackageUri=$uri;PayloadFileName=$name;Size=(Get-Item -LiteralPath $payload).Length;Sha256=(Get-FileHash -LiteralPath $payload).Hash;Sha512=(Get-FileHash -LiteralPath $payload -Algorithm SHA512).Hash } | ConvertTo-Json | Set-Content (Join-Path $Path 'CacheInfo.json')
        }
    }
    BeforeEach {
        Mock Get-Date { [datetime]'2026-10-21T12:00:00Z' }
        $script:spec=Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture x64 -Channel 10.0
        $script:app=[pscustomobject]@{Id=$spec.Id;Family=$spec.Family;Architecture=$spec.Architecture;RuntimeType=$spec.RuntimeType;Channel=$spec.Channel;Type='PrerequisiteExe';Package=$null;PayloadRoot=$spec.RelativeRoot;PayloadExtension='.exe';DisplayName=$spec.DisplayName;InstallTimeoutMinutes=10}
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
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
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
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        $app.Architecture='x86'
        { & $script:preCase } | Should -Throw '*identity*'
    }
    It 'rejects corrupt, wrong-channel and untrusted staged fallback during a metadata outage' {
        $root = Join-Path $StagedPath $spec.RelativeRoot
        New-PrerequisiteFixture $root $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Add-Content (Resolve-OSDAppBuiltInPayloadPath -Root $root -ExpectedExtension '.exe') 'corrupt'
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        New-PrerequisiteFixture $root $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        $info = Get-Content (Join-Path $root 'CacheInfo.json') -Raw | ConvertFrom-Json
        $info.Channel='9.0'
        $info | ConvertTo-Json | Set-Content (Join-Path $root 'CacheInfo.json')
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        New-PrerequisiteFixture $root $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Other Corporation'}} }
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'does not fall back when Microsoft explicitly reports the channel is unsupported' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-OSDAppPrerequisiteRelease { throw [NotSupportedException]::new('Channel is EOL') }
        { & $script:preCase } | Should -Throw '*Channel is EOL*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'rejects an expired channel before offline fallback or execution' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-Date { [datetime]'2028-11-15T00:00:00Z' }
        $script:networkAvailable=$false
        { & $script:preCase } | Should -Throw '*support ended*'
        { & $script:runCase } | Should -Throw '*support ended*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'uses silent install without reboot and confirms the installed version' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -eq '/install /quiet /norestart' }
        Should -Invoke Get-OSDAppInstalledPrerequisiteVersion -Times 2 -Exactly
    }
    It 'preserves newer installed runtime versions without starting the installer' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-OSDAppInstalledPrerequisiteVersion { [version]'10.0.2' }
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'does not report success when exit code is zero but installation is absent' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-OSDAppInstalledPrerequisiteVersion { $null }
        { & $script:runCase } | Should -Throw '*not detected*'
    }
    It 'rejects corrupted content before launching any executable' {
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Add-Content (Join-Path $StagedPath $app.Package) 'corruption'
        { & $script:runCase } | Should -Throw '*SHA-256*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'keeps x86 Visual C++ distinct when x64 is already installed' {
        $script:spec=Get-OSDAppPrerequisiteSpec -Family VisualCRedist -Architecture x86
        $app.Id=$spec.Id;$app.Family=$spec.Family;$app.Architecture=$spec.Architecture;$app.Channel=$spec.Channel;$app.RuntimeType=$spec.RuntimeType;$app.Package=$null;$app.PayloadRoot=$spec.RelativeRoot
        New-PrerequisiteFixture (Join-Path $StagedPath $spec.RelativeRoot) $spec
        Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath
        Mock Get-OSDAppInstalledPrerequisiteVersion { if($Spec.Architecture -eq 'x64' -or $script:installerStarted){[version]'14.50.1.0'} }
        (& $script:runCase).ExitCode | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly
    }
}
