function Test-OSDAppDeployment {
    [CmdletBinding()]
    param(
        [string]$WindowsPath,

        [Alias('RequireCache')]
        [switch]$RequireOfflineReady,

        [ValidateRange(0, 1024)]
        [double]$MinimumFreeSpaceGB = 0,

        [switch]$ThrowOnFailure
    )

    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stageRoot = Join-Path $target 'Windows\Temp\OSDApps'
    $manifestPath = Join-Path $stageRoot 'DeviceManifest.json'
    $setupCompletePath = Join-Path $target 'Windows\Setup\Scripts\SetupComplete.cmd'
    $checks = [System.Collections.Generic.List[object]]::new()

    function Add-DeploymentCheck {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][bool]$Passed,
            [Parameter(Mandatory)][bool]$Required,
            [Parameter(Mandatory)][string]$Message,
            [string]$ApplicationId
        )

        $checks.Add([pscustomobject]@{
            PSTypeName    = 'OSDApps.DeploymentCheck'
            Name          = $Name
            ApplicationId = $ApplicationId
            Required      = $Required
            Passed        = $Passed
            Message       = $Message
        })
    }

    function Test-SafeRelativePath {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path) -or
            [IO.Path]::IsPathRooted($Path) -or
            $Path -match '[:*?"<>|\x00-\x1F]') {
            return $false
        }

        $segments = @($Path -split '[\\/]')
        return ($segments.Count -gt 0 -and @($segments | Where-Object { $_ -in @('', '.', '..') }).Count -eq 0)
    }

    function Get-BuiltInPayloadState {
        param([Parameter(Mandatory)]$App)

        $requiredPaths = @(switch ([string]$App.Type) {
            'OfficeDeploymentTool' {
                @(
                    @{ Path = [string]$App.Setup; Type = 'Leaf' },
                    @{ Path = [string]$App.Configuration; Type = 'Leaf' },
                    @{ Path = 'BuiltIn\Microsoft365Apps\Office\Data'; Type = 'Container' }
                )
                break
            }
            'MicrosoftTeamsBootstrapper' {
                @(
                    @{ Path = [string]$App.Setup; Type = 'Leaf' },
                    @{ Path = [string]$App.OfflinePackage; Type = 'Leaf' }
                )
                break
            }
            'AdobeAcrobatUnifiedZip' {
                @(@{ Path = [string]$App.Package; Type = 'Leaf' })
                break
            }
            'VisualStudioCodeExe' {
                @(@{ Path = [string]$App.Package; Type = 'Leaf' })
                break
            }
            '7ZipExe' {
                @(@{ Path = [string]$App.Package; Type = 'Leaf' })
                break
            }
            'VendorMsi' {
                @(@{ Path = [string]$App.Package; Type = 'Leaf' })
                break
            }
            default { @() }
        })

        $invalidPaths = @($requiredPaths | Where-Object { -not (Test-SafeRelativePath -Path $_.Path) })
        $missingPaths = @($requiredPaths | ForEach-Object {
            $requiredPath = [string]$_.Path
            $requiredPathType = [string]$_.Type
            if ((Test-SafeRelativePath -Path $requiredPath) -and
                -not (Test-Path -LiteralPath (Join-Path $stageRoot $requiredPath) -PathType $requiredPathType)) {
                $requiredPath
            }
        })

        [pscustomobject]@{
            DefinitionValid = ($requiredPaths.Count -gt 0 -and $invalidPaths.Count -eq 0)
            PayloadReady    = ($requiredPaths.Count -gt 0 -and $invalidPaths.Count -eq 0 -and $missingPaths.Count -eq 0)
            MissingPaths    = @($missingPaths)
        }
    }

    function Complete-DeploymentValidation {
        param(
            $Manifest,
            [object[]]$Applications,
            [bool]$OfflineReady,
            [bool]$NetworkRequired,
            $FreeSpaceGB
        )

        $failedRequired = @($checks | Where-Object { $_.Required -and -not $_.Passed })
        $result = [pscustomobject]@{
            PSTypeName       = 'OSDApps.DeploymentValidation'
            WindowsPath      = $target
            StagedPath       = $stageRoot
            ManifestPath     = $manifestPath
            SetupCompletePath= $setupCompletePath
            DeploymentId     = if ($Manifest -and $Manifest.DeploymentId) { [string]$Manifest.DeploymentId } else { $null }
            ApplicationCount = @($Applications).Count
            Applications     = @($Applications)
            RequireOfflineReady = [bool]$RequireOfflineReady
            OfflineReady     = $OfflineReady
            NetworkRequired  = $NetworkRequired
            FreeSpaceGB      = $FreeSpaceGB
            Checks           = @($checks)
            Valid            = ($failedRequired.Count -eq 0)
        }

        if ($ThrowOnFailure -and -not $result.Valid) {
            $messages = @($failedRequired | ForEach-Object { $_.Message })
            throw "OSDApps deployment validation failed: $($messages -join ' | ')"
        }

        $result
    }

    $manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
    Add-DeploymentCheck -Name 'DeviceManifest' -Passed $manifestExists -Required $true -Message $(
        if ($manifestExists) { 'DeviceManifest.json is present.' } else { "DeviceManifest.json is missing: $manifestPath" }
    )
    if (-not $manifestExists) {
        return (Complete-DeploymentValidation -Manifest $null -Applications @() -OfflineReady $false -NetworkRequired $false -FreeSpaceGB $null)
    }

    $manifest = $null
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        Add-DeploymentCheck -Name 'ManifestJson' -Passed $true -Required $true -Message 'DeviceManifest.json contains valid JSON.'
    }
    catch {
        Add-DeploymentCheck -Name 'ManifestJson' -Passed $false -Required $true -Message "DeviceManifest.json is invalid: $($_.Exception.Message)"
        return (Complete-DeploymentValidation -Manifest $null -Applications @() -OfflineReady $false -NetworkRequired $false -FreeSpaceGB $null)
    }

    # Capture the output of the conditional as an array. Arrays emitted inside
    # an if branch are unrolled; a single PSCustomObject has no Count in PS 5.1.
    $apps = @(
        if ($manifest.PSObject.Properties.Name -contains 'Apps') {
            $manifest.Apps | Where-Object { $null -ne $_ }
        }
    )
    $parsedDeploymentId = [guid]::Empty
    $deploymentIdValid = [guid]::TryParse([string]$manifest.DeploymentId, [ref]$parsedDeploymentId)
    Add-DeploymentCheck -Name 'DeploymentId' -Passed $deploymentIdValid -Required $true -Message $(
        if ($deploymentIdValid) { 'DeploymentId is a valid GUID.' } else { 'DeploymentId is missing or invalid; restage an application with the current module.' }
    )

    $runtimeValid = (
        $manifest.Runtime -and
        ([string]$manifest.Runtime.CleanupMode) -in @('OnSuccess', 'Never') -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.Runtime.LogPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.Runtime.ResultPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.Runtime.CacheVolumeLabel) -and
        ($null -eq $manifest.Runtime.PSObject.Properties['PreventSleep'] -or $manifest.Runtime.PreventSleep -is [bool])
    )
    Add-DeploymentCheck -Name 'RuntimeConfiguration' -Passed $runtimeValid -Required $true -Message $(
        if ($runtimeValid) { 'Runtime configuration is complete.' } else { 'Runtime configuration is incomplete or unsupported.' }
    )

    $ids = @($apps | ForEach-Object { [string]$_.Id })
    $validIds = @($ids | Where-Object { $_ -match '^[A-Za-z0-9][A-Za-z0-9._-]*$' -and $_ -notmatch '\.\.' })
    $uniqueIds = @($ids | Select-Object -Unique)
    $queueValid = ($apps.Count -gt 0 -and $validIds.Count -eq $apps.Count -and $uniqueIds.Count -eq $apps.Count)
    Add-DeploymentCheck -Name 'ApplicationQueue' -Passed $queueValid -Required $true -Message $(
        if ($queueValid) { "Application queue contains $($apps.Count) unique valid entries." } else { 'Application queue is empty, contains duplicate IDs, or contains an invalid ID.' }
    )

    $runtimeFiles = @('Invoke-OSDAppPreInstall.ps1', 'Invoke-OSDAppRunner.ps1', 'Restore-OSDAppCacheGeneration.ps1', 'Assert-OSDAppTransactionSpace.ps1', 'Enter-OSDAppCacheLock.ps1', 'Test-OSDAppOfficeCacheCompatibility.ps1', 'OSDAppSleepPrevention.ps1', 'OSDApp7Zip.ps1','OSDAppVisualStudioCode.ps1', 'Invoke-OSDAppBuiltInCacheTransaction.ps1')
    $runtimeMissing = @($runtimeFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $stageRoot $_) -PathType Leaf) })
    Add-DeploymentCheck -Name 'RuntimeScripts' -Passed ($runtimeMissing.Count -eq 0) -Required $true -Message $(
        if ($runtimeMissing.Count -eq 0) { 'Standalone runtime scripts and shared cache helpers are staged.' } else { "Missing runtime script(s): $($runtimeMissing -join ', ')." }
    )

    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $mismatchedRuntime = @()
    if ($runtimeMissing.Count -eq 0) {
        foreach ($file in $runtimeFiles) {
            $source = Join-Path $moduleRoot (Join-Path 'Runtime' $file)
            $staged = Join-Path $stageRoot $file
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
                (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
                $mismatchedRuntime += $file
            }
        }
    }
    Add-DeploymentCheck -Name 'RuntimeVersion' -Passed ($runtimeMissing.Count -eq 0 -and $mismatchedRuntime.Count -eq 0) -Required $true -Message $(
        if ($runtimeMissing.Count -eq 0 -and $mismatchedRuntime.Count -eq 0) { 'Staged runtime scripts match the loaded module.' } else { "Staged runtime does not match the loaded module: $($mismatchedRuntime -join ', ')." }
    )

    $setupValid = $false
    $setupMessage = "SetupComplete.cmd is missing: $setupCompletePath"
    if (Test-Path -LiteralPath $setupCompletePath -PathType Leaf) {
        $setupText = Get-Content -LiteralPath $setupCompletePath -Raw -ErrorAction Stop
        $preCount = [regex]::Matches($setupText, '(?m)^:: OSDApps PreInstall\r?$').Count
        $beginCount = [regex]::Matches($setupText, '(?m)^:: OSDApps Begin\r?$').Count
        $endCount = [regex]::Matches($setupText, '(?m)^:: OSDApps End\r?$').Count
        $preIndex = $setupText.IndexOf(':: OSDApps PreInstall', [StringComparison]::Ordinal)
        $beginIndex = $setupText.IndexOf(':: OSDApps Begin', [StringComparison]::Ordinal)
        $endIndex = $setupText.IndexOf(':: OSDApps End', [StringComparison]::Ordinal)
        $setupValid = (
            $preCount -eq 1 -and $beginCount -eq 1 -and $endCount -eq 1 -and
            $preIndex -lt $beginIndex -and $beginIndex -lt $endIndex -and
            $setupText -match 'Invoke-OSDAppPreInstall\.ps1' -and
            $setupText -match 'OSDAPPS_PREINSTALL_EXITCODE' -and
            $setupText -match 'Invoke-OSDAppRunner\.ps1' -and
            $setupText -match 'OSDAPPS_EXITCODE'
        )
        $setupMessage = if ($setupValid) { 'SetupComplete contains one ordered, exit-code-guarded OSDApps sequence.' } else { 'SetupComplete OSDApps markers, order, script calls, or exit-code guards are invalid.' }
    }
    Add-DeploymentCheck -Name 'SetupComplete' -Passed $setupValid -Required $true -Message $setupMessage

    $applicationStates = [System.Collections.Generic.List[object]]::new()
    $allPayloadsReady = $apps.Count -gt 0
    $networkRequired = $false
    foreach ($app in $apps) {
        $id = [string]$app.Id
        $source = [string]$app.Source
        $definitionValid = $false
        $payloadReady = $false
        $integrityValid = $null
        $detail = $null

        if ($source -eq 'Repository') {
            $archivePath = Join-Path $stageRoot (Join-Path 'Packages' (Join-Path $id 'Package.zip'))
            $definitionValid = ($app.Archive -and [string]$app.Archive.Sha256 -match '^[A-Fa-f0-9]{64}$')
            $payloadReady = Test-Path -LiteralPath $archivePath -PathType Leaf
            $integrityValid = $false
            if ($definitionValid -and $payloadReady) {
                $integrityValid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 ([string]$app.Archive.Sha256)
            }
            $payloadReady = ($payloadReady -and $integrityValid)
            $detail = if ($payloadReady) { 'Repository archive is present and SHA-256 validated.' } else { 'Repository archive is missing, malformed, or failed SHA-256 validation.' }
        }
        elseif ($source -eq 'BuiltIn') {
            $state = Get-BuiltInPayloadState -App $app
            $definitionValid = $state.DefinitionValid
            $payloadReady = $state.PayloadReady
            if ($definitionValid -and -not $payloadReady) { $networkRequired = $true }
            $detail = if ($payloadReady) { 'Complete built-in payload is staged locally.' } elseif ($definitionValid) { "Built-in acquisition is required for: $($state.MissingPaths -join ', ')." } else { 'Built-in manifest paths or type are invalid.' }
        }
        else {
            $detail = "Unsupported application source '$source'."
        }

        if (-not $payloadReady) { $allPayloadsReady = $false }
        $applicationRequiredStateValid = ($definitionValid -and ($source -ne 'Repository' -or $payloadReady))
        Add-DeploymentCheck -Name 'ApplicationDefinition' -ApplicationId $id -Passed $applicationRequiredStateValid -Required $true -Message "${id}: $detail"
        Add-DeploymentCheck -Name 'OfflinePayload' -ApplicationId $id -Passed $payloadReady -Required ([bool]$RequireOfflineReady) -Message "${id}: $detail"

        $applicationStates.Add([pscustomobject]@{
            Id              = $id
            Source          = $source
            Type            = [string]$app.Type
            Version         = if ($app.Version) { [string]$app.Version } else { $null }
            Architecture    = if ($app.Architecture) { [string]$app.Architecture } else { $null }
            DefinitionValid = $definitionValid
            PayloadReady    = $payloadReady
            IntegrityValid  = $integrityValid
            Detail          = $detail
        })
    }

    $freeSpaceGB = $null
    try {
        $driveRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($target))
        $drive = Get-PSDrive -Name $driveRoot.TrimEnd('\').TrimEnd(':') -ErrorAction Stop
        $freeSpaceGB = [math]::Round([double]$drive.Free / 1GB, 2)
        $freeSpaceValid = ($MinimumFreeSpaceGB -le 0 -or $freeSpaceGB -ge $MinimumFreeSpaceGB)
        Add-DeploymentCheck -Name 'FreeSpace' -Passed $freeSpaceValid -Required ($MinimumFreeSpaceGB -gt 0) -Message $(
            if ($freeSpaceValid) { "Offline Windows volume has $freeSpaceGB GB free." } else { "Offline Windows volume has $freeSpaceGB GB free; $MinimumFreeSpaceGB GB is required." }
        )
    }
    catch {
        Add-DeploymentCheck -Name 'FreeSpace' -Passed $false -Required ($MinimumFreeSpaceGB -gt 0) -Message "Free space could not be determined: $($_.Exception.Message)"
    }

    Complete-DeploymentValidation `
        -Manifest $manifest `
        -Applications @($applicationStates) `
        -OfflineReady $allPayloadsReady `
        -NetworkRequired $networkRequired `
        -FreeSpaceGB $freeSpaceGB
}
