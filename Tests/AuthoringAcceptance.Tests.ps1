Describe 'Authoring acceptance coverage for issue #17' {
    BeforeAll {
        $script:acceptanceRoot = Split-Path $PSScriptRoot -Parent
        $script:acceptanceModule = Join-Path $script:acceptanceRoot 'OSDApps.psd1'
        Import-Module $script:acceptanceModule -Force
        Import-Module Microsoft.PowerShell.Archive -ErrorAction Stop
        if (-not ('OSDApps.Tests.Issue17.DecliningHost' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'Helpers/DecliningHost.cs') -ErrorAction Stop
        }

        function Get-AcceptanceTreeSnapshot {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
            $rootPath = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
            $rows = @('directory|.')
            $rows += @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($rootPath.Length).Replace('\','/')
                if ($_.PSIsContainer) { 'directory|' + $relative }
                else { 'file|' + $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
            })
            $rows -join "`n"
        }

        function Invoke-DeclinedAuthoring {
            param([string]$Command, [hashtable]$Parameters)
            $confirmationHost = [OSDApps.Tests.Issue17.DecliningHost]::new()
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($confirmationHost)
            $pipeline = [powershell]::Create()
            try {
                $runspace.Open()
                $pipeline.Runspace = $runspace
                [void]$pipeline.AddScript({
                    param($ModulePath, $CommandName, $Arguments)
                    $ErrorActionPreference = 'Stop'
                    $ProgressPreference = 'SilentlyContinue'
                    $WhatIfPreference = $false
                    Import-Module $ModulePath -Force -ErrorAction Stop
                    & $CommandName @Arguments -Confirm:$true -ErrorAction Stop
                }).AddArgument($script:acceptanceModule).AddArgument($Command).AddArgument($Parameters)
                $output = @($pipeline.Invoke())
                if ($pipeline.HadErrors) { throw ($pipeline.Streams.Error | Out-String) }
                [pscustomobject]@{
                    Output = $output
                    Prompts = $confirmationHost.Interaction.PromptMessages.ToArray()
                    Choices = $confirmationHost.Interaction.SelectedChoices.ToArray()
                }
            }
            finally {
                $pipeline.Dispose()
                $runspace.Dispose()
            }
        }
    }

    BeforeEach {
        $script:previousTemp = $env:TEMP
        $script:previousTmp = $env:TMP
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:sourcePath = Join-Path $script:caseRoot 'Source'
        $script:buildPath = Join-Path $script:caseRoot 'Build'
        $script:repoPath = Join-Path $script:caseRoot 'Repository'
        $script:scratchPath = Join-Path $script:caseRoot 'IsolatedTemp'
        $script:installerMarker = Join-Path $script:caseRoot 'INSTALLER-WAS-EXECUTED.txt'
        New-Item -ItemType Directory -Path $script:sourcePath,$script:scratchPath -Force | Out-Null
        $escapedMarker = $script:installerMarker.Replace("'", "''")
        @(
            "[IO.File]::WriteAllText('$escapedMarker', 'Unexpected installer execution')"
            "throw 'Authoring and validation must never execute this fixture installer.'"
        ) | Set-Content -LiteralPath (Join-Path $script:sourcePath 'Install.ps1') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:sourcePath 'payload.txt') -Value 'original payload' -Encoding ASCII
        # Redirect only this process, and restore even when an assertion fails.
        # No enumeration or deletion of the machine's shared TEMP directory.
        $env:TEMP = $script:scratchPath
        $env:TMP = $script:scratchPath
        [IO.Path]::GetTempPath().TrimEnd('\') | Should -Be $script:scratchPath.TrimEnd('\')
    }

    AfterEach {
        try {
            @(Get-ChildItem -LiteralPath $script:scratchPath -Force -Filter 'OSDApps-*').Count | Should -Be 0
            Test-Path -LiteralPath $script:installerMarker | Should -BeFalse
        }
        finally {
            $env:TEMP = $script:previousTemp
            $env:TMP = $script:previousTmp
        }
    }

    It 'answers a real No prompt for <Command> (existing destination: <Existing>) without changing destination files' -TestCases @(
        @{Command='New-OSDAppPackage'; Existing=$false; Action='Create OSD Apps package ExampleApp 1.0.0'},
        @{Command='New-OSDAppPackage'; Existing=$true; Action='Create OSD Apps package ExampleApp 1.0.0'},
        @{Command='Add-OSDAppPackage'; Existing=$false; Action='Publish ExampleApp 1.0.0 (x64)'},
        @{Command='Add-OSDAppPackage'; Existing=$true; Action='Publish ExampleApp 1.0.0 (x64)'}
    ) {
        param($Command,$Existing,$Action)
        $parameters = @{Id='ExampleApp'; Version='1.0.0'}
        if ($Command -eq 'New-OSDAppPackage') {
            $destination = $script:buildPath
            if ($Existing) {
                New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $destination -Confirm:$false | Out-Null
                Set-Content -LiteralPath (Join-Path $script:sourcePath 'payload.txt') -Value 'replacement payload' -Encoding ASCII
            }
            $parameters.SourcePath = $script:sourcePath
            $parameters.OutputPath = $destination
        }
        else {
            $destination = $script:repoPath
            $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $script:buildPath -Confirm:$false
            if ($Existing) {
                Add-OSDAppPackage -Id ExampleApp -DisplayName 'Original app' -Version 1.0.0 -PackagePath $package.PackagePath -RepositoryPath $destination -Confirm:$false | Out-Null
            }
            $parameters.DisplayName = 'Replacement app'
            $parameters.PackagePath = $package.PackagePath
            $parameters.RepositoryPath = $destination
        }
        $before = Get-AcceptanceTreeSnapshot -Path $destination
        $sourceBefore = Get-AcceptanceTreeSnapshot -Path $script:sourcePath
        $result = Invoke-DeclinedAuthoring -Command $Command -Parameters $parameters
        $result.Prompts.Count | Should -Be 1
        $result.Prompts[0] | Should -Match ([regex]::Escape($Action))
        $result.Choices.Count | Should -Be 1
        $result.Choices[0] | Should -Be 'No'
        $result.Output.Count | Should -Be 0
        (Get-AcceptanceTreeSnapshot -Path $destination) | Should -Be $before
        (Get-AcceptanceTreeSnapshot -Path $script:sourcePath) | Should -Be $sourceBefore
    }

    It 'preserves every repository path and hash when WhatIf would replace the same published version with different content' {
        $original = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $script:buildPath -Confirm:$false
        Add-OSDAppPackage -Id ExampleApp -DisplayName 'Original app' -Vendor 'Original vendor' -Version 1.0.0 -PackagePath $original.PackagePath -RepositoryPath $script:repoPath -Confirm:$false | Out-Null
        Set-Content -LiteralPath (Join-Path $script:sourcePath 'payload.txt') -Value 'different candidate payload' -Encoding ASCII
        $candidate = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath (Join-Path $script:caseRoot 'Candidate') -Confirm:$false
        $candidate.Sha256 | Should -Not -Be $original.Sha256
        $before = Get-AcceptanceTreeSnapshot -Path $script:repoPath
        $candidateHash = (Get-FileHash -LiteralPath $candidate.PackagePath).Hash
        $result = @(Add-OSDAppPackage -Id ExampleApp -DisplayName 'Changed app' -Vendor 'Changed vendor' -Version 1.0.0 -PackagePath $candidate.PackagePath -RepositoryPath $script:repoPath -WhatIf -ErrorAction Stop)
        $result.Count | Should -Be 0
        (Get-AcceptanceTreeSnapshot -Path $script:repoPath) | Should -Be $before
        (Get-FileHash -LiteralPath $candidate.PackagePath).Hash | Should -Be $candidateHash
    }

    It 'cleans scratch data and never executes Install.ps1 during a real build, validation and publication' {
        $sourceBefore = Get-AcceptanceTreeSnapshot -Path $script:sourcePath
        $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $script:buildPath -Confirm:$false
        @(Get-ChildItem -LiteralPath $script:scratchPath -Force -Filter 'OSDApps-*').Count | Should -Be 0
        $validation = Test-OSDAppPackage -PackagePath $package.PackagePath -ErrorAction Stop
        $validation.Valid | Should -BeTrue
        $validation.InstallPs1Exists | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:scratchPath -Force -Filter 'OSDApps-*').Count | Should -Be 0
        $published = Add-OSDAppPackage -Id ExampleApp -DisplayName 'Example' -Version 1.0.0 -PackagePath $package.PackagePath -RepositoryPath $script:repoPath -Confirm:$false
        $published.Id | Should -Be 'ExampleApp'
        $published.Archive.Sha256 | Should -Be $package.Sha256
        @(Test-OSDAppRepository -RepositoryPath $script:repoPath | Where-Object { -not $_.Valid }).Count | Should -Be 0
        (Get-AcceptanceTreeSnapshot -Path $script:sourcePath) | Should -Be $sourceBefore
    }

    It 'cleans validation scratch and leaves the repository untouched when input lacks Package/Install.ps1' {
        $invalidSource = Join-Path $script:caseRoot 'InvalidSource'
        New-Item -ItemType Directory -Path $invalidSource -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $invalidSource 'readme.txt') -Value 'Not an installable package' -Encoding ASCII
        $invalidZip = Join-Path $script:caseRoot 'invalid.zip'
        Compress-Archive -Path $invalidSource -DestinationPath $invalidZip
        $validation = Test-OSDAppPackage -PackagePath $invalidZip -ErrorAction Stop
        $validation.Valid | Should -BeFalse
        $before = (Get-FileHash -LiteralPath $invalidZip).Hash
        { Add-OSDAppPackage -Id ExampleApp -DisplayName 'Invalid' -Version 1.0.0 -PackagePath $invalidZip -RepositoryPath $script:repoPath -WhatIf -ErrorAction Stop } | Should -Throw '*Package validation failed*'
        Test-Path -LiteralPath $script:repoPath | Should -BeFalse
        (Get-FileHash -LiteralPath $invalidZip).Hash | Should -Be $before
    }

    It 'removes actual build scratch after an injected compression failure without executing the installer' {
        Mock Compress-Archive {
            param($Path,$DestinationPath)
            $script:Issue17BuildScratch = [string]$Path
            if (-not (Test-Path -LiteralPath (Join-Path $Path 'Install.ps1'))) { throw 'Build fixture was not copied.' }
            throw 'Issue17 simulated compression failure'
        } -ModuleName OSDApps
        $sourceBefore = Get-AcceptanceTreeSnapshot -Path $script:sourcePath
        { New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $script:buildPath -Confirm:$false -ErrorAction Stop } | Should -Throw '*Issue17 simulated compression failure*'
        Should -Invoke Compress-Archive -ModuleName OSDApps -Exactly 1
        $observed = & (Get-Module OSDApps) { $script:Issue17BuildScratch }
        $observed.StartsWith($script:scratchPath + '\', [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        Test-Path -LiteralPath $observed | Should -BeFalse
        (Get-AcceptanceTreeSnapshot -Path $script:sourcePath) | Should -Be $sourceBefore
    }

    It 'removes partially extracted validation scratch after a simulated extraction failure' {
        $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:sourcePath -OutputPath $script:buildPath -Confirm:$false
        $before = (Get-FileHash -LiteralPath $package.PackagePath).Hash
        Mock Expand-Archive {
            param($LiteralPath,$DestinationPath)
            $script:Issue17ValidationScratch = $DestinationPath
            [void][IO.Directory]::CreateDirectory($DestinationPath)
            [IO.File]::WriteAllText((Join-Path $DestinationPath 'partial.txt'), 'Partially extracted test content')
            throw 'Issue17 simulated extraction failure'
        } -ModuleName OSDApps
        { Test-OSDAppPackage -PackagePath $package.PackagePath -ErrorAction Stop } | Should -Throw '*Issue17 simulated extraction failure*'
        Should -Invoke Expand-Archive -ModuleName OSDApps -Exactly 1
        $observed = & (Get-Module OSDApps) { $script:Issue17ValidationScratch }
        $observed.StartsWith($script:scratchPath + '\', [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        Test-Path -LiteralPath $observed | Should -BeFalse
        (Get-FileHash -LiteralPath $package.PackagePath).Hash | Should -Be $before
    }
}
