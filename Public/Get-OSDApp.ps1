function Get-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name,
        [switch]$Offline
    )

    $configuration = Get-OSDAppConfiguration
    $apps = [System.Collections.Generic.List[object]]::new()
    $cachePath = $null

    try { $cachePath = Get-OSDAppCachePath } catch { }

    $cachedPackages = @()
    if ($cachePath) {
        $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'
        if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
            try {
                $cacheCatalog = Get-OSDAppManifest -Path $cacheCatalogPath
                $cachedPackages = @($cacheCatalog.Packages)
            }
            catch {
                Write-Warning "Failed to read OSD Apps cache catalog '$cacheCatalogPath': $($_.Exception.Message)"
            }
        }
    }

    $onlinePackages = @()
    $catalogUri = if ($configuration.EnableRepository) { $configuration.CatalogUri } else { $null }
    if ($catalogUri -and -not $Offline) {
        try {
            $onlineCatalog = Get-OSDAppCatalogPackages -CatalogUri $catalogUri
            $onlinePackages = @($onlineCatalog.Packages)
        }
        catch {
            Write-Verbose "Online OSD App Catalog could not be read: $($_.Exception.Message)"
        }
    }

    $hostArchitecture = Get-OSDAppHostArchitecture

    $repositoryIds = @(
        (@($onlinePackages.Id) + @($cachedPackages.Id)) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    foreach ($id in $repositoryIds) {
        $onlineCandidates = @($onlinePackages | Where-Object { $_.Id -eq $id })
        $onlinePackage = @(
            $onlineCandidates | Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq $hostArchitecture } | Select-Object -First 1
        )
        if ($onlinePackage.Count -eq 0) {
            $onlinePackage = @(
                $onlineCandidates | Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq 'any' } | Select-Object -First 1
            )
        }
        $onlinePackage = if ($onlinePackage.Count -gt 0) { $onlinePackage[0] } else { $null }

        $cached = @($cachedPackages | Where-Object { $_.Id -eq $id } | Select-Object -First 1)
        $cachedPackage = if ($cached.Count -gt 0) { $cached[0] } else { $null }

        $cachedValid = $null
        if ($cachedPackage -and $cachePath) {
            $archivePath = Join-Path $cachePath (Join-Path 'Packages' (Join-Path $id 'Package.zip'))
            $cachedValid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 $cachedPackage.Archive.Sha256
        }

        $availability = if ($cachedPackage -and $cachedValid) {
            if ($onlinePackage) { 'Cached' } else { 'CachedOnly' }
        }
        elseif ($onlinePackage) {
            'Online'
        }
        elseif ($cachedPackage) {
            'InvalidCache'
        }
        else {
            'Unavailable'
        }

        $apps.Add([pscustomobject]@{
            PSTypeName    = 'OSDApps.App'
            Id            = $id
            Name          = $id
            Aliases       = if ($onlinePackage -and $onlinePackage.PSObject.Properties.Name -contains 'Aliases') { @($onlinePackage.Aliases) } elseif ($cachedPackage -and $cachedPackage.PSObject.Properties.Name -contains 'Aliases') { @($cachedPackage.Aliases) } else { @() }
            DisplayName   = if ($onlinePackage -and $onlinePackage.DisplayName) { $onlinePackage.DisplayName } elseif ($cachedPackage) { $cachedPackage.DisplayName } else { $id }
            Source        = 'Repository'
            PackageType   = if ($cachedPackage -and $cachedPackage.PackageType) { [string]$cachedPackage.PackageType } elseif ($onlinePackage -and $onlinePackage.PackageType) { [string]$onlinePackage.PackageType } else { 'App' }
            Vendor        = if ($onlinePackage -and $onlinePackage.Vendor) { [string]$onlinePackage.Vendor } elseif ($cachedPackage -and $cachedPackage.Vendor) { [string]$cachedPackage.Vendor } else { $null }
            OnlineVersion = if ($onlinePackage) { $onlinePackage.Version } else { $null }
            CachedVersion = if ($cachedPackage) { $cachedPackage.Version } else { $null }
            Version       = if ($cachedPackage) { $cachedPackage.Version } elseif ($onlinePackage) { $onlinePackage.Version } else { $null }
            Architecture  = if ($cachedPackage) { $cachedPackage.Architecture } elseif ($onlinePackage) { $onlinePackage.Architecture } else { $null }
            Availability  = $availability
            Valid         = $cachedValid
        })
    }

    $officeCacheInfo = $null
    $microsoftTeamsCacheInfo = $null
    $adobeCacheInfo = $null
    $chromeCacheInfo = $null
    $webexCacheInfo = $null
    $visualStudioCodeCacheInfo = $null
    $visualCCacheInfo = $null
    $dotNetCacheInfo = $null
    $sevenZipCacheInfo = $null
    $zoomCacheInfo = $null
    $cmTraceInfo = $null
    $companyPortalInfo = $null
    $firefoxCacheInfo = $null

    if ($cachePath) {
        foreach ($definition in @(
            @{ Id='Microsoft365Apps'; Path=(Join-Path $cachePath 'BuiltIn\Microsoft365Apps\CacheInfo.json') },
            @{ Id='MicrosoftCompanyPortal'; Path=(Join-Path $cachePath 'BuiltIn\MicrosoftCompanyPortal\x64\CacheInfo.json') },
        @{ Id='CMTraceOpen'; Path=(Join-Path $cachePath 'BuiltIn\CMTraceOpen\x64\CacheInfo.json') },
            @{ Id='MicrosoftTeams'; Path=(Join-Path $cachePath 'BuiltIn\MicrosoftTeams\CacheInfo.json') },
            @{ Id='AdobeAcrobatUnified'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\AdobeAcrobatUnified' (Join-Path $(if ($hostArchitecture -eq 'x86') { 'x86' } else { 'x64' }) 'CacheInfo.json'))) },
            @{ Id='GoogleChromeEnterprise'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\GoogleChromeEnterprise' (Join-Path $(if ($hostArchitecture -eq 'x86') { 'x86' } else { 'x64' }) 'CacheInfo.json'))) },
            @{ Id='CiscoWebex'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\CiscoWebex' (Join-Path $(if ($hostArchitecture -eq 'arm64') { 'arm64' } else { 'x64' }) 'CacheInfo.json'))) },
            @{ Id='VisualCRedist'; Path=(Join-Path $cachePath 'BuiltIn\VisualCRedist\x64\CacheInfo.json') },
            @{ Id='DotNetRuntime'; Path=(Join-Path $cachePath 'BuiltIn\DotNetRuntime\Desktop\10.0\x64\CacheInfo.json') },
            @{ Id='VisualStudioCode'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\VisualStudioCode' (Join-Path $hostArchitecture 'CacheInfo.json'))) },
            @{ Id='7Zip'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\7Zip' (Join-Path $hostArchitecture 'CacheInfo.json'))) },
            @{ Id='ZoomWorkplace'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\ZoomWorkplace' (Join-Path $(if ($hostArchitecture -eq 'arm64') { 'arm64' } else { 'x64' }) 'CacheInfo.json'))) }
        )) {
            if (Test-Path -LiteralPath $definition.Path -PathType Leaf) {
                try {
                    $info = Get-Content -LiteralPath $definition.Path -Raw -Encoding UTF8 | ConvertFrom-Json
                    switch ($definition.Id) {
                        'Microsoft365Apps' { $officeCacheInfo = $info }
                        'MicrosoftCompanyPortal' { $companyPortalInfo = $info }
                        'CMTraceOpen' { $cmTraceInfo = $info }
                        'MicrosoftTeams' { $microsoftTeamsCacheInfo = $info }
                        'AdobeAcrobatUnified' { $adobeCacheInfo = $info }
                        'GoogleChromeEnterprise' { $chromeCacheInfo = $info }
                        'CiscoWebex' { $webexCacheInfo = $info }
                        'VisualStudioCode' { $visualStudioCodeCacheInfo = $info }
                        'VisualCRedist' { $visualCCacheInfo = $info }
                        'DotNetRuntime' { $dotNetCacheInfo = $info }
                        '7Zip' { $sevenZipCacheInfo = $info }
                        'ZoomWorkplace' { $zoomCacheInfo = $info }
                    }
                }
                catch { }
            }
        }

        $firefoxRoot = Join-Path $cachePath 'BuiltIn\MozillaFirefoxEnterprise'
        if (Test-Path -LiteralPath $firefoxRoot -PathType Container) {
            $firefoxInfos = @(
                Get-ChildItem -LiteralPath $firefoxRoot -Filter 'CacheInfo.json' -File -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
                    } |
                    Where-Object { $_ }
            )

            $preferredArchitecture = if ($hostArchitecture -eq 'x86') { 'x86' } else { 'x64' }
            $firefoxCacheInfo = @(
                $firefoxInfos |
                    Where-Object { $_.Architecture -eq $preferredArchitecture } |
                    Sort-Object @{ Expression = { if ($_.Channel -eq 'Rapid') { 0 } else { 1 } } }, @{ Expression = { if ($_.Language -eq 'en-US') { 0 } else { 1 } } } |
                    Select-Object -First 1
            )
            if ($firefoxCacheInfo.Count -gt 0) { $firefoxCacheInfo = $firefoxCacheInfo[0] } else { $firefoxCacheInfo = $null }
        }
    }

    foreach ($builtIn in @(
        @{ Id='WindowsInboxCleanup'; DisplayName='Windows Inbox App Cleanup'; Info=$null; PackageType='Script'; Version='1.0.0'; Architecture='any' },
        @{ Id='Microsoft365Apps'; DisplayName='Microsoft 365 Apps'; Info=$officeCacheInfo },
        @{ Id='MicrosoftCompanyPortal'; DisplayName='Microsoft Company Portal'; Info=$companyPortalInfo },
        @{ Id='CMTraceOpen'; DisplayName='CMTrace Open'; Info=$cmTraceInfo },
        @{ Id='MicrosoftTeams'; DisplayName='Microsoft Teams'; Info=$microsoftTeamsCacheInfo },
        @{ Id='AdobeAcrobatUnified'; DisplayName='Adobe Acrobat Unified'; Info=$adobeCacheInfo },
        @{ Id='GoogleChromeEnterprise'; DisplayName='Google Chrome Enterprise'; Info=$chromeCacheInfo },
        @{ Id='CiscoWebex'; DisplayName='Cisco Webex'; Info=$webexCacheInfo },
        @{ Id='VisualCRedist'; DisplayName='Visual C++ v14 Redistributable'; Info=$visualCCacheInfo },
        @{ Id='DotNetRuntime'; DisplayName='.NET Runtime'; Info=$dotNetCacheInfo },
        @{ Id='VisualStudioCode'; DisplayName='Visual Studio Code'; Info=$visualStudioCodeCacheInfo },
        @{ Id='7Zip'; DisplayName='7Zip'; Info=$sevenZipCacheInfo },
        @{ Id='ZoomWorkplace'; DisplayName='Zoom Workplace'; Info=$zoomCacheInfo },
        @{ Id='MozillaFirefoxEnterprise'; DisplayName='Mozilla Firefox Enterprise'; Info=$firefoxCacheInfo }
    )) {
        $apps.Add([pscustomobject]@{
            PSTypeName    = 'OSDApps.App'
            Id            = $builtIn.Id
            Name          = $builtIn.Id
            DisplayName   = $builtIn.DisplayName
            Source        = 'BuiltIn'
            PackageType   = if ($builtIn.PackageType) { $builtIn.PackageType } else { 'App' }
            OnlineVersion = if ($builtIn.Version) { $builtIn.Version } else { 'Current' }
            CachedVersion = if ($builtIn.Info) { $builtIn.Info.Version } else { $null }
            Version       = if ($builtIn.Info) { $builtIn.Info.Version } elseif ($builtIn.Version) { $builtIn.Version } else { 'Current' }
            Architecture  = if ($builtIn.Info -and $builtIn.Info.Architecture) { $builtIn.Info.Architecture } elseif ($builtIn.Architecture) { $builtIn.Architecture } else { 'Auto' }
            Availability  = if ($builtIn.Info) { 'Cached' } else { 'Available' }
            Valid         = $true
        })
    }

    $result = @(
        $apps | Where-Object {
            ($_.Source -eq 'BuiltIn' -and $configuration.EnableBuiltIns) -or
            ($_.Source -eq 'Repository' -and $configuration.EnableRepository)
        }
    )

    if ($Name) {
        $result = @(
            $result | Where-Object {
                $app = $_
                @($Name | Where-Object {
                    $filter = $_
                    $app.Id -like $filter -or
                    $app.DisplayName -like $filter -or
                    @($app.Aliases | Where-Object { $_ -like $filter }).Count -gt 0
                }).Count -gt 0
            }
        )
    }

    $result
}
