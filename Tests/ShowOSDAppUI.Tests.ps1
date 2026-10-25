Describe 'Show-OSDAppUI - read-only device inspector' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'exports the UI without loading WinForms at module import time' {
        Get-Command Show-OSDAppUI -Module OSDApps | Should -Not -BeNullOrEmpty
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('WindowsPath') | Should -BeTrue
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('Offline') | Should -BeTrue
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('CatalogUri') | Should -BeFalse
    }

    It 'has no staging, unstaging or configuration mutation calls in the UI implementation' {
        $uiSource = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $uiSource | Should -Not -Match '(?i)\bInvoke-OSDAppUIApplyChanges\b'
        $uiSource | Should -Not -Match '(?i)\bInvoke-OSDAppUIStage\b'
        $uiSource | Should -Not -Match '(?i)\bRemove-OSDAppStaging\b'
        $uiSource | Should -Not -Match '(?i)\bAdd-OSDApp(?:Microsoft|Adobe|Cisco|Mozilla|Google|\s|$)'
        $uiSource | Should -Not -Match '(?i)\bSet-OSDAppConfiguration\b'
        $uiSource | Should -Not -Match '(?i)\bNew-Item\b'
        $uiSource | Should -Not -Match '(?i)\bSet-Content\b'
        $uiSource | Should -Not -Match '(?i)\bRemove-Item\b'
    }

    It 'read-only snapshot reads a manifest containing built-in and repository apps in order' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Offline'
            $stage = Join-Path $target 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $manifestPath = Join-Path $stage 'DeviceManifest.json'
            $raw = '{"Apps":[{"Id":"MicrosoftTeams","Source":"BuiltIn","DisplayName":"Microsoft Teams","Architecture":"arm64"},{"Id":"NotepadPlusPlus","Source":"Repository","Version":"8.9.8.1","DisplayName":"Notepad++","Architecture":"x64"}]}'
            Set-Content -LiteralPath $manifestPath -Value $raw -Encoding UTF8

            Mock Get-OSDApp { @(
                [pscustomobject]@{ Id='MicrosoftTeams';Source='BuiltIn';DisplayName='Microsoft Teams' },
                [pscustomobject]@{ Id='NotepadPlusPlus';Source='Repository';DisplayName='Notepad++' }
            ) }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No USB cache' }
            Mock Add-OSDApp { throw 'MUTATION' }
            Mock Remove-OSDAppStaging { throw 'MUTATION' }

            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.ManifestExists | Should -BeTrue
            @($snapshot.StagedApps.Id) | Should -Be @('MicrosoftTeams','NotepadPlusPlus')
            $snapshot.StagedApps[0].Architecture | Should -Be 'arm64'
            $snapshot.StagedApps[1].Version | Should -Be '8.9.8.1'
            $snapshot.SetupCompleteExists | Should -BeFalse
            (Get-Content -LiteralPath $manifestPath -Raw) | Should -Be ($raw + [Environment]::NewLine)
            Should -Invoke Add-OSDApp -Exactly 0
            Should -Invoke Remove-OSDAppStaging -Exactly 0
        }
    }

    It 'shows empty staging status without creating files when manifest does not exist' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'EmptyTarget'
            New-Item -Path $target -ItemType Directory -Force | Out-Null
            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No cache' }

            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.ManifestExists | Should -BeFalse
            @($snapshot.StagedApps).Count | Should -Be 0
            (Test-Path (Join-Path $target 'Windows')) | Should -BeFalse
        }
    }

    It 'rejects malformed DeviceManifest rather than silently reporting no apps' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'InvalidTarget'
            $stage = Join-Path $target 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Value '{"StagedAt":"2026"}' -Encoding UTF8

            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            { Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline } |
                Should -Throw '*Apps property is missing*'
        }
    }

    It 'lists real cache and offline-device log paths without writing to either' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Device'
            $cache = Join-Path $TestDrive 'USB\OSDApps'
            $clientDir = Join-Path $cache 'Logs'
            $runtimeDir = Join-Path $target 'ProgramData\OSDApps\Logs'
            New-Item -ItemType Directory -Path $clientDir,$runtimeDir -Force | Out-Null
            $clientLog = Join-Path $clientDir 'Client.log'
            $runtimeLog = Join-Path $runtimeDir 'Runtime.log'
            'CLIENT ORIGINAL' | Set-Content $clientLog -Encoding UTF8
            'RUNTIME ORIGINAL' | Set-Content $runtimeLog -Encoding UTF8

            Mock Get-OSDApp { }
            Mock Get-OSDAppCache {
                [pscustomobject]@{Id='NotepadPlusPlus';Source='Repository';Valid=$true;SizeMB=6.6}
            }
            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.CachePath | Should -Be $cache
            @($snapshot.CacheEntries).Count | Should -Be 1
            @($snapshot.Logs).Count | Should -Be 2
            @($snapshot.Logs.Path) | Should -Contain $clientLog
            @($snapshot.Logs.Path) | Should -Contain $runtimeLog
            (Get-Content $clientLog -Raw) | Should -Match 'CLIENT ORIGINAL'
            (Get-Content $runtimeLog -Raw) | Should -Match 'RUNTIME ORIGINAL'
        }
    }

    It 'formats stored configuration fields but hides installer paths and download URLs' {
        InModuleScope OSDApps {
            $app = [pscustomobject]@{
                Id='Microsoft365Apps';DisplayName='Microsoft 365 Apps';Source='BuiltIn'
                Channel='MonthlyEnterprise';Architecture='x64';Language=@('nl-nl','en-us')
                SharedComputerLicensing=$true
                PackageUri='https://example.org/installer?token=sensitive'
                CommandLine='Do-Not-Surface'
            }
            $details = Format-OSDAppUIStagedDetails -Application $app
            $details | Should -Match 'Channel: MonthlyEnterprise'
            $details | Should -Match 'Language: nl-nl, en-us'
            $details | Should -Match 'SharedComputerLicensing: True'
            $details | Should -Not -Match 'token=sensitive'
            $details | Should -Not -Match 'Do-Not-Surface'
            $details | Should -Match 'does not confirm'
        }
    }

    It 'does not query configured repository online when Get-OSDApp -Offline is used' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.org/catalog.json'} }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Get-OSDAppCatalogPackages { throw 'Should not query online' }
            @((Get-OSDApp -Offline) | Where-Object Source -eq 'BuiltIn').Count | Should -BeGreaterThan 11
            Should -Invoke Get-OSDAppCatalogPackages -Exactly 0
        }
    }

    It 'preserves session configuration during snapshot' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.org/catalog.json'} }
            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Set-OSDAppConfiguration { throw 'Unexpected configuration mutation' }
            Get-OSDAppUIReadOnlySnapshot -Offline | Out-Null
            Should -Invoke Set-OSDAppConfiguration -Exactly 0
            (Get-OSDAppConfiguration).CatalogUri.AbsoluteUri | Should -Be 'https://example.org/catalog.json'
        }
    }
    It 'shows Current for all built-in version policies regardless of cached version' {
        InModuleScope OSDApps {
            $builtin = [pscustomobject]@{ Id='Microsoft365Apps'; Source='BuiltIn'; Version='16.0.20430.20146' }
            (Get-OSDAppUIDisplayVersion -Application $builtin) | Should -Be 'Current'
            $staged = [pscustomobject]@{ Id='MicrosoftTeams'; Source='BuiltIn'; Version=$null }
            (Get-OSDAppUIDisplayVersion -Application $staged) | Should -Be 'Current'
            $scriptApp = [pscustomobject]@{ Id='WindowsInboxCleanup'; Source='BuiltIn'; PackageType='Script'; Version='1.0.0' }
            (Get-OSDAppUIDisplayVersion -Application $scriptApp) | Should -Be '1.0.0'
            $repo = [pscustomobject]@{ Id='NotepadPlusPlus'; Source='Repository'; Version='8.9.8.1' }
            (Get-OSDAppUIDisplayVersion -Application $repo) | Should -Be '8.9.8.1'
        }
    }

    It 'displays an actual valid USB cache version without confusing it with Current' {
        InModuleScope OSDApps {
            $app = [pscustomobject]@{ Id='Microsoft365Apps';Source='BuiltIn' }
            $cache = @([pscustomobject]@{Id='Microsoft365Apps';Source='BuiltIn';Version='16.0.20430.20146';Valid=$true})
            (Get-OSDAppUICachedVersion -Application $app -CacheEntries $cache) | Should -Be '16.0.20430.20146'
            $cache[0].Version = 'Current'
            (Get-OSDAppUICachedVersion -Application $app -CacheEntries $cache) | Should -Be 'Not recorded'
            $cache[0].Valid = $false
            (Get-OSDAppUICachedVersion -Application $app -CacheEntries $cache) | Should -Be '-'
        }
    }

    It 'uses non-ambiguous USB cache labels without altering the CLI output' {
        InModuleScope OSDApps {
            (Get-OSDAppUIAvailabilityLabel -Availability 'Cached') | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'CachedOnly' -Offline) | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'CachedOnly') | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'InvalidCache') | Should -Be 'USB cache invalid'
            (Get-OSDAppUIAvailabilityLabel -Availability 'Online') | Should -Be 'Online only'
        }
    }

    It 'parses CMTrace OSDApps log line into timestamp, level, component and readable message' {
        InModuleScope OSDApps {
            $raw = '<![LOG[[StageComplete] Package staged. | Architecture=x64]LOG]!><time="05:44:09.324+00" date="10-10-2026" component="" context="" type="1" thread="" file="">'
            $entry = ConvertFrom-OSDAppUILogLine -Line $raw
            $entry.Timestamp | Should -Be '10-10-2026 05:44:09.324+00'
            $entry.Level | Should -Be 'Info'
            $entry.Component | Should -Be 'StageComplete'
            $entry.Event | Should -Be 'StageComplete'
            $entry.Message | Should -Be 'Package staged. | Architecture=x64'
            $entry.Raw | Should -Be $raw
        }
    }

    It 'preserves plain text log lines and recognizes warning and error severity' {
        InModuleScope OSDApps {
            $plain = ConvertFrom-OSDAppUILogLine -Line 'Plain text log'
            $plain.Message | Should -Be 'Plain text log'
            $plain.Timestamp | Should -Be ''
            $warning = ConvertFrom-OSDAppUILogLine -Line '<![LOG[Disk nearly full]LOG]!><time="08:00:00" date="11-10-2026" component="Cache" type="2">'
            $warning.Level | Should -Be 'Warning'
            $warning.Component | Should -Be 'Cache'
            $error = ConvertFrom-OSDAppUILogLine -Line '<![LOG[Failed]LOG]!><time="08:00:00" date="11-10-2026" component="Runner" type="3">'
            $error.Level | Should -Be 'Error'
        }
    }

    It 'read-only UI declares a search control and header-sort handlers without invoking staging' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match 'Add_TextChanged'
        $source | Should -Match 'Add_ColumnClick'
        $source | Should -Match 'Show-OSDAppUIRows'
        $source | Should -Not -Match '(?i)\bSet-OSDAppConfiguration\b'
        $source | Should -Not -Match '(?i)\bRemove-OSDAppStaging\b'
    }

    It 'displays the Adobe cached version without an MSP suffix' {
        InModuleScope OSDApps {
            $app = [pscustomobject]@{Id='AdobeAcrobatUnified';Source='BuiltIn';Architecture='x64'}
            $cache = @([pscustomobject]@{
                Id='AdobeAcrobatUnified';Source='BuiltIn';Architecture='x64'
                Version='26.002.21931';VersionSource='AdobePatchFileName';Valid=$true
            })
            (Get-OSDAppUICachedVersion -Application $app -CacheEntries $cache) |
                Should -Be '26.002.21931'
        }
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Not -Match "cacheVersion \+= ' \(MSP\)'"
    }

    It 'clearly identifies missing Firefox USB cache without implying installation' {
        InModuleScope OSDApps {
            (Get-OSDAppUIAvailabilityLabel -Availability 'Available') |
                Should -Be 'Not on USB'
        }
    }

    It 'keeps CMTrace component and event as separate fields' {
        InModuleScope OSDApps {
            $raw = '<![LOG[[CacheDetection] USB cache available]LOG]!><time="05:44:09.324+00" date="10-10-2026" component="Microsoft365Apps" type="1">'
            $entry = ConvertFrom-OSDAppUILogLine -Line $raw
            $entry.Component | Should -Be 'Microsoft365Apps'
            $entry.Event | Should -Be 'CacheDetection'
            $entry.Message | Should -Be 'USB cache available'
            $entry.Raw | Should -Be $raw
        }
    }

    It 'uses readable statuses, responsive headers and explains the cache validation scope' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match 'Set-OSDAppUIColumnWidths'
        $source | Should -Match 'Add_ClientSizeChanged'
        $source | Should -Match 'Repository'
        $source | Should -Match "USB cache:"
        $source | Should -Match "Columns.Add\('Event'"
        $source | Should -Match '\$catalogMode = if \(\$Offline\)'
        $source | Should -Not -Match "Add_Click\(\{.*?Remove-OSDAppStaging"
    }

    It 'does not conflate USB cache availability with online lookup status' {
        InModuleScope OSDApps {
            (Get-OSDAppUIAvailabilityLabel -Availability 'Cached') | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'CachedOnly' -Offline) | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'CachedOnly') | Should -Be 'USB cached'
            (Get-OSDAppUIAvailabilityLabel -Availability 'InvalidCache') | Should -Be 'USB cache invalid'
        }
    }

    It 'loads built-in Vendor metadata from the real module location even if script root is changed' {
        InModuleScope OSDApps {
            $originalRoot = $script:moduleRoot
            try {
                $script:moduleRoot = Join-Path $TestDrive 'InvalidModuleRoot'
                $metadata = @(Get-OSDAppUIBuiltInMetadata -ErrorAction Stop)
                $metadata.Count | Should -BeGreaterThan 11
                @($metadata | Where-Object Id -eq 'MicrosoftTeams')[0].Vendor |
                    Should -Be 'Microsoft'
                @($metadata | Where-Object Id -eq 'MozillaFirefoxEnterprise')[0].Vendor |
                    Should -Be 'Mozilla'
            }
            finally {
                $script:moduleRoot = $originalRoot
            }
        }
    }

    It 'uses human-readable built-in metadata instead of technical cache IDs' {
        InModuleScope OSDApps {
            $definitions = @(Get-OSDAppUIBuiltInMetadata)
            $definitions.Count | Should -BeGreaterThan 0
            $cache = [pscustomobject]@{Id='GoogleChromeEnterprise';Source='BuiltIn'}
            $display = Get-OSDAppUIDisplayInfo -Application $cache -BuiltInMetadata $definitions
            $display.DisplayName | Should -Be 'Google Chrome Enterprise'
            $display.Vendor | Should -Be 'Google'

            $office = Get-OSDAppUIDisplayInfo -Application ([pscustomobject]@{Id='Microsoft365Apps';Source='BuiltIn'}) -BuiltInMetadata $definitions
            $office.DisplayName | Should -Be 'Microsoft 365 Apps'
            $office.Vendor | Should -Be 'Microsoft'
        }
    }

    It 'uses optional repository DisplayName and Vendor without guessing absent values' {
        InModuleScope OSDApps {
            $repository = @([pscustomobject]@{
                Id='NotepadPlusPlus';Source='Repository';DisplayName='Notepad++';Vendor='Example Publisher'
            })
            $cached = [pscustomobject]@{Id='NotepadPlusPlus';Source='Repository'}
            $info = Get-OSDAppUIDisplayInfo -Application $cached -CatalogApps $repository
            $info.DisplayName | Should -Be 'Notepad++'
            $info.Vendor | Should -Be 'Example Publisher'

            $withoutVendor = Get-OSDAppUIDisplayInfo -Application ([pscustomobject]@{Id='CustomTool';Source='Repository'})
            $withoutVendor.DisplayName | Should -Be 'CustomTool'
            $withoutVendor.Vendor | Should -Be '-'
        }
    }

    It 'labels repository scripts separately without changing their execution source' {
        InModuleScope OSDApps {
            (Get-OSDAppUIPackageType -Application ([pscustomobject]@{Source='Repository';PackageType='Script'})) |
                Should -Be 'Script'
            (Get-OSDAppUIPackageType -Application ([pscustomobject]@{Source='Repository'})) |
                Should -Be 'App'
            (Get-OSDAppUIPackageType -Application ([pscustomobject]@{Source='BuiltIn'})) |
                Should -Be 'App'
        }
    }

    It 'honors the staged display name while resolving Vendor from catalog metadata' {
        InModuleScope OSDApps {
            $staged = [pscustomobject]@{
                Id='NotepadPlusPlus';Source='Repository';DisplayName='Notepad++';Version='8.9.8.1'
            }
            $catalog = @([pscustomobject]@{
                Id='NotepadPlusPlus';Source='Repository';DisplayName='Some other name';Vendor='Publisher Ltd.'
            })
            $info = Get-OSDAppUIDisplayInfo -Application $staged -CatalogApps $catalog
            $info.DisplayName | Should -Be 'Notepad++'
            $info.Vendor | Should -Be 'Publisher Ltd.'
            $details = Format-OSDAppUIStagedDetails -Application $staged -Vendor $info.Vendor
            $details | Should -Match 'Vendor: Publisher Ltd.'
            $details | Should -Match 'Version: 8.9.8.1'
        }
    }

    It 'exposes a repository Vendor from catalog metadata in Get-OSDApp' {
        InModuleScope OSDApps {
            Mock Get-OSDAppCachePath { throw 'No USB' }
            Mock Get-OSDAppHostArchitecture { 'x64' }
            Mock Get-OSDAppConfiguration {
                [pscustomobject]@{ CatalogUri=[uri]'https://example.org/catalog.json' }
            }
            Mock Get-OSDAppCatalogPackages {
                [pscustomobject]@{
                    Packages=@([pscustomobject]@{
                        Id='SampleApp';Architecture='x64';Version='1.2.3'
                        DisplayName='Sample App';Vendor='Example Publisher'
                    })
                }
            }
            $app = @(Get-OSDApp | Where-Object Id -eq 'SampleApp')
            $app.Count | Should -Be 1
            $app[0].DisplayName | Should -Be 'Sample App'
            $app[0].Vendor | Should -Be 'Example Publisher'
        }
    }

    It 'shows Vendor in Staged, Apps and Cache and names columns Display Name' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match "catalogTab = \[System.Windows.Forms.TabPage\]::new\('Apps'\)"
        $source | Should -Match "catalogList.Columns.Add\('Vendor'"
        $source | Should -Match "stagedList.Columns.Add\('Vendor'"
        $source | Should -Match 'Get-OSDAppUIDisplayInfo -Application \$entry'
        $source | Should -Match 'Get-OSDAppUIDisplayInfo -Application \$app'
        $source | Should -Match "cacheList.Columns.Add\('Vendor'"
        $source | Should -Not -Match "Columns.Add\('App'"
        $source | Should -Match "stagedList.Columns.Add\('Display Name'"
        $source | Should -Match "catalogList.Columns.Add\('Display Name'"
        $source | Should -Match "cacheList.Columns.Add\('Display Name'"
        $source | Should -Match "'Staged'\s+\{ @\(65,0,90,95,100,125,185,105\) \}"
        $source | Should -Not -Match '(?i)\bInvoke-OSDAppUIStage\b'
    }

    It 'preselects staged manifest details and the latest log entry on initial read-only load' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw

        # Both detail panes must be populated from actual read-only row data.
        $source | Should -Match '\$State\.StagedList\.Items\[0\]'
        $source | Should -Match '\$visible\.Items\[\$visible\.Items\.Count - 1\]'
        $source | Should -Match 'Format-OSDAppUIStagedDetails -Application \$selected\.Application'
        $source | Should -Match '\$State\.LogDetails\.Text = "Time:'
        $source | Should -Not -Match '\bSet-OSDAppConfiguration\b'
        $source | Should -Not -Match '\bRemove-OSDAppStaging\b'
    }

    It 'keeps cache integrity descriptions but shortens redundant read-only prose' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match 'USB cache: \$\(\$data\.CachePath\)'
        $source | Should -Match 'built-in and repository'
        $source | Should -Not -Match 'Sort: view only'
        $source | Should -Not -Match 'Read-only: built-in'
    }

    It 'renders the compact Target, USB and Offline status in a single label' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match "form.Text = 'OSDApps Viewer - Read-only'"
        $source | Should -Match "title.Text = 'OSDApps Viewer'"
        $source | Should -Match '\$contextStatus\.Text = "Target:'
        $source | Should -Match 'Target: \$\(\$State\.TargetKind\)\s+\|\s+USB: \$usbLabel\s+\|\s+\$\(\$State\.CatalogMode\)'
        $source | Should -Not -Match '\$targetStatus = \[System.Windows.Forms.Label\]'
        $source | Should -Not -Match '\$catalogStatus = \[System.Windows.Forms.Label\]'
        $source | Should -Match '\$State\.ContextToolTip\.SetToolTip'
    }

    It 'adds package type and cache Vendor without breaking numeric Size sorting' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match "'Cache'\s+\{ @\(0,75,95,88,175,95,115,74,122\) \}"
        $source | Should -Match "cacheList.Columns.Add\('Package Type',95\)"
        $source | Should -Match "cacheList.Columns.Add\('Vendor',88\)"
        $source | Should -Match 'elseif \(\$Key -eq ''Cache'' -and \$column -eq 7\)'
        $source | Should -Match 'Get-OSDAppUIDisplayInfo -Application \$entry'
        $source | Should -Match '\$item.SubItems.Add\(\[string\]\$displayInfo.Vendor\)'
        $source | Should -Not -Match '(?i)\bRemove-OSDAppStaging\b'
        $source | Should -Not -Match '(?i)\bSet-OSDAppConfiguration\b'
    }

}
