Describe '7Zip release-validated built-in' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }
    It 'exports discoverable commands with architecture selection and no arbitrary download override' {
        foreach ($name in @('Add-OSDApp7Zip','Sync-OSDApp7Zip')) {
            $command = Get-Command $name -Module OSDApps
            $command.Parameters.ContainsKey('PackageUri') | Should -BeFalse
            @($command.Parameters.Architecture.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })[0].ValidValues | Should -Be @('x64','x86','arm64')
        }
        InModuleScope OSDApps {
            Mock Get-OSDAppHostArchitecture { 'x64' }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            @(Get-OSDApp -Offline | Where-Object Id -eq 7Zip).Count | Should -Be 1
        }
    }
    It 'stages intent and matching runtime scripts without downloading or an existing cache' {
        InModuleScope OSDApps {
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            Mock Get-OSDApp7ZipRelease { throw 'Must not query releases in WinPE' }
            $windows = Join-Path $TestDrive 'WindowsRoot'
            New-Item -ItemType Directory -Path $windows -Force | Out-Null
            $result = Add-OSDApp7Zip -WindowsPath $windows -Confirm:$false
            $result.CacheAvailable | Should -BeFalse
            $stage = Join-Path $windows 'Windows/Temp/OSDApps'
            $manifest = Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps).Count | Should -Be 1
            $manifest.Apps[0].Type | Should -Be 7ZipExe
            $manifest.Apps[0].Architecture | Should -Be x64
            foreach ($file in @('OSDApp7Zip.ps1','Invoke-OSDAppBuiltInCacheTransaction.ps1')) {
                (Get-FileHash (Join-Path $stage $file)).Hash | Should -Be (Get-FileHash (Join-Path $script:moduleRoot "Runtime/$file")).Hash
            }
        }
    }
    It 'does not stage anything with WhatIf' {
        InModuleScope OSDApps {
            Mock Resolve-OSDAppWindowsPath { $WindowsPath }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            $windows = Join-Path $TestDrive 'WhatIfWindows'
            Add-OSDApp7Zip -WindowsPath $windows -WhatIf
            Test-Path $windows | Should -BeFalse
        }
    }
    Context 'Release metadata and generation integrity' {
        BeforeEach {
            InModuleScope OSDApps {
                $script:payload = New-Object byte[] 256
                $script:payload[0]=0x4d; $script:payload[1]=0x5a; $script:payload[60]=0x80
                $script:payload[128]=0x50; $script:payload[129]=0x45; $script:payload[132]=0x64; $script:payload[133]=0x86
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $script:hash = ([BitConverter]::ToString($sha.ComputeHash($script:payload))).Replace('-','') } finally { $sha.Dispose() }
                $script:apiRelease = [pscustomobject]@{
                    tag_name='26.04'; draft=$false; prerelease=$false
                    assets=@([pscustomobject]@{name='7z2604-x64.exe'; browser_download_url='https://github.com/ip7z/7zip/releases/download/26.04/7z2604-x64.exe'; digest="sha256:$script:hash"; size=256})
                }
                Mock Invoke-RestMethod { $script:apiRelease }
                Mock Assert-OSDAppTransactionSpace { }
                $script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $script:downloadCount = 0
                $script:download = { param($uri,$destination); $script:downloadCount++; [IO.File]::WriteAllBytes($destination,$script:payload) }
            }
        }
        It 'acquires once, reuses without download and detects later corruption' {
            InModuleScope OSDApps {
                (Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download).Updated | Should -BeTrue
                (Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download).Updated | Should -BeFalse
                $script:downloadCount | Should -Be 1
                $path = Join-Path $script:cache 'Package.exe'
                $data = [IO.File]::ReadAllBytes($path); $data[255]=1; [IO.File]::WriteAllBytes($path,$data)
                { Assert-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 } | Should -Throw '*SHA-256*'
                (Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download).Updated | Should -BeTrue
                $script:downloadCount | Should -Be 2
            }
        }
        It 'preserves the active generation when replacement download fails' {
            InModuleScope OSDApps {
                Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $before = (Get-FileHash (Join-Path $script:cache 'Package.exe')).Hash
                $script:apiRelease.tag_name='26.05'; $script:apiRelease.assets[0].name='7z2605-x64.exe'
                $script:apiRelease.assets[0].browser_download_url='https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe'
                { Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download { throw 'Download failed' } } | Should -Throw '*Download failed*'
                (Get-FileHash (Join-Path $script:cache 'Package.exe')).Hash | Should -Be $before
                (Assert-OSDApp7ZipGeneration -Root $script:cache -Architecture x64).Version | Should -Be '26.04'
                @(Get-ChildItem (Split-Path $script:cache -Parent) -Directory | Where-Object Name -like '*.osdapps-*').Count | Should -Be 0
            }
        }
        It 'rejects a downloaded hash mismatch without promoting the candidate' {
            InModuleScope OSDApps {
                { Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download { param($u,$p); [IO.File]::WriteAllBytes($p,(New-Object byte[] 256)) } } | Should -Throw '*SHA-256*'
                Test-Path $script:cache | Should -BeFalse
            }
        }
        It 'rejects absent digests and non-vendor URLs before downloading' {
            InModuleScope OSDApps {
                $script:apiRelease.assets[0].digest=$null
                { Get-OSDApp7ZipRelease -Architecture x64 } | Should -Throw '*SHA-256*'
                $script:apiRelease.assets[0].digest="sha256:$script:hash"
                $script:apiRelease.assets[0].browser_download_url='https://example.org/package.exe'
                { Get-OSDApp7ZipRelease -Architecture x64 } | Should -Throw '*unexpected URL*'
            }
        }
        It 'rejects the wrong architecture even with matching hash and size' {
            InModuleScope OSDApps {
                Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $path = Join-Path $script:cache 'CacheInfo.json'
                $info = Get-Content $path -Raw | ConvertFrom-Json
                $info.Architecture='arm64'; $info.PackageUri='https://github.com/ip7z/7zip/releases/download/26.04/7z2604-arm64.exe'
                $info | ConvertTo-Json | Set-Content $path
                { Assert-OSDApp7ZipGeneration -Root $script:cache -Architecture arm64 } | Should -Throw '*architecture*'
            }
        }
        It 'recovers a verified previous generation after interruption' {
            InModuleScope OSDApps {
                Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download
                $old = "$script:cache.osdapps-old-$([guid]::NewGuid().ToString('N'))"
                Move-Item $script:cache $old
                (Sync-OSDApp7ZipGeneration -Root $script:cache -Architecture x64 -Download $script:download).Updated | Should -BeFalse
                Test-Path $old | Should -BeFalse
            }
        }
    }
}

Describe '7Zip runtime dispatch' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:runtimeRoot = Join-Path $root 'Runtime'
        . (Join-Path $script:runtimeRoot 'OSDApp7Zip.ps1')
        . (Join-Path $script:runtimeRoot 'Assert-OSDAppTransactionSpace.ps1')
        . (Join-Path $script:runtimeRoot 'Restore-OSDAppCacheGeneration.ps1')
        . (Join-Path $script:runtimeRoot 'Invoke-OSDAppBuiltInCacheTransaction.ps1')
        $tokens=$null; $errors=$null
        $preAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:runtimeRoot 'Invoke-OSDAppPreInstall.ps1'),[ref]$tokens,[ref]$errors)
        foreach ($definition in $preAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $preSwitch = $preAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Value -eq '7Zip' }).Count -gt 0},$true)
        $script:preCase = [scriptblock]::Create(@($preSwitch.Clauses | Where-Object { $_.Item1.Value -eq '7Zip' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
        $runnerAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:runtimeRoot 'Invoke-OSDAppRunner.ps1'),[ref]$tokens,[ref]$errors)
        $runSwitch = $runnerAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and @($n.Clauses | Where-Object { $_.Item1.Value -eq '7ZipExe' }).Count -gt 0},$true)
        $runText = @($runSwitch.Clauses | Where-Object { $_.Item1.Value -eq '7ZipExe' })[0].Item2.Extent.Text.Trim().TrimStart('{').TrimEnd('}')
        $script:runCase = [scriptblock]::Create($runText.Replace('$PSScriptRoot', "'$script:runtimeRoot'"))
        function Write-RunnerLog { param($LogPath,$Event,$Message,$Data) }
        function New-RuntimeFixture {
            param($Path)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $bytes = New-Object byte[] 256
            $bytes[0]=0x4d; $bytes[1]=0x5a; $bytes[60]=128; $bytes[128]=0x50; $bytes[129]=0x45; $bytes[132]=0x64; $bytes[133]=0x86
            [IO.File]::WriteAllBytes((Join-Path $Path 'Package.exe'),$bytes)
            @{Id='7Zip';Version='26.04';Architecture='x64';Size=256;Sha256=(Get-FileHash (Join-Path $Path 'Package.exe')).Hash;PackageUri='https://github.com/ip7z/7zip/releases/download/26.04/7z2604-x64.exe'} | ConvertTo-Json | Set-Content (Join-Path $Path 'CacheInfo.json')
        }
    }
    BeforeEach {
        $script:StagedPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:app = [pscustomobject]@{Id='7Zip';DisplayName='7Zip';Architecture='x64';Package='BuiltIn/7Zip/x64/Package.exe';InstallTimeoutMinutes=10}
        $script:acquisition = @{}
        $script:usbRoot = $null
        $script:networkAvailable = $true
        $script:logPath = Join-Path $StagedPath 'runtime.log'
        Mock Write-RunnerLog { }
        Mock Get-OSDApp7ZipRelease { throw 'Release API unavailable' }
    }
    It 'records fallback reuse only for valid staged content after an API failure' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/7Zip/x64')
        & $script:preCase
        $acquisition.Outcome | Should -Be 'FallbackCacheUsed'
        $acquisition.RefreshError | Should -Match 'Release API unavailable'
    }
    It 'fails acquisition when no valid fallback exists' {
        { & $script:preCase } | Should -Throw '*no valid staged fallback*'
    }
    It 'records offline reuse without calling the release API' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/7Zip/x64')
        $script:networkAvailable = $false
        & $script:preCase
        $acquisition.Outcome | Should -Be 'OfflineCacheUsed'
        Should -Invoke Get-OSDApp7ZipRelease -Times 0 -Exactly
    }
    It 'executes only the validated EXE with the fixed silent argument' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/7Zip/x64')
        Mock Start-Process { [pscustomobject]@{HasExited=$true;ExitCode=0} }
        # Supply the production runtime root for the clause's dot-sourced helper.
        $PSScriptRoot = $script:runtimeRoot
        $result = & $script:runCase
        $result.ExitCode | Should -Be 0
        Should -Invoke Start-Process -Exactly -Times 1 -ParameterFilter { $FilePath -eq (Join-Path $StagedPath $app.Package) -and @($ArgumentList).Count -eq 1 -and $ArgumentList[0] -ceq '/S' }
    }
    It 'rejects corruption before starting any installer process' {
        New-RuntimeFixture (Join-Path $StagedPath 'BuiltIn/7Zip/x64')
        Add-Content (Join-Path $StagedPath $app.Package) 'corruption'
        Mock Start-Process { throw 'Must not start' }
        $PSScriptRoot = $script:runtimeRoot
        { & $script:runCase } | Should -Throw '*SHA-256*'
        Should -Invoke Start-Process -Exactly -Times 0
    }
}
