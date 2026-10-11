function Set-OSDAppUIColumnWidths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Applications','Cache','Logs')][string]$Key
    )

    $list = $State.Lists[$Key]
    if (-not $list -or $list.Columns.Count -eq 0) { return }

    # Reserve enough room for Teams' four-part package version, and let
    # Application / Message absorb remaining space on window resize.
    $fixed = switch ($Key) {
        'Staged'       { @(65,0,90,100,125,185,105) }
        'Applications' { @(0,75,90,110,175,100,100,90) }
        'Cache'        { @(0,75,88,175,95,115,74,122) }
        'Logs'         { @(185,78,135,125,0) }
    }
    $flexIndex = if ($Key -in @('Staged','Applications','Cache')) {
        if ($Key -eq 'Staged') { 1 } else { 0 }
    } else { 4 }
    $minimumFlex = if ($Key -eq 'Logs') { 270 } elseif ($Key -in @('Applications','Cache')) { 180 } else { 200 }
    $reserved = 0
    foreach ($width in $fixed) { $reserved += [int]$width }
    $available = [math]::Max(0,$list.ClientSize.Width - 22)
    $flexWidth = [math]::Max($minimumFlex,$available - $reserved)

    for ($i=0; $i -lt $fixed.Count -and $i -lt $list.Columns.Count; $i++) {
        $width = if ($i -eq $flexIndex) { $flexWidth } else { [int]$fixed[$i] }
        if ($width -gt 0 -and $list.Columns[$i].Width -ne $width) {
            $list.Columns[$i].Width = $width
        }
    }
}

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
                elseif ($Key -eq 'Cache' -and $column -eq 6) {
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
                [void]$item.SubItems.Add([string]$entry.Event)
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
        $State.LogInfo.Text = "$($entries.Count) recent lines | $path"
        Show-OSDAppUIRows -State $State -Key Logs
        Set-OSDAppUIColumnWidths -State $State -Key Logs

        # The log details pane should be useful immediately after opening.
        # Select the most recent visible entry without changing log order.
        $visible = $State.Lists['Logs']
        if ($visible.Items.Count -gt 0) {
            $last = $visible.Items[$visible.Items.Count - 1]
            $last.Selected = $true
            $entry = $last.Tag
            $State.LogDetails.Text = "Time: $($entry.Timestamp) | Level: $($entry.Level) | Component: $($entry.Component) | Event: $($entry.Event)" +
                [Environment]::NewLine + [Environment]::NewLine + [string]$entry.Message
        }
        else {
            $State.LogDetails.Text = 'No log entries match the current search.'
        }
    }
    catch {
        $State.LogInfo.Text = "Cannot read log: $($_.Exception.Message)"
        $State.LogDetails.Text = 'Unable to load the selected log file.'
        Show-OSDAppUIRows -State $State -Key Logs
    }
}

function Update-OSDAppUIReadOnlyView {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $data = Get-OSDAppUIReadOnlySnapshot -WindowsPath $State.Target -Offline:$State.Offline -SkipSignatureVerification:$State.SkipSignatureVerification
    $State.Snapshot = $data
    $builtInMetadata = @(Get-OSDAppUIBuiltInMetadata)

    $stagedItems = @(
        $number = 0
        foreach ($app in @($data.StagedApps)) {
            $number++
            $item = [System.Windows.Forms.ListViewItem]::new([string]$number)
            $displayInfo = Get-OSDAppUIDisplayInfo -Application $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            [void]$item.SubItems.Add([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            [void]$item.SubItems.Add((Get-OSDAppUIDisplayVersion -Application $app))
            [void]$item.SubItems.Add((Get-OSDAppUICachedVersion -Application $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            $item.Tag = [pscustomobject]@{ Application=$app; Vendor=$displayInfo.Vendor }
            $item
        }
    )
    $State.Rows['Staged'] = $stagedItems

    $appItems = @(
        foreach ($app in @($data.CatalogApps | Sort-Object Source,DisplayName)) {
            $displayInfo = Get-OSDAppUIDisplayInfo -Application $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            [void]$item.SubItems.Add((Get-OSDAppUIDisplayVersion -Application $app))
            [void]$item.SubItems.Add((Get-OSDAppUICachedVersion -Application $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            [void]$item.SubItems.Add((Get-OSDAppUIAvailabilityLabel -Availability $app.Availability -Offline:$State.Offline))
            [void]$item.SubItems.Add($(if ([string]$app.Id -in @($data.StagedApps.Id)) { 'Staged' } else { '-' }))
            $item
        }
        # Staged apps absent from the current catalog/cache remain visible.
        foreach ($app in @($data.StagedApps)) {
            if ([string]$app.Id -in @($data.CatalogApps.Id)) { continue }
            $displayInfo = Get-OSDAppUIDisplayInfo -Application $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
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
            $displayInfo = Get-OSDAppUIDisplayInfo -Application $entry -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($entry.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            $cacheVersion = [string]$entry.Version
            if ([string]::IsNullOrWhiteSpace($cacheVersion) -or $cacheVersion -eq 'Current') { $cacheVersion = 'Not recorded' }
            [void]$item.SubItems.Add($cacheVersion)
            [void]$item.SubItems.Add([string]$entry.Architecture)
            $integrity = if (-not $entry.Valid) {
                'Missing / invalid'
            }
            elseif ($entry.Source -eq 'Repository') {
                'SHA-256 verified'
            }
            else {
                'Files present'
            }
            [void]$item.SubItems.Add($integrity)
            [void]$item.SubItems.Add($(if ($null -ne $entry.SizeMB) { "$($entry.SizeMB) MB" } else { '-' }))
            [void]$item.SubItems.Add((Get-OSDAppUISignatureLabel -Status ([string]$entry.SignatureStatus) -Source ([string]$entry.Source)))
            if ([string]$entry.Source -eq 'BuiltIn' -and
                [string]$entry.SignatureStatus -in @('NotSigned','NotTrusted','HashMismatch','PublisherMismatch','Check failed','File missing','UnknownError')) {
                $item.ForeColor = [System.Drawing.Color]::Firebrick
            }
            $item.ToolTipText = @(
                "Integrity: $integrity"
                "Signature: $($entry.SignatureStatus)"
                "Scope: $($entry.SignatureScope)"
                "Signed file: $($entry.SignatureFile)"
                "Signer: $($entry.SignatureSigner)"
            ) -join [Environment]::NewLine
            $item.Tag = $entry
            $item
        }
    )
    $State.Rows['Cache'] = $cacheItems

    foreach ($key in @('Staged','Applications','Cache')) {
        Show-OSDAppUIRows -State $State -Key $key
        Set-OSDAppUIColumnWidths -State $State -Key $key
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
    $State.StagedInfo.Text = "$stagedCount staged for SetupComplete | $builtInCount built-in, $repositoryCount repository | SetupComplete.cmd: $setupStatus"
    $State.CacheInfo.Text = if ($data.CachePath) {
        "USB cache: $($data.CachePath) | $(@($data.CacheEntries).Count) entries | Signatures: $(if ($State.SkipSignatureVerification) { 'skipped' } elseif ($State.WinPE) { 'unavailable in WinPE' } else { 'checked where supported' })"
    } else {
        'USB cache: not connected / not found.'
    }
    $usbLabel = if ($data.CachePath) { [string]$data.CachePath } else { 'not connected' }
    $State.ContextStatus.Text = "Target: $($State.TargetKind)  |  USB: $usbLabel  |  $($State.CatalogMode)"
    $detail = "Target: $($State.TargetDescription)" + [Environment]::NewLine +
        "USB: $usbLabel" + [Environment]::NewLine + $State.CatalogDescription
    $State.ContextToolTip.SetToolTip($State.ContextStatus,$detail)
    # Show a real staged manifest entry by default instead of an empty panel.
    # This is only a UI selection; it does not change DeviceManifest ordering.
    if ($State.StagedList.Items.Count -gt 0) {
        $first = $State.StagedList.Items[0]
        $first.Selected = $true
        $selected = $first.Tag
        $State.Details.Text = Format-OSDAppUIStagedDetails -Application $selected.Application -Vendor $selected.Vendor
    }
    else {
        $State.Details.Text = if ($stagedCount) {
            'No staged applications match the current search.'
        } else {
            'No staged applications found. Stage apps using the PowerShell CLI first.'
        }
    }
    $State.Status.Text = "$stagedCount staged | $(@($data.CacheEntries).Count) USB cache entries | $(@($data.Logs).Count) logs"
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
        [switch]$TestMode,
        [switch]$SkipSignatureVerification
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
    if ($script:OSDAppUIState) { throw 'OSDApps Viewer is already open.' }
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
    $form.Text = 'OSDApps Viewer - Read-only'
    $form.Size = [System.Drawing.Size]::new(980,710)
    $form.MinimumSize = [System.Drawing.Size]::new(800,580)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = [System.Drawing.Font]::new('Segoe UI',9)

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.RowCount = 5
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',80))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',34))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',45))
    $form.Controls.Add($root)

    $header = [System.Windows.Forms.Panel]::new()
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(35,59,95)
    [void]$root.Controls.Add($header,0,0)

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = 'OSDApps Viewer'
    $title.Font = [System.Drawing.Font]::new('Segoe UI',17,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.SetBounds(18,9,670,37)
    $title.Anchor = 'Top,Left,Right'
    $header.Controls.Add($title)

    $subtitle = [System.Windows.Forms.Label]::new()
    $subtitle.Text = 'Deployment overview'
    $subtitle.ForeColor = [System.Drawing.Color]::Gainsboro
    $subtitle.SetBounds(20,49,560,23)
    $header.Controls.Add($subtitle)

    $readOnly = [System.Windows.Forms.Label]::new()
    $readOnly.Text = 'Read-only'
    $readOnly.ForeColor = [System.Drawing.Color]::White
    $readOnly.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $readOnly.SetBounds(811,22,110,28)
    $readOnly.Anchor = 'Top,Right'
    $header.Controls.Add($readOnly)

    $context = [System.Windows.Forms.Panel]::new()
    $context.Dock = 'Fill'
    $context.BackColor = [System.Drawing.Color]::FromArgb(242,244,247)
    [void]$root.Controls.Add($context,0,1)

    $targetKind = if ($TestMode) { 'Test environment' } elseif ($winPE) { 'Offline Windows' } else { 'Windows' }
    $catalogUri = (Get-OSDAppConfiguration).CatalogUri
    $catalogMode = if ($Offline) { 'Offline' } elseif ($catalogUri) { 'Online' } else { 'No catalog' }
    $catalogDescription = if ($Offline) {
        'Catalog lookup disabled (-Offline).'
    } elseif ($catalogUri) {
        "Catalog: $($catalogUri.AbsoluteUri)"
    } else {
        'Repository not configured in this PowerShell session.'
    }

    $contextStatus = [System.Windows.Forms.Label]::new()
    $contextStatus.Dock = 'Fill'
    $contextStatus.Padding = [System.Windows.Forms.Padding]::new(14,0,8,0)
    $contextStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $contextStatus.AutoEllipsis = $true
    $contextStatus.Text = "Target: $targetKind  |  USB: detecting...  |  $catalogMode"
    [void]$context.Controls.Add($contextStatus)

    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $contextToolTip = "Target: $targetText" + [Environment]::NewLine + $catalogDescription
    $toolTip.SetToolTip($contextStatus,$contextToolTip)


    $searchPanel = [System.Windows.Forms.TableLayoutPanel]::new()
    $searchPanel.Dock = 'Fill'
    $searchPanel.ColumnCount = 2
    $searchPanel.Padding = [System.Windows.Forms.Padding]::new(8,5,8,5)
    [void]$searchPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',73))
    [void]$searchPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$root.Controls.Add($searchPanel,0,2)
    $searchLabel = [System.Windows.Forms.Label]::new()
    $searchLabel.Text = 'Search'
    $searchLabel.Dock = 'Fill'
    $searchLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$searchPanel.Controls.Add($searchLabel,0,0)
    $searchBox = [System.Windows.Forms.TextBox]::new()
    $searchBox.Dock = 'Fill'
    [void]$searchPanel.Controls.Add($searchBox,1,0)

    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    [void]$root.Controls.Add($tabs,0,3)
    $stagedTab = [System.Windows.Forms.TabPage]::new('Staged for device')
    $catalogTab = [System.Windows.Forms.TabPage]::new('Apps')
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
    [void]$stagedList.Columns.Add('Display Name',270)
    [void]$stagedList.Columns.Add('Source',90)
    [void]$stagedList.Columns.Add('Vendor',100)
    [void]$stagedList.Columns.Add('Version / policy',125)
    [void]$stagedList.Columns.Add('USB version',185)
    [void]$stagedList.Columns.Add('Architecture',105)
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
    $catalogInfo.Text = 'Built-in and repository apps | Configure and stage using PowerShell CLI'
    $catalogInfo.Dock = 'Fill'
    $catalogInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$catalogLayout.Controls.Add($catalogInfo,0,0)
    $catalogList = [System.Windows.Forms.ListView]::new()
    $catalogList.Dock = 'Fill'
    $catalogList.View = 'Details'
    $catalogList.FullRowSelect = $true
    $catalogList.GridLines = $true
    [void]$catalogList.Columns.Add('Display Name',260)
    [void]$catalogList.Columns.Add('Source',90)
    [void]$catalogList.Columns.Add('Vendor',100)
    [void]$catalogList.Columns.Add('Version / policy',110)
    [void]$catalogList.Columns.Add('USB version',115)
    [void]$catalogList.Columns.Add('Architecture',95)
    [void]$catalogList.Columns.Add('Availability',160)
    [void]$catalogList.Columns.Add('Deployment',95)
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
    $cacheList.ShowItemToolTips = $true
    [void]$cacheList.Columns.Add('Display Name',265)
    [void]$cacheList.Columns.Add('Source',75)
    [void]$cacheList.Columns.Add('Vendor',88)
    [void]$cacheList.Columns.Add('USB version',175)
    [void]$cacheList.Columns.Add('Architecture',105)
    [void]$cacheList.Columns.Add('Integrity',145)
    [void]$cacheList.Columns.Add('Size',100)
    [void]$cacheList.Columns.Add('Signature',145)
    [void]$cacheLayout.Controls.Add($cacheList,0,1)

    $logsLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $logsLayout.Dock = 'Fill'
    $logsLayout.RowCount = 4
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',43))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',30))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',110))
    $logsTab.Controls.Add($logsLayout)
    $logFiles = [System.Windows.Forms.ComboBox]::new()
    $logFiles.Dock = 'Fill'
    $logFiles.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $logFiles.Margin = [System.Windows.Forms.Padding]::new(7,8,7,4)
    [void]$logsLayout.Controls.Add($logFiles,0,0)
    $logInfo = [System.Windows.Forms.Label]::new()
    $logInfo.Text = 'Select a log entry to view its full details below.'
    $logInfo.Dock = 'Fill'
    $logInfo.AutoEllipsis = $true
    [void]$logsLayout.Controls.Add($logInfo,0,1)
    $logList = [System.Windows.Forms.ListView]::new()
    $logList.View = 'Details'
    $logList.Dock = 'Fill'
    $logList.FullRowSelect = $true
    $logList.MultiSelect = $false
    $logList.GridLines = $true
    $logList.ShowItemToolTips = $true
    [void]$logList.Columns.Add('Timestamp',185)
    [void]$logList.Columns.Add('Level',78)
    [void]$logList.Columns.Add('Component',135)
    [void]$logList.Columns.Add('Event',125)
    [void]$logList.Columns.Add('Message',420)
    [void]$logsLayout.Controls.Add($logList,0,2)
    $logDetails = [System.Windows.Forms.TextBox]::new()
    $logDetails.Multiline = $true
    $logDetails.ReadOnly = $true
    $logDetails.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $logDetails.Dock = 'Fill'
    $logDetails.BackColor = [System.Drawing.Color]::White
    $logDetails.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$logsLayout.Controls.Add($logDetails,0,3)

    $footer = [System.Windows.Forms.TableLayoutPanel]::new()
    $footer.Dock = 'Fill'
    $footer.ColumnCount = 3
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',120))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',100))
    [void]$root.Controls.Add($footer,0,4)
    $status = [System.Windows.Forms.Label]::new()
    $status.Text = 'Loading inventory...'
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
        Form=$form; Target=$target; Offline=[bool]$Offline; Search=$searchBox
        SkipSignatureVerification=[bool]$SkipSignatureVerification; WinPE=[bool]$winPE
        ContextStatus=$contextStatus; ContextToolTip=$toolTip
        TargetKind=$targetKind; TargetDescription=$targetText
        CatalogMode=$catalogMode; CatalogDescription=$catalogDescription
        StagedList=$stagedList; CatalogList=$catalogList; CacheList=$cacheList
        StagedInfo=$stagedInfo; CacheInfo=$cacheInfo; Details=$details
        LogFiles=$logFiles; LogList=$logList; LogDetails=$logDetails; LogInfo=$logInfo
        LogEntries=@(); Status=$status; Snapshot=$null
        Lists=@{ Staged=$stagedList; Applications=$catalogList; Cache=$cacheList; Logs=$logList }
        Rows=@{ Staged=@(); Applications=@(); Cache=@(); Logs=@() }
        Sorts=@{
            Staged=@{Column=-1;Descending=$false}
            Applications=@{Column=-1;Descending=$false}
            Cache=@{Column=-1;Descending=$false}
            Logs=@{Column=-1;Descending=$false}
        }
    }

    $stagedList.Add_SelectedIndexChanged({
        $state=$script:OSDAppUIState
        if (-not $state -or $state.StagedList.SelectedItems.Count -eq 0) { return }
        $selected = $state.StagedList.SelectedItems[0].Tag
        $state.Details.Text = Format-OSDAppUIStagedDetails -Application $selected.Application -Vendor $selected.Vendor
    })
    $logFiles.Add_SelectedIndexChanged({
        $state=$script:OSDAppUIState
        if ($state) { Update-OSDAppUILogViewer -State $state }
    })
    $logList.Add_SelectedIndexChanged({
        $state=$script:OSDAppUIState
        if (-not $state -or $state.LogList.SelectedItems.Count -eq 0) { return }
        $entry=$state.LogList.SelectedItems[0].Tag
        $state.LogDetails.Text = "Time: $($entry.Timestamp) | Level: $($entry.Level) | Component: $($entry.Component) | Event: $($entry.Event)" +
            [Environment]::NewLine + [Environment]::NewLine + [string]$entry.Message
    })
    $searchBox.Add_TextChanged({
        $state=$script:OSDAppUIState
        if (-not $state) { return }
        foreach ($key in @('Staged','Applications','Cache','Logs')) {
            Show-OSDAppUIRows -State $state -Key $key
        }
    })
    $stagedList.Add_ColumnClick({
        $state=$script:OSDAppUIState
        if ($state) { Set-OSDAppUIListSort -State $state -Key Staged -Column $_.Column }
    })
    $catalogList.Add_ColumnClick({
        $state=$script:OSDAppUIState
        if ($state) { Set-OSDAppUIListSort -State $state -Key Applications -Column $_.Column }
    })
    $cacheList.Add_ColumnClick({
        $state=$script:OSDAppUIState
        if ($state) { Set-OSDAppUIListSort -State $state -Key Cache -Column $_.Column }
    })
    $logList.Add_ColumnClick({
        $state=$script:OSDAppUIState
        if ($state) { Set-OSDAppUIListSort -State $state -Key Logs -Column $_.Column }
    })
    $stagedList.Add_ClientSizeChanged({
        $state = $script:OSDAppUIState
        if ($state) { Set-OSDAppUIColumnWidths -State $state -Key Staged }
    })
    $catalogList.Add_ClientSizeChanged({
        $state = $script:OSDAppUIState
        if ($state) { Set-OSDAppUIColumnWidths -State $state -Key Applications }
    })
    $cacheList.Add_ClientSizeChanged({
        $state = $script:OSDAppUIState
        if ($state) { Set-OSDAppUIColumnWidths -State $state -Key Cache }
    })
    $logList.Add_ClientSizeChanged({
        $state = $script:OSDAppUIState
        if ($state) { Set-OSDAppUIColumnWidths -State $state -Key Logs }
    })
    $refresh.Add_Click({
        $state = $script:OSDAppUIState
        if (-not $state) { return }
        $state.Status.Text = 'Refreshing inventory...'
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
