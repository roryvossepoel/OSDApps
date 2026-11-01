BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'OSDStage.psd1') -Force -ErrorAction Stop
    function Format-Summary($value) { ($value | Out-String -Width 240).Trim() }
    function New-Result([string]$type, [hashtable]$fields) {
        $result = [pscustomobject]$fields
        $result.PSObject.TypeNames.Insert(0, ('OSDStage.' + $type))
        $result
    }
}

Describe 'Compact default console output' {
    It 'keeps typed objects, JSON and explicit detail views unchanged' {
        $result = New-Result StagedApp @{ Name='FileSystem'; OperationCount=9; WindowsPath='C:\'; StagedPath='C:\stage'; Paths=@('a','b') }
        $before = $result | ConvertTo-Json -Depth 8 -Compress
        Format-Summary $result | Should -Be '[STAGED] FileSystem | 9 operations queued | Windows C:\'
        ($result | ConvertTo-Json -Depth 8 -Compress) | Should -Be $before
        ($result | Format-List * | Out-String) | Should -Match 'StagedPath\s+: C:\\stage'
        $result.Paths.Count | Should -Be 2
        $result.PSObject.TypeNames | Should -Contain 'OSDStage.StagedApp'
    }

    It 'formats mixed result types as separate status lines without tables' {
        $values = @(
            New-Result StagedApp @{Name='7Zip'; WindowsPath='C:\'}
            New-Result BuiltInCache @{Id='7Zip'; Version='26.05'; Architecture='x64'; Updated=$false}
            New-Result DeploymentValidation @{Valid=$true; PackageCount=1; OfflineReady=$true; NetworkRequired=$false}
        )
        $lines = @(($values | Out-String -Width 240) -split '\r?\n' | Where-Object { $_.Trim() })
        $lines.Count | Should -Be 3
        $lines[0] | Should -Match '^\[STAGED\] 7Zip'
        $lines[1] | Should -Be '[REUSED] 7Zip | 26.05 | x64 | cache ready'
        $lines[2] | Should -Be '[READY] Deployment | 1 packages | offline ready | network not required'
    }

    It 'does not claim reuse without explicit evidence' {
        Format-Summary (New-Result BuiltInCache @{Id='Microsoft365Apps'; Cached=$true}) | Should -Match '^\[SYNCED\]'
        Format-Summary (New-Result BuiltInCache @{Id='7Zip'; Updated=$true}) | Should -Match '^\[UPDATED\]'
        Format-Summary (New-Result BuiltInCache @{Id='MicrosoftCompanyPortal'; Updated=$false; CacheReused=$true}) | Should -Match 'validated cache fallback'
    }

    It 'shows invalid and unavailable results rather than green success' {
        Format-Summary (New-Result CacheValidation @{CacheAvailable=$false; Valid=$false}) | Should -Be '[FAILED] Cache not found'
        Format-Summary (New-Result CacheValidation @{CacheAvailable=$true; Valid=$false; EntryCount=2; ValidEntryCount=1; InvalidEntryCount=1; SignatureChecksRequested=$true; SignatureChecksComplete=$false}) | Should -Be '[FAILED] Cache | 1/2 valid | 1 invalid | signatures incomplete'
        Format-Summary (New-Result CacheEntry @{Id='Broken'; Valid=$null}) | Should -Match '^\[UNKNOWN\]'
        Format-Summary (New-Result CacheEntry @{Id='Unsigned'; Valid=$true; SignatureStatus='NotTrusted'}) | Should -Match '^\[REVIEW\].*signature NotTrusted'
        Format-Summary (New-Result DeploymentValidation @{Valid=$false; PackageCount=1; Checks=@([pscustomobject]@{Name='PayloadIntegrity';Required=$true;Passed=$false;Message='sensitive error'})}) | Should -Match 'failed checks: PayloadIntegrity'
        Format-Summary (New-Result RepositoryValidation @{Id='Broken';Valid=$false;HashValid=$false;Orphaned=$true}) | Should -Match 'failed: HashValid, Orphaned'
        Format-Summary (New-Result PackageValidation @{PackagePath='Package.zip';PackageType='Script';Valid=$false;PackageFolderExists=$true;InstallPs1Exists=$false}) | Should -Match 'Install.ps1 missing'
    }

    It 'omits configuration values, content, raw errors and credentials from summaries' {
        $secret = 'DO-NOT-DISPLAY'
        $objects = @(
            New-Result Configuration @{CatalogUri="https://user:$secret@example.test/catalog?sig=$secret";LogPath=$secret; ResultPath=$secret; EnableBuiltIns=$true;EnableRepository=$true;CleanupMode='Never'}
            New-Result CatalogStatus @{Uri="https://example.test/?sig=$secret";Available=$true;Enabled=$true;PackageCount=2;SchemaVersion=2}
            New-Result StagedApp @{Name='WiFiProfiles';WindowsPath='C:\';Content=$secret;Operations=@(@{Value=$secret})}
            New-Result PackageValidation @{PackagePath='Package.zip';PackageType='Driver';Valid=$false;Error=$secret}
            New-Result CacheHealth @{CacheAvailable=$true;Healthy=$false;CatalogError=$secret;CacheCatalogError=$secret}
        )
        ($objects | Out-String -Width 240) | Should -Not -Match $secret
    }

    It 'removes metadata newlines and ANSI escapes' {
        $result = New-Result StagedApp @{Name="Test`nInjected$([char]27)[31m";WindowsPath='C:\'}
        Format-Summary $result | Should -Be '[STAGED] Test Injected | queued for SetupComplete | Windows C:\'
    }

    It 'preserves normal FileInfo formatting and only formats repository sync results' {
        $path = Join-Path $TestDrive 'CacheCatalog.json'
        '{}' | Set-Content $path
        $file = Get-Item $path
        Format-Summary $file | Should -Not -Match '\[SYNCED\]'
        $file.PSObject.TypeNames.Insert(0, 'OSDStage.RepositorySync')
        Format-Summary $file | Should -Match '^\[SYNCED\] Repository cache'
        $file | Should -BeOfType ([IO.FileInfo])
        $file.FullName | Should -Be $path
    }

    It 'preserves configuration success stream and suppressible information output' {
        $information = @()
        $result = @(Set-OSDStageConfiguration -CleanupMode Never -InformationVariable information -InformationAction SilentlyContinue)
        $result.Count | Should -Be 0
        @($information).Count | Should -Be 1
        [string]$information[0] | Should -Be '[CONFIGURED] Session configuration updated'
        @(Set-OSDStageConfiguration -InformationAction Ignore 6>&1).Count | Should -Be 0
        $information = @()
        $result = @(Set-OSDStageConfiguration -CleanupMode OnSuccess -PassThru -InformationVariable information)
        $result.Count | Should -Be 1
        @($information).Count | Should -Be 0
        $result[0].CleanupMode | Should -Be 'OnSuccess'
        $result[0].PSObject.TypeNames | Should -Contain 'OSDStage.Configuration'
        Format-Summary $result[0] | Should -Be '[CONFIGURED] Session configuration updated'
    }

    It 'does not create a repository or claim success for WhatIf' {
        $path = Join-Path $TestDrive 'planned'
        $result = New-OSDStageRepository -Path $path -WhatIf
        Test-Path $path | Should -BeFalse
        $result.Path | Should -Be $path
        Format-Summary $result | Should -Match '^\[NOT APPLIED\]'
        $actual = New-OSDStageRepository -Path $path -Confirm:$false
        Format-Summary $actual | Should -Match '^\[READY\] Repository'
    }

    It 'reports actual removals and review counts, including a zero-removal run' {
        Format-Summary (New-Result CacheClearResult @{Removed=@();Review=@()}) | Should -Be '[CLEANUP] Cache | 0 items removed | 0 preserved for review'
        Format-Summary (New-Result CacheClearResult @{Removed=@('a','b');Review=@('c')}) | Should -Be '[CLEANUP] Cache | 2 items removed | 1 preserved for review'
        Format-Summary (New-Result CacheClearPlan @{Scope='All';Removed=@()}) | Should -Match '^\[NOT APPLIED\]'
        Format-Summary (New-Result UnstagedApps @{Changed=$false;Removed=@();Remaining=@('a')}) | Should -Be '[UNCHANGED] Queue | 0 removed | 1 remaining'
    }

    It 'formats all declared result types without requiring module functions' {
        [xml]$format = Get-Content (Join-Path $root 'OSDStage.format.ps1xml') -Raw
        $types = @($format.Configuration.ViewDefinitions.View.ViewSelectedBy.TypeName)
        Remove-Module OSDStage -Force
        # Load only the view, proving it needs no public/private helper functions.
        Update-FormatData -PrependPath (Join-Path $root 'OSDStage.format.ps1xml')
        try {
            foreach ($type in $types) {
                $result = New-Result ($type -replace '^OSDStage\.','') @{Name='Example';Id='Example'}
                $text = $result | Format-Custom -View OSDStage.Summary -DisplayError -ShowError | Out-String -Width 240
                $text.Trim() | Should -Match '^\[' -Because $type
                $text | Should -Not -Match '#ERR|Error formatting|PropertyNotFound|InvalidOperation' -Because $type
            }
        }
        finally { Import-Module (Join-Path $root 'OSDStage.psd1') -Force }
    }

    It 'ships the format data in the built module' {
        $build = & (Join-Path $root 'build/Build-Module.ps1') -OutputPath (Join-Path $TestDrive 'package')
        Test-Path (Join-Path $build.Path 'OSDStage.format.ps1xml') | Should -BeTrue
        try {
            Format-Summary (Get-OSDStageConfiguration) | Should -Match '^\[CONFIGURATION\]'
            (Get-Module OSDStage).Path | Should -Be (Join-Path $build.Path 'OSDStage.psm1')
        }
        finally {
            Remove-Module OSDStage -Force
            Import-Module (Join-Path $root 'OSDStage.psd1') -Force
        }
    }
}
