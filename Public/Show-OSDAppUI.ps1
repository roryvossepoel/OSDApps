function Show-OSDAppUIRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Applications','Cache','Logs')][string]$Key
    )

    $view = $State.Lists[$Key]
    $rows = @($State.Rows[$Key])
    $needle = [string]$State.Search.Text
    if (-not [string]::IsNullOrWhiteSpace($needle)) {
        $rows = @($rows | Where-Object {
            $searchable = @($_.SubItems | ForEach-Object { [string]$_.Text }) -join ' '
            $searchable.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }

    $sorting = $State.Sorts[$Key]
    if ($sorting.Column -ge 0) {
        $column = [int]$sorting.Column
        $rows = @($rows | Sort-Object -Property @{
            Expression = {
                $value = [string]$_.SubItems[$column].Text
                if ($Key -eq 'Staged' -and $column -eq 0) {
                    [int]$value
                }
                elseif ($Key -eq 'Cache' -and $column -eq 5) {
                    $parsed = [double]0
                    $rawValue = $value.Replace(' MB','').Replace(',','.')
                    if ([double]::TryParse($rawValue,[System.Globalization.NumberStyles]::Float,
                        [System.Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)) { $parsed } else { -1.0 }
                }
                else { $value.ToLowerInvariant() }
            }
        } -Descending:([bool]$sorting.Descending))
    }

    $view.BeginUpdate()
    try {
        $view.Items.Clear()
        foreach ($item in $rows) {
            [void]$view.Items.Add($item)
        }
    }
    finally { $view.EndUpdate() }
}

function Set-OSDAppUIListSort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Applications','Cache','Logs')][string]$Key,
        [Parameter(Mandatory)][int]$Column
    )

    $previous = $State.Sorts[$Key]
    $descending = if ($previous.Column -eq $Column) { -not [bool]$previous.Descending } else { $false }
    $State.Sorts[$Key] = @{ Column=$Column; Descending=$descending }
    Show-OSDAppUIRows -State $State -Key $Key
}

function Update-OSDAppUILogViewer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $State.Rows['Logs'] = @()
    $State.LogDetails.Text = ''
    $selected = $State.LogFiles.SelectedIndex
    if ($selected -lt 0 -or $selected -ge @($State.LogEntries).Count) {
        $State.LogInfo.Text = 'Select an available log file.'
        Show-OSDAppUIRows -State $State -Key Logs
        return
    }

    $path = [string]$State.LogEntries[$selected].Path
    try {
        $entries = @(Get-OSDAppUILogRows -Path $path -Tail 500)
        $items = @(
            foreach ($entry in $entries) {
                $item = [System.Windows.Forms.ListViewItem]::new([string]$entry.Timestamp)
                [void]$item.SubItems.Add([string]$entry.Level)
                [void]$item.SubItems.Add([string]$entry.Component)
                [void]$item.SubItems.Add([string]$entry.Message)
                if ($entry.Level -eq 'Error') {
                    $item.ForeColor = [System.Drawing.Color]::Firebrick
                }
                elseif ($entry.Level -eq 'Warning') {
                    $item.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                $item.Tag = $entry
                $item.ToolTipText = [string]$entry.Raw
                $item
            }
        )
        $State.Rows['Logs'] = $items
        $State.LogInfo.Text = "$($entries.Count) recent log lines | $path | Read-only"
        Show-OSDAppUIRows -State $State -Key Logs
    }
    catch {
        $State.LogInfo.Text = "Cannot read log: $($_.Exception.Message)"
        Show-OSDAppUIRows -State $State -Key Logs
    }
}

function Update-OSDAppUIReadOnlyView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $data = Get-OSDAppUIReadOnlySnapshot -WindowsPath $State.Target -Offline:$State.Offline
    $State.Snapshot = $data

    $stagedItems = @(
        $number = 0
        foreach ($app in @($data.StagedApps)) {
            $number++
            $item = [System.Windows.Forms.ListViewItem]::new([string]$number)
            [void]$item.SubItems.Add($(if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }))
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDAppUIDisplayVersion -Application $app))
            [void]$item.SubItems.Add((Get-OSDAppUICachedVersion -Application $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            $item.Tag = $app
            $item
        }
    )
    $State.Rows['Staged'] = $stagedItems

    $appItems = @(
        foreach ($app in @($data.CatalogApps | Sort-Object Source,DisplayName)) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$app.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDAppUIDisplayVersion -Application $app))
            [void]$item.SubItems.Add((Get-OSDAppUICachedVersion -Application $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            [void]$item.SubItems.Add((Get-OSDAppUIAvailabilityLabel -Availability $app.Availability))
            [void]$item.SubItems.Add($(if ([string]$app.Id -in @($data.StagedApps.Id)) { 'Staged' } else { '-' }))
            $item
        }
        # Staged apps absent from the current catalog/cache remain visible.
        foreach ($app in @($data.StagedApps)) {
            if ([string]$app.Id -in @($data.CatalogApps.Id)) { continue }
            $item = [System.Windows.Forms.ListViewItem]::new($(if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }))
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDAppUIDisplayVersion -Application $app))
            [void]$item.SubItems.Add((Get-OSDAppUICachedVersion -Application $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            [void]$item.SubItems.Add('Not in current catalog/cache')
            [void]$item.SubItems.Add('Staged')
            $item
        }
    )
    $State.Rows['Applications'] = $appItems

    $cacheItems = @(
        foreach ($entry in @($data.CacheEntries)) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$entry.Id)
            [void]$item.SubItems.Add($(if ($entry.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            $cacheVersion = [string]$entry.Version
            if ([string]::IsNullOrWhiteSpace($cacheVersion) -or $cacheVersion -eq 'Current') { $cacheVersion = 'Not recorded' }
            [void]$item.SubItems.Add($cacheVersion)
            [void]$item.SubItems.Add([string]$entry.Architecture)
            [void]$item.SubItems.Add($(if ($entry.Valid) { 'Valid' } else { 'Missing / invalid' }))
            [void]$item.SubItems.Add($(if ($null -ne $entry.SizeMB) { "$($entry.SizeMB) MB" } else { '-' }))
            $item.Tag = $entry
            $item
        }
    )
    $State.Rows['Cache'] = $cacheItems

    foreach ($key in @('Staged','Applications','Cache')) {
        Show-OSDAppUIRows -State $State -Key $key
    }

    $State.LogFiles.Items.Clear()
    $State.LogEntries = @($data.Logs)
    foreach ($entry in $State.LogEntries) {
        [void]$State.LogFiles.Items.Add([string]$entry.Label)
    }
    if ($State.LogFiles.Items.Count -gt 0) {
        $State.LogFiles.SelectedIndex = 0
    }
    else {
        $State.Rows['Logs'] = @()
        $State.LogInfo.Text = 'No existing OSDApps log files found on the device or USB cache.'
        $State.LogDetails.Text = ''
        Show-OSDAppUIRows -State $State -Key Logs
    }

    $stagedCount = @($data.StagedApps).Count
    $builtInCount = @($data.StagedApps | Where-Object Source -eq 'BuiltIn').Count
    $repositoryCount = @($data.StagedApps | Where-Object Source -eq 'Repository').Count
    $setupStatus = if ($data.SetupCompleteExists) { 'Present' } else { 'Not found' }
    $State.StagedInfo.Text = "Pending SetupComplete: $stagedCount apps ($builtInCount built-in, $repositoryCount repository) | SetupComplete.cmd: $setupStatus | Sort: view only"
    $State.CacheInfo.Text = if ($data.CachePath) {
        "USB volume: $($data.CachePath) | $(@($data.CacheEntries).Count) entries | Separate from device staging"
    } else {
        'USB cache: not connected / not found. No cache files were changed.'
    }
    $State.Details.Text = if ($stagedCount) {
        'Select an app to view its actual staged configuration. Current means vendor-managed; USB version is separate.'
    } else {
        'No staged DeviceManifest.json entries found at this target. Run the OSDApps CLI staging commands first.'
    }
    $State.Status.Text = "Read-only | $stagedCount staged | $(@($data.CacheEntries).Count) USB cache entries | $(@($data.Logs).Count) logs"
}

function Show-OSDAppUI {
    <#
    .SYNOPSIS
    Read-only overview of staged OSDApps, built-in and repository catalog,
    USB cache, and available log files. All staging and configuration stay CLI-only.
    .EXAMPLE
    Show-OSDAppUI -Offline
    .EXAMPLE
    Show-OSDAppUI -TestMode -Offline
    .EXAMPLE
    Show-OSDAppUI -WindowsPath 'D:\' -Offline
    #>
    [CmdletBinding()]
    param(
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$PreviewOnly,
        [switch]$TestMode
    )

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        throw 'An STA session is required. Run Windows PowerShell with powershell.exe -STA -NoProfile.'
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        throw "Windows Forms is unavailable in this Windows/WinPE image: $($_.Exception.Message)"
    }
    if ($script:OSDAppUIState) { throw 'OSDApps Manager is already open.' }
    if ($TestMode -and $PSBoundParameters.ContainsKey('WindowsPath')) {
        throw '-TestMode points to the existing isolated TEMP test folder. Do not also specify -WindowsPath.'
    }

    $winPE = Test-OSDAppWinPE
    $target = $null
    $targetText = 'No Windows target detected'
    if ($TestMode) {
        $candidate = Get-OSDAppUITestWindowsPath
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $target = $candidate
            $targetText = "Test folder: $target"
        }
        else {
            $targetText = "Test folder not present: $candidate"
        }
    }
    elseif ($PSBoundParameters.ContainsKey('WindowsPath')) {
        $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
        $targetText = "Read-only Windows target: $target"
    }
    elseif ($winPE) {
        try {
            $target = Resolve-OSDAppWindowsPath
            $targetText = "WinPE target: $target"
        }
        catch {
            $targetText = "WinPE: $($_.Exception.Message)"
        }
    }
    elseif ($env:SystemDrive) {
        $target = [System.IO.Path]::GetPathRoot((Join-Path $env:SystemDrive '\Windows'))
        $targetText = "Windows target: $target"
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'OSDApps Manager - Read-only'
    $form.Size = [System.Drawing.Size]::new(980,710)
    $form.MinimumSize = [System.Drawing.Size]::new(800,580)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = [System.Drawing.Font]::new('Segoe UI',9)

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.RowCount = 3
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',138))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',45))
    $form.Controls.Add($root)

    $header = [System.Windows.Forms.Panel]::new()
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(35,59,95)
    [void]$root.Controls.Add($header,0,0)

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = 'OSDApps Manager'
    $title.Font = [System.Drawing.Font]::new('Segoe UI',17,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.SetBounds(18,8,750,36)
    $header.Controls.Add($title)

    $subtitle = [System.Windows.Forms.Label]::new()
    $subtitle.Text = 'READ ONLY  |  Inspect after CLI staging  |  No changes to the device'
    $subtitle.ForeColor = [System.Drawing.Color]::White
    $subtitle.SetBounds(20,48,900,23)
    $subtitle.Anchor = 'Top,Left,Right'
    $header.Controls.Add($subtitle)

    $targetLabel = [System.Windows.Forms.Label]::new()
    $targetLabel.Text = $targetText
    $targetLabel.ForeColor = [System.Drawing.Color]::White
    $targetLabel.AutoEllipsis = $true
    $targetLabel.SetBounds(20,76,900,23)
    $targetLabel.Anchor = 'Top,Left,Right'
    $header.Controls.Add($targetLabel)

    $repositoryLabel = [System.Windows.Forms.Label]::new()
    $repositoryLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    $repositoryLabel.AutoEllipsis = $true
    $repositoryLabel.SetBounds(20,107,900,23)
    $repositoryLabel.Anchor = 'Top,Left,Right'
    $catalogUri = (Get-OSDAppConfiguration).CatalogUri
    $repositoryLabel.Text = if ($catalogUri) { "Configured repository: $($catalogUri.AbsoluteUri)" } else { 'Repository not configured in the current PowerShell session' }
    $header.Controls.Add($repositoryLabel)

    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    [void]$root.Controls.Add($tabs,0,1)
    $stagedTab = [System.Windows.Forms.TabPage]::new('Staged for device')
    $catalogTab = [System.Windows.Forms.TabPage]::new('Applications')
    $cacheTab = [System.Windows.Forms.TabPage]::new('Cache')
    $logsTab = [System.Windows.Forms.TabPage]::new('Logs')
    foreach ($tab in @($stagedTab,$catalogTab,$cacheTab,$logsTab)) { [void]$tabs.TabPages.Add($tab) }

    $stagedLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $stagedLayout.Dock = 'Fill'
    $stagedLayout.RowCount = 3
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',38))
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',160))
    $stagedTab.Controls.Add($stagedLayout)
    $stagedInfo = [System.Windows.Forms.Label]::new()
    $stagedInfo.Dock = 'Fill'
    $stagedInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$stagedLayout.Controls.Add($stagedInfo,0,0)
    $stagedList = [System.Windows.Forms.ListView]::new()
    $stagedList.Dock = 'Fill'
    $stagedList.View = 'Details'
    $stagedList.FullRowSelect = $true
    $stagedList.GridLines = $true
    $stagedList.MultiSelect = $false
    [void]$stagedList.Columns.Add('Order',65)
    [void]$stagedList.Columns.Add('Application',285)
    [void]$stagedList.Columns.Add('Source',125)
    [void]$stagedList.Columns.Add('Version',155)
    [void]$stagedList.Columns.Add('Architecture',115)
    [void]$stagedLayout.Controls.Add($stagedList,0,1)
    $details = [System.Windows.Forms.TextBox]::new()
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.Dock = 'Fill'
    $details.BackColor = [System.Drawing.Color]::White
    [void]$stagedLayout.Controls.Add($details,0,2)

    $catalogLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $catalogLayout.Dock = 'Fill'
    $catalogLayout.RowCount = 2
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',38))
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    $catalogTab.Controls.Add($catalogLayout)
    $catalogInfo = [System.Windows.Forms.Label]::new()
    $catalogInfo.Text = 'Read-only: built-in and repository applications. Configuration and staging are CLI-only.'
    $catalogInfo.Dock = 'Fill'
    $catalogInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$catalogLayout.Controls.Add($catalogInfo,0,0)
    $catalogList = [System.Windows.Forms.ListView]::new()
    $catalogList.Dock = 'Fill'
    $catalogList.View = 'Details'
    $catalogList.FullRowSelect = $true
    $catalogList.GridLines = $true
    [void]$catalogList.Columns.Add('Application',260)
    [void]$catalogList.Columns.Add('Source',115)
    [void]$catalogList.Columns.Add('Version',120)
    [void]$catalogList.Columns.Add('Architecture',100)
    [void]$catalogList.Columns.Add('Availability',145)
    [void]$catalogList.Columns.Add('Deployment',100)
    [void]$catalogLayout.Controls.Add($catalogList,0,1)

    $cacheLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $cacheLayout.Dock = 'Fill'
    $cacheLayout.RowCount = 2
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',48))
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    $cacheTab.Controls.Add($cacheLayout)
    $cacheInfo = [System.Windows.Forms.Label]::new()
    $cacheInfo.Dock = 'Fill'
    $cacheInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $cacheInfo.AutoEllipsis = $true
    [void]$cacheLayout.Controls.Add($cacheInfo,0,0)
    $cacheList = [System.Windows.Forms.ListView]::new()
    $cacheList.Dock = 'Fill'
    $cacheList.View = 'Details'
    $cacheList.FullRowSelect = $true
    $cacheList.GridLines = $true
    [void]$cacheList.Columns.Add('Application',265)
    [void]$cacheList.Columns.Add('Source',105)
    [void]$cacheList.Columns.Add('Version',115)
    [void]$cacheList.Columns.Add('Architecture',105)
    [void]$cacheList.Columns.Add('Integrity',145)
    [void]$cacheList.Columns.Add('Size',100)
    [void]$cacheLayout.Controls.Add($cacheList,0,1)

    $logsLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $logsLayout.Dock = 'Fill'
    $logsLayout.RowCount = 2
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',43))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    $logsTab.Controls.Add($logsLayout)
    $logFiles = [System.Windows.Forms.ComboBox]::new()
    $logFiles.Dock = 'Fill'
    $logFiles.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $logFiles.Margin = [System.Windows.Forms.Padding]::new(7,8,7,4)
    [void]$logsLayout.Controls.Add($logFiles,0,0)
    $logText = [System.Windows.Forms.TextBox]::new()
    $logText.Multiline = $true
    $logText.ReadOnly = $true
    $logText.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $logText.WordWrap = $false
    $logText.Dock = 'Fill'
    $logText.BackColor = [System.Drawing.Color]::White
    $logText.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$logsLayout.Controls.Add($logText,0,1)

    $footer = [System.Windows.Forms.TableLayoutPanel]::new()
    $footer.Dock = 'Fill'
    $footer.ColumnCount = 3
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',120))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',100))
    [void]$root.Controls.Add($footer,0,2)
    $status = [System.Windows.Forms.Label]::new()
    $status.Text = 'Loading read-only inventory...'
    $status.Dock = 'Fill'
    $status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$footer.Controls.Add($status,0,0)
    $refresh = [System.Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.Dock = 'Fill'
    [void]$footer.Controls.Add($refresh,1,0)
    $close = [System.Windows.Forms.Button]::new()
    $close.Text = 'Close'
    $close.Dock = 'Fill'
    [void]$footer.Controls.Add($close,2,0)

    $script:OSDAppUIState = @{
        Form=$form; Target=$target; Offline=[bool]$Offline
        StagedList=$stagedList; CatalogList=$catalogList; CacheList=$cacheList
        StagedInfo=$stagedInfo; CacheInfo=$cacheInfo; Details=$details
        Logs=$logFiles; LogText=$logText; LogEntries=@()
        Status=$status; Snapshot=$null
    }

    $stagedList.Add_SelectedIndexChanged({
        $state = $script:OSDAppUIState
        if (-not $state -or $state.StagedList.SelectedItems.Count -eq 0) { return }
        $state.Details.Text = Format-OSDAppUIStagedDetails -Application $state.StagedList.SelectedItems[0].Tag
    })
    $logFiles.Add_SelectedIndexChanged({
        $state = $script:OSDAppUIState
        if (-not $state) { return }
        $index = $state.Logs.SelectedIndex
        if ($index -lt 0 -or $index -ge @($state.LogEntries).Count) { return }
        $file = $state.LogEntries[$index].Path
        try {
            $state.LogText.Text = (Get-Content -LiteralPath $file -Tail 250 -ErrorAction Stop) -join [Environment]::NewLine
        }
        catch {
            $state.LogText.Text = "Cannot read log $($file): $($_.Exception.Message)"
        }
    })
    $refresh.Add_Click({
        $state = $script:OSDAppUIState
        if (-not $state) { return }
        $state.Status.Text = 'Refreshing read-only inventory...'
        $state.Form.Refresh()
        try {
            Update-OSDAppUIReadOnlyView -State $state
        }
        catch {
            $state.Status.Text = "Refresh failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDApps - Inventory','OK','Error')
        }
    })
    $close.Add_Click({ $script:OSDAppUIState.Form.Close() })

    try {
        try {
            Update-OSDAppUIReadOnlyView -State $script:OSDAppUIState
        }
        catch {
            $script:OSDAppUIState.Status.Text = "Load failed: $($_.Exception.Message)"
            Write-Warning "OSDApps UI: $($_.Exception.Message)"
        }
        [void]$form.ShowDialog()
    }
    finally {
        $script:OSDAppUIState = $null
        $form.Dispose()
    }
}
