function Set-OSDAppUIConfigurationControls {
    param([Parameter(Mandatory)]$Dialog, [Parameter(Mandatory)][hashtable]$Values)
    foreach ($field in $Dialog.Tag.Fields) {
        $control = $Dialog.Tag.Inputs[$field.Name]
        $value = $Values[$field.Name]
        if ($control -is [System.Windows.Forms.CheckBox]) { $control.Checked = [bool]$value }
        elseif ($field.Type -eq [Nullable[bool]]) {
            $control.SelectedIndex = if ($null -eq $value) { 0 } elseif ($value) { 1 } else { 2 }
        }
        elseif ($control -is [System.Windows.Forms.ComboBox]) {
            $control.SelectedIndex = if ($null -eq $value -or [string]$value -eq '') { 0 } else { $control.Items.IndexOf([string]$value) }
        }
        else { $control.Text = @($value) -join [Environment]::NewLine }
    }
    Update-OSDAppUIOfficeMode -Dialog $Dialog
}

function Update-OSDAppUIOfficeMode {
    param([Parameter(Mandatory)]$Dialog)
    if ($Dialog.Tag.Id -ne 'Microsoft365Apps') { return }
    $custom = -not [string]::IsNullOrWhiteSpace($Dialog.Tag.Inputs.ConfigurationXml.Text)
    foreach ($field in $Dialog.Tag.Fields) {
        if ($field.Name -notin @('ConfigurationXml','OfficeDeploymentToolUri')) {
            $Dialog.Tag.Inputs[$field.Name].Enabled = -not $custom
        }
    }
}

function Save-OSDAppUIConfigurationDialog {
    param([Parameter(Mandatory)]$Dialog)
    try {
        $values = @{}
        foreach ($field in $Dialog.Tag.Fields) {
            $control = $Dialog.Tag.Inputs[$field.Name]
            if ($control -is [System.Windows.Forms.CheckBox]) { $values[$field.Name] = $control.Checked }
            elseif ($field.Type -eq [Nullable[bool]]) {
                $values[$field.Name] = if ($control.SelectedIndex -eq 0) { $null } else { $control.SelectedIndex -eq 1 }
            }
            elseif ($control -is [System.Windows.Forms.ComboBox] -and $control.SelectedIndex -eq 0 -and $null -eq $field.Default) {
                $values[$field.Name] = $null
            }
            else { $values[$field.Name] = $control.Text }
        }
        $Dialog.Tag.Result = ConvertTo-OSDAppUIConfiguration -Id $Dialog.Tag.Id -Values $values
        $Dialog.Tag.Error.Text = ''
        $Dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    }
    catch {
        $Dialog.Tag.Error.Text = $_.Exception.Message
        $Dialog.Tag.Result = $null
    }
}

function New-OSDAppUIConfigurationDialog {
    param([Parameter(Mandatory)]$Entry)
    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = "Configure $($Entry.DisplayName) - selection preview"
    $dialog.Size = [System.Drawing.Size]::new(700,650)
    $dialog.MinimumSize = [System.Drawing.Size]::new(580,450)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'; $layout.RowCount = 4
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',65))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',65))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $dialog.Controls.Add($layout)
    $notice = [System.Windows.Forms.Label]::new()
    $notice.Dock = 'Fill'; $notice.Padding = [System.Windows.Forms.Padding]::new(10)
    $notice.Text = 'New selection settings start with cmdlet defaults. Cache and existing staging do not determine these choices. Apply updates this preview only.'
    if ($Entry.Id -eq 'Microsoft365Apps') {
        $notice.Text += ' A custom XML file replaces the generated Office settings below.'
    }
    $layout.Controls.Add($notice,0,0)
    $scroll = [System.Windows.Forms.Panel]::new()
    $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true
    $layout.Controls.Add($scroll,0,1)
    $fields = @(Get-OSDAppUIConfigurationFields -Id $Entry.Id)
    $table = [System.Windows.Forms.TableLayoutPanel]::new()
    $table.Dock = 'Top'; $table.AutoSize = $true; $table.ColumnCount = 2; $table.RowCount = $fields.Count
    [void]$table.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',43))
    [void]$table.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',57))
    $scroll.Controls.Add($table)
    $inputs = @{}
    $row = 0
    foreach ($field in $fields) {
        $label = [System.Windows.Forms.Label]::new()
        $label.Text = $field.Label; $label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'
        $label.Padding = [System.Windows.Forms.Padding]::new(8,0,0,0)
        $height = if ($field.Type -eq [string[]]) { 80 } else { 38 }
        [void]$table.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',$height))
        $table.Controls.Add($label,0,$row)
        if ($field.Type -in @([bool],[switch])) { $control = [System.Windows.Forms.CheckBox]::new() }
        elseif ($field.Type -eq [Nullable[bool]] -or ($field.Choices.Count -gt 0 -and $field.Type -ne [string[]])) {
            $control = [System.Windows.Forms.ComboBox]::new()
            $control.DropDownStyle = 'DropDownList'
            if ($field.Type -eq [Nullable[bool]]) { $control.Items.AddRange([object[]]@('Vendor default','Enabled','Disabled')) }
            else {
                if ($null -eq $field.Default) { [void]$control.Items.Add('(Not specified)') }
                $control.Items.AddRange([object[]]$field.Choices)
            }
        }
        else {
            $control = [System.Windows.Forms.TextBox]::new()
            if ($field.Type -eq [string[]]) { $control.Multiline = $true; $control.ScrollBars = 'Vertical' }
        }
        $control.Name = $field.Name; $control.Dock = 'Fill'; $control.Margin = [System.Windows.Forms.Padding]::new(4,6,12,4)
        $table.Controls.Add($control,1,$row)
        $inputs[$field.Name] = $control
        $row++
    }
    $errorLabel = [System.Windows.Forms.Label]::new()
    $errorLabel.Dock = 'Fill'; $errorLabel.ForeColor = [System.Drawing.Color]::Firebrick
    $errorLabel.Padding = [System.Windows.Forms.Padding]::new(10,4,10,0)
    $layout.Controls.Add($errorLabel,0,2)
    $buttons = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttons.Dock = 'Fill'; $buttons.FlowDirection = 'RightToLeft'
    $layout.Controls.Add($buttons,0,3)
    $cancel = [System.Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'; $cancel.DialogResult = 'Cancel'; $cancel.Width = 85
    $buttons.Controls.Add($cancel)
    $apply = [System.Windows.Forms.Button]::new()
    $apply.Text = 'Apply'; $apply.Width = 85
    $buttons.Controls.Add($apply)
    $reset = [System.Windows.Forms.Button]::new()
    $reset.Text = 'Reset defaults'; $reset.Width = 120
    $buttons.Controls.Add($reset)
    $dialog.CancelButton = $cancel
    $dialog.Tag = @{Id=$Entry.Id; Fields=$fields; Inputs=$inputs; Error=$errorLabel; Result=$null}
    $apply.Add_Click({ Save-OSDAppUIConfigurationDialog -Dialog $this.FindForm() })
    $reset.Add_Click({
        $window = $this.FindForm()
        Set-OSDAppUIConfigurationControls -Dialog $window -Values (New-OSDAppUIConfiguration -Id $window.Tag.Id)
        $window.Tag.Error.Text = ''
    })
    if ($Entry.Id -eq 'Microsoft365Apps') {
        $inputs.ConfigurationXml.Add_TextChanged({ Update-OSDAppUIOfficeMode -Dialog $this.FindForm() })
    }
    $values = New-OSDAppUIConfiguration -Id $Entry.Id
    foreach ($key in $Entry.Configuration.Keys) { $values[$key] = $Entry.Configuration[$key] }
    Set-OSDAppUIConfigurationControls -Dialog $dialog -Values $values
    return $dialog
}

function Show-OSDAppUIEntryConfiguration {
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)]$Entry)
    if ($Entry.Source -ne 'BuiltIn') { return }
    $dialog = New-OSDAppUIConfigurationDialog -Entry $Entry
    try {
        if ($dialog.ShowDialog($State.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $Entry.Configuration = Copy-OSDAppUIConfiguration -Configuration $dialog.Tag.Result
            Update-OSDAppUISelectionPreview -State $State
            $State.Status.Text = "Preview settings updated: $($Entry.DisplayName). Check the app to include it."
        }
    }
    finally { $dialog.Dispose() }
}

function Update-OSDAppUISelectionPreview {
    param([Parameter(Mandatory)][hashtable]$State)
    $list = $State.SelectionList
    $selectedKey = if ($list.SelectedItems.Count) { [string]$list.SelectedItems[0].Tag.Key } else { '' }
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        $number = 0
        foreach ($key in $State.Draft.Order) {
            $entry = $State.Draft.Entries[$key]
            $number++
            $item = [System.Windows.Forms.ListViewItem]::new([string]$number)
            [void]$item.SubItems.Add($entry.DisplayName)
            [void]$item.SubItems.Add($entry.Source)
            [void]$item.SubItems.Add($entry.PackageType)
            [void]$item.SubItems.Add((Format-OSDAppUIConfiguration -Entry $entry))
            $item.Tag = $entry; $item.ToolTipText = $item.SubItems[4].Text
            [void]$list.Items.Add($item)
            if ($entry.Key -eq $selectedKey) { $item.Selected = $true }
        }
    }
    finally { $list.EndUpdate() }
    $State.SelectionInfo.Text = "Selection preview: $number items | Desired order only; nothing staged | Not saved on close"
    $State.SelectionDetails.Text = 'Select a preview row to inspect all settings. Existing device staging is shown separately.'
    if ($list.SelectedItems.Count) { $State.SelectionDetails.Text = $list.SelectedItems[0].SubItems[4].Text }
    Update-OSDAppUISelectionButtons -State $State
}

function Update-OSDAppUISelectionButtons {
    param([Parameter(Mandatory)][hashtable]$State)
    $list = $State.SelectionList
    $hasSelection = $list.SelectedItems.Count -gt 0
    $State.DraftConfigure.Enabled = $hasSelection -and $list.SelectedItems[0].Tag.Source -eq 'BuiltIn'
    $State.DraftRemove.Enabled = $hasSelection
    $State.DraftUp.Enabled = $hasSelection -and $list.SelectedItems[0].Index -gt 0
    $State.DraftDown.Enabled = $hasSelection -and $list.SelectedItems[0].Index -lt ($list.Items.Count - 1)
    $State.CatalogConfigure.Enabled = $State.CatalogList.SelectedItems.Count -gt 0 -and $State.CatalogList.SelectedItems[0].Tag.Source -eq 'BuiltIn'
}

function Initialize-OSDAppUISelectionControls {
    param([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)]$Layout)
    $State.Draft = @{Entries=@{}; Order=[System.Collections.Generic.List[string]]::new()}
    $State.RenderingApplications = $false
    $State.CatalogList.CheckBoxes = $true; $State.CatalogList.MultiSelect = $false; $State.CatalogList.HideSelection = $false
    $toolbar = [System.Windows.Forms.FlowLayoutPanel]::new()
    $toolbar.Dock = 'Fill'
    $configure = [System.Windows.Forms.Button]::new()
    $configure.Text = 'Configure selected...'; $configure.Width = 160; $configure.Enabled = $false
    $toolbar.Controls.Add($configure)
    $State.CatalogConfigure = $configure
    $Layout.Controls.Add($toolbar,0,2)
    $preview = [System.Windows.Forms.TableLayoutPanel]::new()
    $preview.Dock = 'Fill'; $preview.RowCount = 4
    [void]$preview.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$preview.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$preview.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',36))
    [void]$preview.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',58))
    $Layout.Controls.Add($preview,0,3)
    $info = [System.Windows.Forms.Label]::new(); $info.Dock = 'Fill'; $info.TextAlign = 'MiddleLeft'
    $preview.Controls.Add($info,0,0); $State.SelectionInfo = $info
    $list = [System.Windows.Forms.ListView]::new()
    $list.Dock = 'Fill'; $list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false
    $list.HideSelection = $false; $list.ShowItemToolTips = $true
    [void]$list.Columns.Add('Order',50)
    [void]$list.Columns.Add('Display Name',230)
    [void]$list.Columns.Add('Source',85)
    [void]$list.Columns.Add('Package Type',95)
    [void]$list.Columns.Add('Configuration',600)
    $preview.Controls.Add($list,0,1); $State.SelectionList = $list
    $actions = [System.Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock = 'Fill'
    $preview.Controls.Add($actions,0,2)
    foreach ($pair in @(@('DraftConfigure','Configure...'),@('DraftUp','Move up'),@('DraftDown','Move down'),@('DraftRemove','Remove'))) {
        $button = [System.Windows.Forms.Button]::new(); $button.Text = $pair[1]; $button.Width = 100; $button.Enabled = $false
        $button.Tag = $pair[0]; $actions.Controls.Add($button); $State[$pair[0]] = $button
        $button.Add_Click({
            $state = $script:OSDAppUIState
            if (-not $state -or $state.SelectionList.SelectedItems.Count -eq 0) { return }
            $entry = $state.SelectionList.SelectedItems[0].Tag
            switch ($this.Tag) {
                'DraftConfigure' { Show-OSDAppUIEntryConfiguration -State $state -Entry $entry }
                'DraftUp' { Move-OSDAppUISelection -Draft $state.Draft -Key $entry.Key -Offset -1 }
                'DraftDown' { Move-OSDAppUISelection -Draft $state.Draft -Key $entry.Key -Offset 1 }
                'DraftRemove' {
                    Set-OSDAppUISelection -Draft $state.Draft -Application $entry -Selected $false
                    Show-OSDAppUIRows -State $state -Key Applications
                }
            }
            Update-OSDAppUISelectionPreview -State $state
        })
    }
    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'; $details.Multiline = $true; $details.ReadOnly = $true; $details.ScrollBars = 'Vertical'
    $details.BackColor = [System.Drawing.Color]::White
    $preview.Controls.Add($details,0,3); $State.SelectionDetails = $details
    $list.Add_SelectedIndexChanged({
        $state = $script:OSDAppUIState
        if (-not $state) { return }
        Update-OSDAppUISelectionButtons -State $state
        if ($state.SelectionList.SelectedItems.Count) { $state.SelectionDetails.Text = $state.SelectionList.SelectedItems[0].SubItems[4].Text }
    })
    $State.CatalogList.Add_ItemCheck({
        $eventArgs = $_
        $state = $script:OSDAppUIState
        if (-not $state -or $state.RenderingApplications) { return }
        $app = $state.CatalogList.Items[$_.Index].Tag
        try {
            Set-OSDAppUISelection -Draft $state.Draft -Application $app -Selected ($_.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
            Update-OSDAppUISelectionPreview -State $state
        }
        catch {
            $eventArgs.NewValue = $eventArgs.CurrentValue
            $state.Status.Text = "Selection failed: $($_.Exception.Message)"
        }
    })
    $State.CatalogList.Add_SelectedIndexChanged({
        if ($script:OSDAppUIState) { Update-OSDAppUISelectionButtons -State $script:OSDAppUIState }
    })
    $configure.Add_Click({
        $state = $script:OSDAppUIState
        if (-not $state -or $state.CatalogList.SelectedItems.Count -eq 0) { return }
        $app = $state.CatalogList.SelectedItems[0].Tag
        $key = Get-OSDAppUISelectionKey -Application $app
        if (-not $state.Draft.Entries.ContainsKey($key)) { Set-OSDAppUISelection -Draft $state.Draft -Application $app -Selected $false }
        Show-OSDAppUIEntryConfiguration -State $state -Entry $state.Draft.Entries[$key]
    })
    Update-OSDAppUISelectionPreview -State $State
}
