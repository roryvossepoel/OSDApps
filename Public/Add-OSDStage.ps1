function Add-OSDStage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]]$Name,
        [string]$WindowsPath,
        [switch]$SkipCacheRefresh
    )

    begin {
        Assert-OSDStageSourceEnabled -Source Repository
        $requested=[System.Collections.Generic.List[string]]::new()
    }
    process { foreach($item in $Name){ if(-not [string]::IsNullOrWhiteSpace($item)){ $requested.Add($item) } } }
    end {
        $apps=@($requested | Select-Object -Unique)
        if($apps.Count -eq 0){throw 'No apps were supplied.'}

        foreach($app in $apps){
            if($app -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $app -match '\.\.'){
                throw "Invalid repository app Id '$app'."
            }
            if($app -ieq 'WindowsInboxCleanup'){throw "'WindowsInboxCleanup' is a built-in script. Use Add-OSDStageWindowsInboxCleanup instead."}
            if($app -ieq 'Microsoft365Apps'){throw "'Microsoft365Apps' is a built-in app. Use Add-OSDStageMicrosoft365Apps instead."}
            if($app -ieq 'MicrosoftTeams' -or $app -ieq 'Teams'){throw "'MicrosoftTeams' is a built-in app. Use Add-OSDStageMicrosoftTeams instead."}
            if($app -ieq 'AdobeAcrobatUnified'){throw "'AdobeAcrobatUnified' is a built-in app. Use Add-OSDStageAdobeAcrobatUnified instead."}
            if($app -ieq 'GoogleChromeEnterprise'){throw "'GoogleChromeEnterprise' is a built-in app. Use Add-OSDStageGoogleChromeEnterprise instead."}
            if($app -ieq 'MozillaFirefoxEnterprise'){throw "'MozillaFirefoxEnterprise' is a built-in app. Use Add-OSDStageMozillaFirefoxEnterprise instead."}
            if($app -ieq 'CiscoWebex'){throw "'CiscoWebex' is a built-in app. Use Add-OSDStageCiscoWebex instead."}
            if($app -in @('VisualCRedist','DotNetRuntime')){
                $command = if ($app -eq 'VisualCRedist') { 'Add-OSDStageVisualCRedist' } else { 'Add-OSDStageDotNetRuntime' }
                throw "'$app' is a built-in runtime. Use $command instead."
            }
            if($app -ieq 'VisualStudioCode'){throw "'VisualStudioCode' is a built-in app. Use Add-OSDStageVisualStudioCode instead."}
            if($app -ieq '7Zip'){throw "'7Zip' is a built-in app. Use Add-OSDStage7Zip instead."}
            if($app -ieq 'ZoomWorkplace'){throw "'ZoomWorkplace' is a built-in app. Use Add-OSDStageZoomWorkplace instead."}
        }

# USB cache is optional. When absent, stage repository archives in
        # a temporary cache on the offline Windows disk instead.
        $cachePath = $null
        try {
            $cachePath = Get-OSDStageCachePath
        }
        catch {
            Write-Verbose 'OSDCloud cache not available; using the offline Windows disk.'
        }

        $resolvedWindowsPath = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
        if (-not $cachePath) {
            $cachePath = Join-Path $resolvedWindowsPath 'Windows\Temp\OSDStage\RepositoryCache'
            Write-Verbose ("Local repository cache: {0}" -f $cachePath)
        }

        # WhatIf must not download, create a local cache, modify the manifest,
        # or update SetupComplete.cmd.
        if (-not $PSCmdlet.ShouldProcess(($apps -join ', '), "Stage repository apps for SetupComplete on $resolvedWindowsPath")) {
            return
        }

        $sourceUri = (Get-OSDStageConfiguration).CatalogUri
        $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'

        if ($sourceUri -and -not $SkipCacheRefresh) {
            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-OSDStageConsole -Level Info -Component 'Repository' -Message ("Synchronizing requested repository app(s): {0}" -f ($apps -join ', '))
            }

            try {
                Sync-OSDStageCache -CatalogUri $sourceUri -CachePath $cachePath -Name $apps -Confirm:$false -ErrorAction Stop | Out-Null
                $apps = @(Resolve-OSDStageCachedPackageId -CachePath $cachePath -Name $apps)
            }
            catch {
                if ($_.Exception.Data.Contains('OSDStageCacheLockFailure')) { throw }
                $syncError = $_.Exception.Message

                if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
                    try {
                        $apps = @(Resolve-OSDStageCachedPackageId -CachePath $cachePath -Name $apps)
                    }
                    catch {
                        throw "Repository synchronization failed ($syncError). Cached repository identities cannot be resolved safely: $($_.Exception.Message)"
                    }
                }

                # Only fall back when *every* requested archive is present and
                # matches the SHA-256 recorded in the local cache catalog.
                # A partial or corrupted cache must never be staged.
                $validCache = @()
                if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
                    try {
                        $validCache = @(Test-OSDStageRepositoryCache -CachePath $cachePath -Name $apps -ErrorAction Stop)
                    }
                    catch {
                        Write-Verbose "Offline cache validation failed: $($_.Exception.Message)"
                    }
                }

                $unavailable = @($apps | Where-Object {
                    $requestedName = $_
                    @($validCache | Where-Object { $_.Id -ieq $requestedName -and $_.Valid }).Count -ne 1
                })

                if ($unavailable.Count -gt 0) {
                    throw "Repository synchronization failed ($syncError). No valid offline cache for: $($unavailable -join ', ')."
                }

                Write-Warning "Repository synchronization failed ($syncError). Using SHA-256 validated offline cache for: $($apps -join ', ')."
            }

            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-OSDStageConsole -Level Success -Component 'Repository' -Message 'Requested repository app cache is available'
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf)) {
                throw 'No cached repository catalog is available. Configure CatalogUri and synchronize first, or attach a USB flash drive with a populated OSDStage cache.'
            }

            $apps = @(Resolve-OSDStageCachedPackageId -CachePath $cachePath -Name $apps)
            $cachedPackages = @(Test-OSDStageRepositoryCache -CachePath $cachePath -Name $apps)
            $unavailable = @($apps | Where-Object {
                $requestedName = $_
                @($cachedPackages | Where-Object { $_.Id -ieq $requestedName -and $_.Valid }).Count -ne 1
            })
            if ($unavailable.Count -gt 0) {
                throw "No valid offline cache for: $($unavailable -join ', ')."
            }

            Write-Verbose 'Using SHA-256 validated offline repository cache without synchronization.'
        }

        $stagedRelativePath='Windows\Temp\OSDStage'

        Copy-OSDStageContent -Name $apps -CachePath $cachePath -WindowsPath $resolvedWindowsPath -DestinationRelativePath $stagedRelativePath -Confirm:$false -ErrorAction Stop | Out-Null
        $manifestPath=Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
        $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Add-OSDStageSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false -ErrorAction Stop | Out-Null

        foreach($app in $apps){
            $stagedEntry = @($manifest.Packages | Where-Object { $_.Id -ieq $app } | Select-Object -First 1)
            [pscustomobject]@{
                PSTypeName='OSDStage.StagedApp'
                Name=$app
                PackageType=if($stagedEntry.Count -gt 0 -and $stagedEntry[0].PackageType){[string]$stagedEntry[0].PackageType}else{'App'}
                CachePath=$cachePath
                WindowsPath=$resolvedWindowsPath
                StagedPath=(Join-Path $resolvedWindowsPath $stagedRelativePath)
                Source='Repository'
            }
        }
    }
}
