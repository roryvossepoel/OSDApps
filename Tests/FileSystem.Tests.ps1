Describe 'File system operations' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime/Invoke-OSDStageFileSystem.ps1')
        function New-TestFileOperation {
            param($Path, $Text='', $Kind='File', $Action='Create', [bool]$Force=$false, [bool]$Recurse=$false)
            [pscustomobject]@{Kind=$Kind;Action=$Action;Path=$Path;Force=$Force;Recurse=$Recurse;Data=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))}
        }
    }
    BeforeEach {
        $script:destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Resolve-OSDStageFileSystemPath { param($Path) Join-Path $script:destination (($Path -replace '^C:\\','').Replace('\',[IO.Path]::DirectorySeparatorChar)) }
    }
    It 'creates parents and literal bracketed filenames, preserves bytes, and is idempotent' {
        $op = New-TestFileOperation 'C:\Parent\Child\file[1].txt' 'hello'
        (Invoke-OSDStageFileSystemOperation $op).Outcome | Should -Be Created
        [IO.File]::ReadAllText((Join-Path $script:destination 'Parent/Child/file[1].txt')) | Should -BeExactly hello
        (Invoke-OSDStageFileSystemOperation $op).Outcome | Should -Be Unchanged
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\Parent\Child' -Kind Directory)).Outcome | Should -Be Unchanged
    }
    It 'creates a zero-byte file and snapshots raw binary data without conversion' {
        $op = New-TestFileOperation 'C:\empty'
        Invoke-OSDStageFileSystemOperation $op | Out-Null
        (Get-Item (Join-Path $script:destination empty)).Length | Should -Be 0
        $op = New-TestFileOperation 'C:\binary'
        $op.Data = [Convert]::ToBase64String([byte[]](0,255,10,13,128))
        Invoke-OSDStageFileSystemOperation $op | Out-Null
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:destination binary))) | Should -BeExactly $op.Data
    }
    It 'refuses overwrite without Force and replaces atomically with Force' {
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file' 'before') | Out-Null
        { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file' 'after') } | Should -Throw '*Force*'
        [IO.File]::ReadAllText((Join-Path $script:destination file)) | Should -BeExactly before
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file' 'after' -Force $true)).Outcome | Should -Be Replaced
        [IO.File]::ReadAllText((Join-Path $script:destination file)) | Should -BeExactly after
        @(Get-ChildItem $script:destination -Force -Filter '.osdstage-*').Count | Should -Be 0
    }
    It 'requires Recurse independently of Force and removes nested trees bottom-up' {
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree\nested\file' 'test') | Out-Null
        { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Force $true) } | Should -Throw '*Recurse*'
        Test-Path (Join-Path $script:destination tree/nested/file) | Should -BeTrue
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Recurse $true)).Outcome | Should -Be Removed
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Recurse $true)).Outcome | Should -Be AlreadyAbsent
    }
    It 'removes an empty directory and an individual file, rejecting type conflicts' {
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\empty' -Kind Directory) | Out-Null
        { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\empty' -Action Remove -Force $true) } | Should -Throw '*different item type*'
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\empty' -Kind Directory -Action Remove)).Outcome | Should -Be Removed
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file') | Out-Null
        { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file' -Kind Directory -Force $true) } | Should -Throw '*different item type*'
        (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\file' -Action Remove)).Outcome | Should -Be Removed
    }
    It 'preflights read-only children and requires Force to remove them' {
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree\a' 'a') | Out-Null
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree\z' 'z') | Out-Null
        $file = Join-Path $script:destination tree/z
        [IO.File]::SetAttributes($file,[IO.FileAttributes]::ReadOnly)
        try {
            { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Recurse $true) } | Should -Throw '*Force*'
            Test-Path (Join-Path $script:destination tree/a) | Should -BeTrue
            (Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Recurse $true -Force $true)).Outcome | Should -Be Removed
        } finally { if (Test-Path -LiteralPath $file) { [IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal) } }
    }
    It 'rejects a link inside a recursive deletion before removing ordinary siblings' {
        Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree\a' 'keep') | Out-Null
        $outside = Join-Path $TestDrive ('outside-' + [guid]::NewGuid().ToString('N'))
        New-Item $outside -ItemType Directory | Out-Null
        [IO.File]::WriteAllText((Join-Path $outside keep.txt),'keep')
        $link = Join-Path $script:destination tree/link
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        New-Item -Path $link -ItemType $linkType -Target $outside | Out-Null
        try {
            { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree' -Kind Directory -Action Remove -Force $true -Recurse $true) } | Should -Throw '*reparse*'
            Test-Path (Join-Path $script:destination tree/a) | Should -BeTrue
            Test-Path (Join-Path $outside keep.txt) | Should -BeTrue
            { Invoke-OSDStageFileSystemOperation (New-TestFileOperation 'C:\tree\link\new.txt' 'bad') } | Should -Throw '*Reparse*'
        } finally { (Get-Item -LiteralPath $link -Force).Delete() }
    }
    It 'rejects unsupported paths and malformed intent before execution' {
        foreach ($path in @('C:\','C:relative','relative','\\server\share\file','\\?\C:\file','C:\x\..\file','C:\x\file:stream','C:\x\NUL.txt','C:\x\file.','C:\x\file ','C:\x\*.txt','%USERPROFILE%\file','%ProgramData%\%TEMP%\file')) {
            { Assert-OSDStageFileSystemPath -Path $path } | Should -Throw
        }
        foreach ($path in @('C:\Tools\file[1].txt','%ProgramData%\Contoso\config.json','%ProgramFiles(x86)%\Contoso\file')) {
            { Assert-OSDStageFileSystemPath -Path $path } | Should -Not -Throw
        }
        $op = New-TestFileOperation 'C:\file'; $op.Data = '!invalid!'
        { Assert-OSDStageFileSystemOperation $op } | Should -Throw
        $op = New-TestFileOperation 'C:\file' -Recurse $true
        { Assert-OSDStageFileSystemOperation $op } | Should -Throw
    }
    It 'validates the entire configuration before any mutation and redacts file content' {
        $ops=@((New-TestFileOperation 'C:\first' 'SECRET-FIXTURE'),(New-TestFileOperation 'relative' 'bad'))
        $config=[pscustomobject]@{SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\result.json';Operations=$ops}
        { Invoke-OSDStageFileSystemConfiguration $config } | Should -Throw
        Test-Path $script:destination | Should -BeFalse
        $config.Operations=@((New-TestFileOperation 'C:\first' 'SECRET-FIXTURE'),(New-TestFileOperation 'C:\first' 'OTHER-SECRET'),(New-TestFileOperation 'C:\last' 'SECRET-FIXTURE'))
        $record=Invoke-OSDStageFileSystemConfiguration $config
        $record.Status | Should -Be Failed
        $record.SuccessfulOperationCount | Should -Be 2
        $record.FailedOperationCount | Should -Be 1
        ($record | ConvertTo-Json -Depth 8) | Should -Not -Match 'SECRET|U0VDUkVU'
        $record.RebootRequested | Should -BeFalse
    }
}

Describe 'File system staging' {
    BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force }
    BeforeEach { Set-OSDStageConfiguration -EnableBuiltIns $true -EnableRepository $false -CleanupMode Never }
    It 'guards full Windows, disabled built-ins and Remove false' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $false }
            { Add-OSDStageFile -Path 'C:\test' } | Should -Throw '*WinPE*'
            Mock Test-OSDStageWinPE { $true }
            { Add-OSDStageDirectory -Path 'C:\test' -Remove:$false } | Should -Throw '*explicitly*'
            Set-OSDStageConfiguration -EnableBuiltIns $false -EnableRepository $true
            { Add-OSDStageDirectory -Path 'C:\test' } | Should -Throw '*disabled*'
        }
    }
    It 'honors WhatIf, keeps order in one offline-ready entry and snapshots source bytes' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive Windows
            New-Item $target -ItemType Directory | Out-Null
            Add-OSDStageDirectory -Path 'C:\Tools' -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows/Temp/OSDStage/DeviceManifest.json') | Should -BeFalse
            Add-OSDStageDirectory -Path 'C:\Tools\Child' -WindowsPath $target | Out-Null
            Add-OSDStageFile -Path 'C:\Tools\text.txt' -Content 'before' -WindowsPath $target | Out-Null
            Add-OSDStageFile -Path 'C:\Tools\text.txt' -Content 'after' -Force -WindowsPath $target | Out-Null
            $source=Join-Path $TestDrive source.bin
            [IO.File]::WriteAllBytes($source,[byte[]](0,255,1,128))
            Add-OSDStageFile -SourcePath $source -DestinationPath 'C:\Tools\binary.bin' -WindowsPath $target | Out-Null
            Remove-Item $source
            Add-OSDStageDirectory -Path 'C:\Tools\Child' -Remove -Recurse -WindowsPath $target | Out-Null
            $ready=Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.PackageCount | Should -Be 1
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $file=Join-Path $target 'Windows/Temp/OSDStage/BuiltIn/FileSystem/config.json'
            $config=Get-Content $file -Raw | ConvertFrom-Json
            $config.Operations.Count | Should -Be 5
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($config.Operations[1].Data)) | Should -BeExactly before
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($config.Operations[2].Data)) | Should -BeExactly after
            $config.Operations[3].Data | Should -BeExactly ([Convert]::ToBase64String([byte[]](0,255,1,128)))
            $before=(Get-FileHash $file).Hash
            Mock Add-OSDStageSetupComplete { throw 'transaction fixture' }
            { Add-OSDStageFile -Path 'C:\Tools\rejected' -WindowsPath $target } | Should -Throw '*transaction fixture*'
            (Get-FileHash $file).Hash | Should -Be $before
            Add-Content $file 'tamper'
            { Test-OSDStageDeployment -WindowsPath $target -ThrowOnFailure } | Should -Throw
            { Add-OSDStageFile -Path 'C:\Tools\rejected' -WindowsPath $target } | Should -Throw '*not an intact*'
        }
    }
    It 'writes explicit encodings and preserves non-ASCII text' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive EncodingWindows
            New-Item $target -ItemType Directory | Out-Null
            foreach ($encoding in @('UTF8','UTF8BOM','Unicode')) {
                Add-OSDStageFile -Path "C:\Tools\$encoding.txt" -Content "caf$([char]233)" -Encoding $encoding -WindowsPath $target | Out-Null
            }
            Add-OSDStageFile -Path 'C:\Tools\empty.txt' -WindowsPath $target | Out-Null
            { Add-OSDStageFile -Path 'C:\Tools\ascii.txt' -Content ([string][char]233) -Encoding ASCII -WindowsPath $target } | Should -Throw
            $config=Get-Content (Join-Path $target 'Windows/Temp/OSDStage/BuiltIn/FileSystem/config.json') -Raw | ConvertFrom-Json
            $config.Operations.Count | Should -Be 4
            [BitConverter]::ToString([Convert]::FromBase64String($config.Operations[0].Data)) | Should -Be '63-61-66-C3-A9'
            [BitConverter]::ToString([Convert]::FromBase64String($config.Operations[1].Data)) | Should -Be 'EF-BB-BF-63-61-66-C3-A9'
            [BitConverter]::ToString([Convert]::FromBase64String($config.Operations[2].Data)) | Should -Be 'FF-FE-63-00-61-00-66-00-E9-00'
            $config.Operations[3].Data | Should -BeExactly ''
        }
    }
}

Describe 'Native Windows file system integration' -Skip:($env:OS -ne 'Windows_NT') {
    BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force }
    It 'runs PreInstall and the real runner, preserving unrelated files and reporting correlated results' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive OfflineWindows
            $dest=Join-Path $TestDrive NativeFiles
            New-Item $target -ItemType Directory | Out-Null
            $results=Join-Path $TestDrive Results
            $log=Join-Path $TestDrive runtime.log
            try {
                Set-OSDStageConfiguration -EnableBuiltIns $true -LogPath $log -ResultPath (Join-Path $results Latest.json) -CleanupMode Never -PreventSleep $false
                Add-OSDStageDirectory -Path "$dest\Remove\Nested" -WindowsPath $target | Out-Null
                Add-OSDStageFile -Path "$dest\Remove\Nested\temporary.txt" -Content 'remove' -WindowsPath $target | Out-Null
                Add-OSDStageDirectory -Path "$dest\Remove" -Remove -Recurse -WindowsPath $target | Out-Null
                Add-OSDStageFile -Path "$dest\keep.txt" -Content 'do-not-log-fixture' -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDStage'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage Invoke-OSDStagePreInstall.ps1) -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage Invoke-OSDStageRunner.ps1) -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                $latest=Get-Content (Join-Path $results Latest.json) -Raw | ConvertFrom-Json
                $latest.Status | Should -Be Succeeded
                $latest.Packages[0].Integrity | Should -Be Sha256Validated
                $record=Get-Content (Join-Path $results FileSystem-Result.json) -Raw | ConvertFrom-Json
                $record.DeploymentId | Should -Be $latest.DeploymentId
                $record.SuccessfulOperationCount | Should -Be 4
                $record.RebootRequested | Should -BeFalse
                Test-Path "$dest\Remove" | Should -BeFalse
                [IO.File]::ReadAllText("$dest\keep.txt") | Should -BeExactly 'do-not-log-fixture'
                (Get-Content $log -Raw) | Should -Not -Match 'do-not-log-fixture'
                ($record | ConvertTo-Json -Depth 10) | Should -Not -Match 'do-not-log-fixture'
                foreach ($path in @($env:windir, "$env:windir\Temp", "$env:ProgramData\OSDStage\Results", "$env:windir\Setup\Scripts\SetupComplete.cmd")) {
                    { Resolve-OSDStageFileSystemPath -Path $path } | Should -Throw
                }
            } finally { Set-OSDStageConfiguration -LogPath '%ProgramData%\OSDStage\Logs\Runtime.log' -ResultPath '%ProgramData%\OSDStage\Results\Latest.json' -PreventSleep $true }
        }
    }
}
