BeforeAll {
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function global:Get-AuthenticodeSignature { param([string]$LiteralPath) throw 'Windows trust evaluation is unavailable.' }
    }
}
Describe 'VisualStudioCode release-validated built-in' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }
    It 'exports discoverable commands with architecture selection and no arbitrary download override' {
        foreach ($name in @('Add-OSDStageVisualStudioCode','Sync-OSDStageVisualStudioCode')) {
            $command = Get-Command $name -Module OSDStage
            $command.Parameters.ContainsKey('PackageUri') | Should -BeFalse
            @($command.Parameters.Architecture.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })[0].ValidValues | Should -Be @('x64','arm64')
        }
        InModuleScope OSDStage {
            Mock Get-OSDStageHostArchitecture { 'x64' }
            Mock Get-OSDStageCachePath { throw 'No cache' }
            @(Get-OSDStage -Offline | Where-Object Id -eq VisualStudioCode).Count | Should -Be 1
        }
    }
    It 'stages intent and matching runtime scripts without downloading or an existing cache' {
        InModuleScope OSDStage {
            Mock Resolve-OSDStageWindowsPath { $WindowsPath }
            Mock Get-OSDStageCachePath { throw 'No cache' }
            Mock Get-OSDStageVisualStudioCodeRelease { throw 'Must not query releases in WinPE' }
            $windows = Join-Path $TestDrive 'WindowsRoot'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            $result = Add-OSDStageVisualStudioCode -WindowsPath $windows -Confirm:$false
            $result.CacheAvailable | Should -BeFalse
            $stage = Join-Path $windows 'Windows/Temp/OSDStage'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages).Count | Should -Be 1
            $manifest.Packages[0].Type | Should -Be VisualStudioCodeExe
            $manifest.Packages[0].Architecture | Should -Be x64
            foreach ($file in @('OSDStageVisualStudioCode.ps1','Invoke-OSDStageBuiltInCacheTransaction.ps1')) {
                (Get-FileHash (Join-Path $stage $file)).Hash | Should -Be (Get-FileHash (Join-Path $script:moduleRoot "Runtime/$file")).Hash
            }
        }
    }
    It 'does not stage anything with WhatIf' {
        InModuleScope OSDStage {
            Mock Resolve-OSDStageWindowsPath { $WindowsPath }
            Mock Get-OSDStageCachePath { throw 'No cache' }
            $windows = Join-Path $TestDrive 'WhatIfWindows'
            Add-OSDStageVisualStudioCode -WindowsPath $windows -WhatIf
            Test-Path $windows | Should -BeFalse
        }
    }
    Context 'Release metadata and generation integrity' {
        BeforeEach {
            InModuleScope OSDStage {
                $script:payload = New-Object byte[] 256
                $script:payload[0]=0x4d; $script:payload[1]=0x5a; $script:payload[60]=0x80
                $script:payload[128]=0x50; $script:payload[129]=0x45; $script:payload[132]=0x64; $script:payload[133]=0x86
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $script:hash = ([BitConverter]::ToString($sha.ComputeHash($script:payload))).Replace('-','') } finally { $sha.Dispose() }
                $script:apiRelease = [pscustomobject]@{
                    productVersion='1.100.0'; version=('a' * 40)
                    url=('https://vscode.download.prss.microsoft.com/dbazure/download/stable/' + ('a' * 40) + '/VSCodeSetup-x64-1.100.0.exe')
                    sha256hash=$script:hash
                }
                Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'}} }
                Mock Invoke-RestMethod { $script:apiRelease }
                Mock Assert-OSDStageTransactionSpace { }
                $script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $script:downloadCount = 0
                $script:download = { param($uri,$destinationDirectory); $script:downloadCount++; $file=Join-Path $destinationDirectory ([IO.Path]::GetFileName(([uri]$uri).AbsolutePath)); [IO.File]::WriteAllBytes($file,$script:payload); Get-Item -LiteralPath $file }
            }
        }
        It 'acquires once, reuses without download and detects later corruption' {
            InModuleScope OSDStage {
                $first = Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $first.Updated | Should -BeTrue
                $first.CacheDecisionReason | Should -Match 'could not be reused'
                $reused = Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $reused.Updated | Should -BeFalse
                $reused.CacheDecisionReason | Should -Match 'passed integrity.*current official release'
                $script:downloadCount | Should -Be 1
                $path = Join-Path $script:cache 'VSCodeSetup-x64-1.100.0.exe'
                $data = [IO.File]::ReadAllBytes($path); $data[255]=1; [IO.File]::WriteAllBytes($path,$data)
                { Assert-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 } | Should -Throw '*SHA-256*'
                $repaired = Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $repaired.Updated | Should -BeTrue
                $repaired.CacheDecisionReason | Should -Match 'SHA-256'
                $script:downloadCount | Should -Be 2
            }
        }
        It 'preserves the active generation when replacement download fails' {
            InModuleScope OSDStage {
                Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $before = (Get-FileHash (Join-Path $script:cache 'VSCodeSetup-x64-1.100.0.exe')).Hash
                $script:apiRelease.productVersion='1.100.1'
                $script:apiRelease.url=$script:apiRelease.url.Replace('1.100.0','1.100.1')
                { Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download { throw 'Download failed' } } | Should -Throw '*Download failed*'
                (Get-FileHash (Join-Path $script:cache 'VSCodeSetup-x64-1.100.0.exe')).Hash | Should -Be $before
                (Assert-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64).Version | Should -Be '1.100.0'
                @(Get-ChildItem (Split-Path $script:cache -Parent) -Directory | Where-Object Name -like '*.osdstage-*').Count | Should -Be 0
            }
        }
        It 'rejects a downloaded hash mismatch without promoting the candidate' {
            InModuleScope OSDStage {
                { Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download { param($u,$p); $file=Join-Path $p ([IO.Path]::GetFileName(([uri]$u).AbsolutePath)); [IO.File]::WriteAllBytes($file,(New-Object byte[] 256)); Get-Item -LiteralPath $file } } | Should -Throw '*SHA-256*'
                Test-Path $script:cache | Should -BeFalse
            }
        }
        It 'rejects absent digests and non-vendor URLs before downloading' {
            InModuleScope OSDStage {
                $script:apiRelease.sha256hash=$null
                { Get-OSDStageVisualStudioCodeRelease -Architecture x64 } | Should -Throw '*SHA-256*'
                $script:apiRelease.sha256hash=$script:hash
                $script:apiRelease.url='https://example.org/package.exe'
                { Get-OSDStageVisualStudioCodeRelease -Architecture x64 } | Should -Throw '*unexpected system-installer URL*'
            }
        }
        It 'rejects user installers, wrong platforms and invalid Microsoft signatures' {
            InModuleScope OSDStage {
                $script:apiRelease.url=$script:apiRelease.url.Replace('VSCodeSetup','VSCodeUserSetup')
                { Get-OSDStageVisualStudioCodeRelease -Architecture x64 } | Should -Throw '*system-installer URL*'
                $script:apiRelease.url=$script:apiRelease.url.Replace('VSCodeUserSetup','VSCodeSetup')
                { Get-OSDStageVisualStudioCodeRelease -Architecture arm64 } | Should -Throw '*system-installer URL*'
                Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Corporation, O=Other Vendor, C=US'}} }
                { Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download } | Should -Throw '*Microsoft Corporation Authenticode*'
                Test-Path $script:cache | Should -BeFalse
            }
        }
        It 'preserves the active generation when replacement fails publisher validation' {
            InModuleScope OSDStage {
                Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $before = (Get-FileHash (Join-Path $script:cache 'CacheInfo.json')).Hash
                $script:apiRelease.productVersion='1.100.1'
                $script:apiRelease.url=$script:apiRelease.url.Replace('1.100.0','1.100.1')
                Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='HashMismatch';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}} }
                { Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download } | Should -Throw '*Authenticode*'
                (Get-FileHash (Join-Path $script:cache 'CacheInfo.json')).Hash | Should -Be $before
                @(Get-ChildItem (Split-Path $script:cache -Parent) -Directory | Where-Object Name -like '*.osdstage-*').Count | Should -Be 0
            }
        }
        It 'accepts ARM64 metadata only at the ARM64 system platform endpoint' {
            InModuleScope OSDStage {
                $script:apiRelease.url=$script:apiRelease.url.Replace('x64','arm64')
                (Get-OSDStageVisualStudioCodeRelease -Architecture arm64).Architecture | Should -Be 'arm64'
                Should -Invoke Invoke-RestMethod -Exactly -Times 1 -ParameterFilter { $Uri -eq 'https://update.code.visualstudio.com/api/update/win32-arm64/stable/latest' }
            }
        }
        It 'recovers a verified previous generation after interruption' {
            InModuleScope OSDStage {
                Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $old = "$script:cache.osdstage-old-$([guid]::NewGuid().ToString('N'))"
                Move-Item $script:cache $old
                (Sync-OSDStageVisualStudioCodeGeneration -Root $script:cache -Architecture x64 -Download $script:download).Updated | Should -BeFalse
                Test-Path $old | Should -BeFalse
            }
        }
    }
}

Describe 'VisualStudioCode runtime dispatch' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:runtimeRoot = Join-Path $root 'Runtime'
        . (Join-Path $script:runtimeRoot 'OSDStageVisualStudioCode.ps1')
        . (Join-Path $script:runtimeRoot 'Assert-OSDStageTransactionSpace.ps1')
        . (Join-Path $script:runtimeRoot 'Restore-OSDStageCacheGeneration.ps1')
        . (Join-Path $script:runtimeRoot 'Invoke-OSDStageBuiltInCacheTransaction.ps1')
        $tokens=$null; $errors=$null
        $preAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:runtimeRoot 'Invoke-OSDStagePreInstall.ps1'),[ref]$tokens,[ref]$errors)
        foreach ($definition in $preAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $preSwitch = $preAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Value -eq 'VisualStudioCode' }).Count -gt 0},$true)
        $script:preCase = [scriptblock]::Create(@($preSwitch.Clauses | Where-Object { $_.Item1.Value -eq 'VisualStudioCode' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
        $runnerAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:runtimeRoot 'Invoke-OSDStageRunner.ps1'),[ref]$tokens,[ref]$errors)
        $runSwitch = $runnerAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Value -eq 'VisualStudioCodeExe' }).Count -gt 0},$true)
        $runText = @($runSwitch.Clauses | Where-Object { $_.Item1.Value -eq 'VisualStudioCodeExe' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
        $script:runCase = [scriptblock]::Create($runText.Replace('$PSScriptRoot', "'$script:runtimeRoot'"))
        function Write-RunnerLog { param($LogPath,$Event,$Message,$Data) }
        function New-RuntimeFixture {
            param($Path)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $bytes = New-Object byte[] 256
            $bytes[0]=0x4d; $bytes[1]=0x5a; $bytes[60]=128; $bytes[128]=0x50; $bytes[129]=0x45; $bytes[132]=0x64; $bytes[133]=0x86
            [IO.File]::WriteAllBytes((Join-Path $Path 'VSCodeSetup-x64-1.100.0.exe'),$bytes)
            @{PayloadFileName='VSCodeSetup-x64-1.100.0.exe';Id='VisualStudioCode';Version='1.100.0';Commit=('a' * 40);Architecture='x64';Size=256;Sha256=(Get-FileHash (Join-Path $Path 'VSCodeSetup-x64-1.100.0.exe')).Hash;PackageUri=('https://vscode.download.prss.microsoft.com/dbazure/download/stable/' + ('a' * 40) + '/VSCodeSetup-x64-1.100.0.exe')} | ConvertTo-Json | Set-Content (Join-Path $Path 'CacheInfo.json')
        }
    }
    BeforeEach {
        $script:StagedPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:app = [pscustomobject]@{Id='VisualStudioCode';Type='VisualStudioCodeExe';DisplayName='VisualStudioCode';Architecture='x64';Package='BuiltIn/VisualStudioCode/x64/VSCodeSetup-x64-1.100.0.exe';InstallTimeoutMinutes=10}
        $script:acquisition = @{}
        $script:usbRoot = $null
        $script:networkAvailable = $true
        $script:logPath = Join-Path $StagedPath 'runtime.log'
        Mock Write-RunnerLog { }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}} }
        Mock Get-OSDStageVisualStudioCodeRelease { throw 'Release API unavailable' }
    }
    It 'records fallback reuse only for valid staged content after an API failure' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/VisualStudioCode/x64')
        Set-OSDStageManifestPayload -App $app -StagedPath $StagedPath
        & $script:preCase
        $acquisition.Outcome | Should -Be 'FallbackCacheUsed'
        $acquisition.RefreshError | Should -Match 'Release API unavailable'
    }
    It 'fails acquisition when no valid fallback exists' {
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
    }
    It 'records offline reuse without calling the release API' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/VisualStudioCode/x64')
        Set-OSDStageManifestPayload -App $app -StagedPath $StagedPath
        $script:networkAvailable = $false
        & $script:preCase
        $acquisition.Outcome | Should -Be 'OfflineCacheUsed'
        Should -Invoke Get-OSDStageVisualStudioCodeRelease -Times 0 -Exactly
    }
    It 'executes only the validated EXE with the fixed silent argument' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/VisualStudioCode/x64')
        Set-OSDStageManifestPayload -App $app -StagedPath $StagedPath
        Mock Start-Process { [pscustomobject]@{HasExited=$true;ExitCode=0} }
        # Supply the production runtime root for the clause's dot-sourced helper.
        $PSScriptRoot = $script:runtimeRoot
        $result = & $script:runCase
        $result.ExitCode | Should -Be 0
        Should -Invoke Start-Process -Exactly -Times 1 -ParameterFilter { $FilePath -eq (Join-Path $StagedPath $app.Package) -and ($ArgumentList -join ' ') -ceq '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS=!runcode /RESTARTEXITCODE=3010' }
    }
    It 'rejects corruption before starting any installer process' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/VisualStudioCode/x64')
        Set-OSDStageManifestPayload -App $app -StagedPath $StagedPath
        Add-Content (Join-Path $StagedPath $app.Package) 'corruption'
        Mock Start-Process { throw 'Must not start' }
        $PSScriptRoot = $script:runtimeRoot
        { & $script:runCase } | Should -Throw '*SHA-256*'
        Should -Invoke Start-Process -Exactly -Times 0
    }
}
