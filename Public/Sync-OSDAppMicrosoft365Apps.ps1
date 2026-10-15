function Sync-OSDAppMicrosoft365Apps {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$Channel = 'Current',

        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')]
        [string]$ProductId = 'O365ProPlusRetail',

        [string[]]$Language = @('en-us'),
        [bool]$AcceptEula = $true,
        [bool]$SharedComputerLicensing = $false,
        [bool]$DeviceBasedLicensing = $false,
        [bool]$UpdatesEnabled = $true,
        [switch]$IncludeVisio,
        [switch]$IncludeProject,

        [ValidateSet('Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word')]
        [string[]]$ExcludeApp,

        [string]$ConfigurationXml,
        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',
        [double]$MinimumFreeSpaceGB = 8
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppMicrosoft365Apps is intended for full Windows. Pre-cache Microsoft 365 Apps from full Windows before deployment.'
    }

    if ($SharedComputerLicensing -and $DeviceBasedLicensing) {
        throw 'SharedComputerLicensing and DeviceBasedLicensing cannot both be enabled.'
    }

    if (-not $ConfigurationXml -and (-not $Language -or @($Language).Count -eq 0)) {
        throw 'At least one Office language must be specified.'
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath 'BuiltIn\Microsoft365Apps'
    $transactionRoot = "$root.osdapps-new-$([guid]::NewGuid().ToString('N'))"
    $backupRoot = "$root.osdapps-old-$([guid]::NewGuid().ToString('N'))"
    $setupPath = Join-Path $transactionRoot 'setup.exe'
    $configPath = Join-Path $transactionRoot 'configuration.xml'
    $cacheInfoPath = Join-Path $transactionRoot 'CacheInfo.json'

    if (-not $PSCmdlet.ShouldProcess($root, 'Configure and synchronize Microsoft 365 Apps built-in cache')) { return }

    Restore-OSDAppBuiltInCache -Root $root -Id Microsoft365Apps -LogPath $clientLogPath

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation 'Microsoft 365 Apps cache synchronization' -LogPath $clientLogPath | Out-Null
    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'BuiltInSyncStart' -Message 'Synchronizing Microsoft 365 Apps built-in cache.'

    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
    try {
        Save-OSDAppVerifiedBuiltInDownload -Id 'Microsoft365Apps' -Uri $OfficeDeploymentToolUri -DestinationPath $setupPath -Activity 'Downloading Office Deployment Tool' | Out-Null

    if ($ConfigurationXml) {
        Test-OSDAppOfficeConfigurationXml -Path $ConfigurationXml | Out-Null
        Copy-Item -LiteralPath $ConfigurationXml -Destination $configPath -Force
    }
    else {
        New-OSDAppOfficeConfiguration -Path $configPath `
            -Channel $Channel -Architecture $Architecture -ProductId $ProductId `
            -Language $Language -AcceptEula $AcceptEula -UpdatesEnabled $UpdatesEnabled `
            -SharedComputerLicensing $SharedComputerLicensing -DeviceBasedLicensing $DeviceBasedLicensing `
            -ExcludeApp $ExcludeApp -IncludeVisio:$IncludeVisio -IncludeProject:$IncludeProject
    }

    $downloadConfigPath = Join-Path $transactionRoot 'download-configuration.xml'
    New-OSDAppOfficeDownloadConfiguration -SourcePath $configPath -DestinationPath $downloadConfigPath -DownloadRoot $transactionRoot

    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeCacheDownloadStart' -Message 'Running Office Deployment Tool in download mode.' -Data @{ Configuration = $downloadConfigPath; TransactionRoot=$transactionRoot }

    # Validate the cached installer before it can be launched or reused.
    Assert-OSDAppBuiltInSignature -Id 'Microsoft365Apps' -FilePath $setupPath | Out-Null

    $process = Start-Process -FilePath $setupPath -ArgumentList @('/download', $downloadConfigPath) -WorkingDirectory $transactionRoot -PassThru
    try {
        while (-not $process.HasExited) {
            $downloadedBytes = 0L
            $officeRoot = Join-Path $transactionRoot 'Office'
            if (Test-Path -LiteralPath $officeRoot -PathType Container) {
                $downloadedBytes = (Get-ChildItem -LiteralPath $officeRoot -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            }
            $downloadedGB = [math]::Round(([double]$downloadedBytes / 1GB), 2)
            Write-Progress -Activity 'Downloading Microsoft 365 Apps content' -Status "$downloadedGB GB cached" -PercentComplete -1
            Start-Sleep -Seconds 2
            $process.Refresh()
        }
    }
    finally { Write-Progress -Activity 'Downloading Microsoft 365 Apps content' -Completed }

    if ($process.ExitCode -ne 0) { throw "Office Deployment Tool download failed with exit code $($process.ExitCode)." }

    $officeData = Join-Path $transactionRoot 'Office\Data'
    if (-not (Test-Path -LiteralPath $officeData -PathType Container)) { throw "Office Deployment Tool completed but Office\Data was not found: $officeData" }

    $versionFolders = @(Get-ChildItem -LiteralPath $officeData -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { try { [pscustomobject]@{ Name = $_.Name; Version = [version]$_.Name } } catch { } } | Sort-Object Version -Descending)
    $resolvedVersion = if ($versionFolders.Count -gt 0) { $versionFolders[0].Name } else { 'Unknown' }

    [ordered]@{
        Id = 'Microsoft365Apps'
        Cached = $true
        Version = $resolvedVersion
        Architecture = $Architecture
        SourcePolicy = 'Evergreen'
        SyncMethod = 'OfficeDeploymentTool'
        Updated = $true
        Channel = $Channel
        ProductId = $ProductId
        Language = @($Language)
        AcceptEula = $AcceptEula
        SharedComputerLicensing = $SharedComputerLicensing
        DeviceBasedLicensing = $DeviceBasedLicensing
        UpdatesEnabled = $UpdatesEnabled
        IncludeVisio = [bool]$IncludeVisio
        IncludeProject = [bool]$IncludeProject
        ExcludeApp = @($ExcludeApp)
        ConfigurationSource = if ($ConfigurationXml) { 'CustomXml' } else { 'Generated' }
        SyncedAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Test-OSDAppOfficeCacheGeneration -OfficeRoot $transactionRoot -ExpectedVersion $resolvedVersion -Architecture $Architecture | Out-Null
    Remove-Item -LiteralPath $downloadConfigPath -Force

    $hadPrevious = Test-Path -LiteralPath $root -PathType Container
    if ($hadPrevious) { Move-Item -LiteralPath $root -Destination $backupRoot -ErrorAction Stop }
    try {
        Move-Item -LiteralPath $transactionRoot -Destination $root -ErrorAction Stop
    }
    catch {
        if ($hadPrevious -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not (Test-Path -LiteralPath $root)) {
            Move-Item -LiteralPath $backupRoot -Destination $root -ErrorAction SilentlyContinue
        }
        throw
    }
    if (Test-Path -LiteralPath $backupRoot -PathType Container) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
    # A previous interrupted run may have left an uncommitted candidate next
    # to the restored old generation. Delete only owned siblings, and only
    # after this new complete Office generation has passed validation/promotion.
    $residuePattern = '^' + [regex]::Escape((Split-Path $root -Leaf)) + '\.osdapps-(?:new|old)-[0-9a-f]{32}$'
    Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Directory -ErrorAction Stop |
        Where-Object { $_.Name -match $residuePattern } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop }
    $removedVersions = @()

    Write-OSDAppLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'BuiltInSyncComplete' -Message 'Microsoft 365 Apps built-in cache synchronized.' -Data @{ Version = $resolvedVersion; Path = $root; Channel = $Channel; Architecture = $Architecture; RemovedVersions=$removedVersions; SourcePolicy='Evergreen'; SyncMethod='OfficeDeploymentTool' }

    [pscustomobject]@{ PSTypeName='OSDApps.BuiltInCache'; Id='Microsoft365Apps'; Version=$resolvedVersion; Architecture=$Architecture; Channel=$Channel; CachePath=$root; Cached=$true; RemovedVersions=$removedVersions }
    }
    catch {
        if (Test-Path -LiteralPath $transactionRoot) { Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $backupRoot -PathType Container) -and -not (Test-Path -LiteralPath $root)) { Move-Item -LiteralPath $backupRoot -Destination $root -ErrorAction SilentlyContinue }
        throw
    }
}
