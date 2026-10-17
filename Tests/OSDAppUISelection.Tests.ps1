Describe 'OSDApps selection preview model' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force
    }
    It 'derives defaults and allowed choices from every loaded built-in cmdlet' {
        InModuleScope OSDApps {
            Set-StrictMode -Version Latest
            foreach ($definition in @(Get-OSDAppUIBuiltInMetadata)) {
                $fields = @(Get-OSDAppUIConfigurationFields -Id $definition.Id)
                $command = Get-Command $definition.AddCommand -Module OSDApps
                @($fields.Name) | Should -Not -Contain 'WindowsPath'
                foreach ($parameter in $command.ScriptBlock.Ast.Body.ParamBlock.Parameters) {
                    $name = $parameter.Name.VariablePath.UserPath
                    if ($name -eq 'WindowsPath') { continue }
                    $field = @($fields | Where-Object Name -eq $name)[0]
                    if ($parameter.DefaultValue) { $field.Default | Should -Be $parameter.DefaultValue.SafeGetValue() }
                    $field.Type | Should -Be $command.Parameters[$name].ParameterType
                }
                { ConvertTo-OSDAppUIConfiguration -Id $definition.Id -Values (New-OSDAppUIConfiguration $definition.Id) } | Should -Not -Throw
            }
        }
    }
    It 'keeps five Office languages, Visio and shared licensing explicit without invoking staging' {
        InModuleScope OSDApps {
            Mock Add-OSDAppMicrosoft365Apps { throw 'Unexpected staging' }
            Mock Set-OSDAppConfiguration { throw 'Unexpected session mutation' }
            Mock Get-OSDAppCache { throw 'Cache must not choose settings' }
            $values = New-OSDAppUIConfiguration Microsoft365Apps
            $values.Channel = 'MonthlyEnterprise'
            $values.Language = "nl-nl`nen-us`nde-de`nfr-fr`nes-es"
            $values.IncludeVisio = $true
            $values.SharedComputerLicensing = $true
            $result = ConvertTo-OSDAppUIConfiguration Microsoft365Apps $values
            $result.Language | Should -Be @('nl-nl','en-us','de-de','fr-fr','es-es')
            $result.IncludeVisio | Should -BeTrue
            $result.IncludeProject | Should -BeFalse
            $result.SharedComputerLicensing | Should -BeTrue
            $result.Channel | Should -Be 'MonthlyEnterprise'
            $result.Architecture | Should -Be 'x64'
            Should -Invoke Add-OSDAppMicrosoft365Apps -Exactly 0
            Should -Invoke Set-OSDAppConfiguration -Exactly 0
            Should -Invoke Get-OSDAppCache -Exactly 0
        }
    }
    It 'rejects invalid channel, timeout, locale, URL and empty required settings' {
        InModuleScope OSDApps {
            $office = New-OSDAppUIConfiguration Microsoft365Apps
            $office.Channel = 'invented'
            { ConvertTo-OSDAppUIConfiguration Microsoft365Apps $office } | Should -Throw '*Channel*'
            $chrome = New-OSDAppUIConfiguration GoogleChromeEnterprise
            $chrome.InstallTimeoutMinutes = '121'
            { ConvertTo-OSDAppUIConfiguration GoogleChromeEnterprise $chrome } | Should -Throw '*InstallTimeoutMinutes*'
            $firefox = New-OSDAppUIConfiguration MozillaFirefoxEnterprise
            $firefox.Language = '..\unsafe'
            { ConvertTo-OSDAppUIConfiguration MozillaFirefoxEnterprise $firefox } | Should -Throw '*Language*'
            $chrome.InstallTimeoutMinutes = 10
            $chrome.PackageUri = 'file:///tmp/installer'
            { ConvertTo-OSDAppUIConfiguration GoogleChromeEnterprise $chrome } | Should -Throw '*PackageUri*'
            $office.Channel = ''
            { ConvertTo-OSDAppUIConfiguration Microsoft365Apps $office } | Should -Throw '*value is required*'
        }
    }
    It 'keeps Webex omitted, false and true distinct and applies its real MSI validation' {
        InModuleScope OSDApps {
            $values = New-OSDAppUIConfiguration CiscoWebex
            (ConvertTo-OSDAppUIConfiguration CiscoWebex $values).ContainsKey('EnableOutlookIntegration') | Should -BeFalse
            $values.EnableOutlookIntegration = $false
            (ConvertTo-OSDAppUIConfiguration CiscoWebex $values).EnableOutlookIntegration | Should -BeFalse
            $values.EnableOutlookIntegration = $true
            (ConvertTo-OSDAppUIConfiguration CiscoWebex $values).EnableOutlookIntegration | Should -BeTrue
            $values.AdditionalMsiProperties = 'EXAMPLE=one,two'
            (ConvertTo-OSDAppUIConfiguration CiscoWebex $values).AdditionalMsiProperties | Should -Be @('EXAMPLE=one,two')
            $values.AdditionalMsiProperties = 'ALLUSERS=0'
            { ConvertTo-OSDAppUIConfiguration CiscoWebex $values } | Should -Throw '*reserved*'
        }
    }
    It 'uses custom XML exclusively and validates it without altering the file' {
        InModuleScope OSDApps {
            $path = Join-Path $TestDrive 'custom.xml'
            '<Configuration><Add OfficeClientEdition="64" /></Configuration>' | Set-Content $path
            $hash = (Get-FileHash $path).Hash
            $values = New-OSDAppUIConfiguration Microsoft365Apps
            $values.ConfigurationXml = $path
            $values.Channel = 'ignored while XML is selected'
            $result = ConvertTo-OSDAppUIConfiguration Microsoft365Apps $values
            @($result.Keys).Count | Should -Be 2
            $result.ContainsKey('Channel') | Should -BeFalse
            $result.ConfigurationXml | Should -Be $path
            (Get-FileHash $path).Hash | Should -Be $hash
            '<!DOCTYPE x [<!ENTITY y SYSTEM "file:///secret">]><x>&y;</x>' | Set-Content $path
            { ConvertTo-OSDAppUIConfiguration Microsoft365Apps $values } | Should -Throw '*not well-formed*'
        }
    }
    It 'retains configuration across unchecking and does not merge equal IDs from different sources' {
        InModuleScope OSDApps {
            $draft = @{Entries=@{}; Order=[System.Collections.Generic.List[string]]::new()}
            $builtin = [pscustomobject]@{Id='MicrosoftTeams';Source='BuiltIn'}
            $repository = [pscustomobject]@{Id='MicrosoftTeams';Source='Repository';PackageType='Script'}
            Set-OSDAppUISelection $draft $builtin $true
            Set-OSDAppUISelection $draft $builtin $true
            Set-OSDAppUISelection $draft $repository $true
            $draft.Order.Count | Should -Be 2
            $draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture = 'arm64'
            Set-OSDAppUISelection $draft $builtin $false
            $draft.Order | Should -Be @('Repository:MicrosoftTeams')
            Set-OSDAppUISelection $draft $builtin $true
            $draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture | Should -Be 'arm64'
            $draft.Entries['Repository:MicrosoftTeams'].PackageType | Should -Be 'Script'
            Move-OSDAppUISelection $draft 'BuiltIn:MicrosoftTeams' -1
            $draft.Order | Should -Be @('BuiltIn:MicrosoftTeams','Repository:MicrosoftTeams')
            Move-OSDAppUISelection $draft 'BuiltIn:MicrosoftTeams' -1
            $draft.Order | Should -Be @('BuiltIn:MicrosoftTeams','Repository:MicrosoftTeams')
        }
    }
    It 'copies arrays independently so cancelled edits cannot change the committed preview' {
        InModuleScope OSDApps {
            $original = New-OSDAppUIConfiguration Microsoft365Apps
            $copy = Copy-OSDAppUIConfiguration $original
            $copy.Language[0] = 'nl-nl'
            $original.Language | Should -Be @('en-us')
        }
    }
}

Describe 'OSDApps selection Windows Forms controls' -Skip:($env:OS -ne 'Windows_NT') {
    BeforeAll {
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    }
    It 'opens every built-in configuration with usable defaults and leaves the entry untouched until acceptance' {
        InModuleScope OSDApps {
            Set-StrictMode -Version Latest
            foreach ($definition in @(Get-OSDAppUIBuiltInMetadata)) {
                $entry = [pscustomobject]@{Id=$definition.Id;DisplayName=$definition.DisplayName;Configuration=(New-OSDAppUIConfiguration $definition.Id)}
                $before = $entry.Configuration | ConvertTo-Json -Compress
                $dialog = New-OSDAppUIConfigurationDialog $entry
                try {
                    Save-OSDAppUIConfigurationDialog $dialog
                    $dialog.Tag.Error.Text | Should -Be ''
                    $dialog.Tag.Result | Should -Not -BeNullOrEmpty
                    ($entry.Configuration | ConvertTo-Json -Compress) | Should -Be $before
                }
                finally { $dialog.Dispose() }
            }
        }
    }
    It 'applies five Office languages and switches between XML and generated controls' {
        InModuleScope OSDApps {
            $entry = [pscustomobject]@{Id='Microsoft365Apps';DisplayName='Office';Configuration=(New-OSDAppUIConfiguration Microsoft365Apps)}
            $dialog = New-OSDAppUIConfigurationDialog $entry
            try {
                $dialog.Tag.Inputs.Language.Text = "nl-nl`r`nen-us`r`nde-de`r`nfr-fr`r`nes-es"
                $dialog.Tag.Inputs.IncludeVisio.Checked = $true
                $dialog.Tag.Inputs.SharedComputerLicensing.Checked = $true
                Save-OSDAppUIConfigurationDialog $dialog
                @($dialog.Tag.Result.Language).Count | Should -Be 5
                $dialog.Tag.Result.IncludeVisio | Should -BeTrue
                $dialog.Tag.Result.SharedComputerLicensing | Should -BeTrue
                $entry.Configuration.SharedComputerLicensing | Should -BeFalse
                $dialog.Tag.Inputs.ConfigurationXml.Text = 'missing.xml'
                $dialog.Tag.Inputs.Language.Enabled | Should -BeFalse
                Save-OSDAppUIConfigurationDialog $dialog
                $dialog.Tag.Result | Should -BeNullOrEmpty
                $dialog.Tag.Error.Text | Should -Match 'not found'
                $dialog.Tag.Inputs.ConfigurationXml.Text = ''
                $dialog.Tag.Inputs.Language.Enabled | Should -BeTrue
            }
            finally { $dialog.Dispose() }
        }
    }
    It 'preserves checked items and desired order across search, sorting and inventory reconstruction' {
        InModuleScope OSDApps {
            $form = [System.Windows.Forms.Form]::new()
            $layout = [System.Windows.Forms.TableLayoutPanel]::new(); $layout.Dock = 'Fill'; $layout.RowCount = 4
            $form.Controls.Add($layout)
            $catalog = [System.Windows.Forms.ListView]::new(); $catalog.Dock = 'Fill'; $catalog.View = 'Details'
            [void]$catalog.Columns.Add('Name',200)
            $layout.Controls.Add($catalog,0,1)
            $search = [System.Windows.Forms.TextBox]::new()
            $state = @{Form=$form; CatalogList=$catalog; Search=$search; Lists=@{Applications=$catalog}; Rows=@{Applications=@()}; Sorts=@{Applications=@{Column=-1;Descending=$false}}}
            $script:OSDAppUIState = $state
            try {
                Initialize-OSDAppUISelectionControls $state $layout
                $state.Rows.Applications = @(
                    foreach ($id in @('MicrosoftTeams','GoogleChromeEnterprise')) {
                        $row = [System.Windows.Forms.ListViewItem]::new($id)
                        $row.Tag = [pscustomobject]@{Id=$id;Source='BuiltIn'}
                        $row
                    }
                )
                $form.Show()
                Show-OSDAppUIRows $state Applications
                $catalog.Items[0].Checked = $true
                $catalog.Items[1].Checked = $true
                $state.Draft.Order.Count | Should -Be 2
                $state.Draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture = 'arm64'
                $search.Text = 'Chrome'
                Show-OSDAppUIRows $state Applications
                $catalog.Items.Count | Should -Be 1
                $catalog.Items[0].Checked | Should -BeTrue
                $state.Draft.Order.Count | Should -Be 2
                $search.Text = ''
                Set-OSDAppUIListSort $state Applications 0
                $state.Draft.Order | Should -Be @('BuiltIn:MicrosoftTeams','BuiltIn:GoogleChromeEnterprise')
                $state.Rows.Applications = @($state.Rows.Applications | ForEach-Object { $r=[System.Windows.Forms.ListViewItem]::new($_.Text); $r.Tag=$_.Tag; $r })
                Show-OSDAppUIRows $state Applications
                @($catalog.CheckedItems).Count | Should -Be 2
                $state.Draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture | Should -Be 'arm64'
                $catalog.Items[0].Checked = $false
                $state.Draft.Order.Count | Should -Be 1
            }
            finally { $script:OSDAppUIState=$null; $form.Dispose(); $search.Dispose() }
        }
    }
}
