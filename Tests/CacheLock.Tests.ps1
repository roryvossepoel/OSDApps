Describe 'Exclusive cache writers' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'blocks every public synchronization and cleanup before touching a busy cache' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'BusyCache'
            $lock = Enter-OSDAppCacheLock -CachePath $cache -Operation 'first writer'
            $catalog = Join-Path $cache 'CacheCatalog.json'
            Set-Content -LiteralPath $catalog -Value 'must not even parse this while busy'
            $hash = (Get-FileHash -LiteralPath $catalog).Hash
            Mock Get-OSDAppCachePath { $cache }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppHostArchitecture { 'x64' }
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri='https://example.invalid/catalog.json'} }
            Mock Get-OSDAppCatalogPackages { [pscustomobject]@{SchemaVersion=1; GeneratedAt='test'; Packages=@()} }
            Mock Get-OSDAppRemoteFileMetadata { throw 'must not contact vendor while busy' }
            try {
                foreach ($command in @('Sync-OSDAppMicrosoft365Apps','Sync-OSDAppMicrosoftTeams','Sync-OSDAppAdobeAcrobatUnified','Sync-OSDAppGoogleChromeEnterprise','Sync-OSDAppMozillaFirefoxEnterprise','Sync-OSDAppCiscoWebex','Sync-OSDAppRepository','Clear-OSDAppCache')) {
                    { & $command -Confirm:$false } | Should -Throw '*Cannot acquire the OSDApps cache lock*'
                }
                (Get-FileHash -LiteralPath $catalog).Hash | Should -Be $hash
                @(Get-ChildItem -LiteralPath $cache -Directory -Force).Count | Should -Be 0
                Should -Invoke Get-OSDAppRemoteFileMetadata -Exactly -Times 0
            }
            finally { $lock.Dispose() }
        }
    }

    It 'releases a public writer lock after a synchronization exception' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'FailedWriter'
            Mock Get-OSDAppCachePath { $cache }
            Mock Test-OSDAppWinPE { $false }
            Mock Sync-OSDAppVendorBuiltInCache { throw 'simulated vendor failure' }
            { Sync-OSDAppGoogleChromeEnterprise -Confirm:$false } | Should -Throw '*simulated vendor failure*'
            $next = Enter-OSDAppCacheLock -CachePath $cache -Operation 'next writer'
            $next.Dispose()
            (Get-Item -LiteralPath (Join-Path $cache '.osdapps-cache.lock') -Force).Length | Should -Be 0
        }
    }

    It 'keeps the lock file through Clear All and allows the next operation' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'ClearCache'
            New-Item -ItemType Directory -Path (Join-Path $cache 'BuiltIn'),(Join-Path $cache 'Packages') -Force | Out-Null
            Mock Get-OSDAppCachePath { $cache }
            Clear-OSDAppCache -All -IncludeLogs -Confirm:$false | Out-Null
            Test-Path -LiteralPath (Join-Path $cache 'BuiltIn') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cache 'Packages') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $cache '.osdapps-cache.lock') | Should -BeTrue
            $next = Enter-OSDAppCacheLock -CachePath $cache -Operation 'next writer'
            $next.Dispose()
        }
    }

    It 'does not create a cache or lock file for WhatIf' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'PreviewOnly'
            Mock Get-OSDAppCachePath { $cache }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri='https://example.invalid/catalog.json'} }
            Mock Enter-OSDAppCacheLock { throw 'preview must not lock' }
            foreach ($command in @('Sync-OSDAppMicrosoft365Apps','Sync-OSDAppMicrosoftTeams','Sync-OSDAppAdobeAcrobatUnified','Sync-OSDAppGoogleChromeEnterprise','Sync-OSDAppMozillaFirefoxEnterprise','Sync-OSDAppCiscoWebex','Sync-OSDAppRepository','Clear-OSDAppCache')) {
                & $command -WhatIf | Out-Null
            }
            Should -Invoke Enter-OSDAppCacheLock -Exactly -Times 0
            Test-Path -LiteralPath $cache | Should -BeFalse
        }
    }

    It 'does not treat a busy repository as a network error with offline fallback' {
        InModuleScope OSDApps {
            Mock Get-OSDAppCachePath { $TestDrive }
            Mock Resolve-OSDAppWindowsPath { $TestDrive }
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri='https://example.invalid/catalog.json'} }
            Mock Sync-OSDAppCache {
                $e = [InvalidOperationException]::new('busy cache fixture')
                $e.Data['OSDAppsCacheLockFailure'] = $true
                throw $e
            }
            Mock Copy-OSDAppContent { throw 'must not copy a busy cache' }
            Mock Test-OSDAppRepositoryCache { throw 'must not inspect a busy cache as fallback' }
            { Add-OSDApp -Name Example -WindowsPath $TestDrive -Confirm:$false } | Should -Throw '*busy cache fixture*'
            Should -Invoke Copy-OSDAppContent -Exactly -Times 0
            Should -Invoke Test-OSDAppRepositoryCache -Exactly -Times 0
        }
    }

    It 'stages the exact lock helper for standalone PreInstall' {
        InModuleScope OSDApps {
            Add-OSDAppSetupComplete -WindowsPath $TestDrive -Confirm:$false | Out-Null
            $source = Join-Path (Split-Path (Get-Module OSDApps).Path -Parent) 'Runtime\Enter-OSDAppCacheLock.ps1'
            $staged = Join-Path $TestDrive 'Windows\Temp\OSDApps\Enter-OSDAppCacheLock.ps1'
            (Get-FileHash -LiteralPath $staged).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        }
    }
}

Describe 'Cache lock across real processes' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $helper = Join-Path $moduleRoot 'Runtime\Enter-OSDAppCacheLock.ps1'
        . $helper
        $engine = (Get-Process -Id $PID).Path
    }

    It 'stops standalone PreInstall before acquisition when the <CacheMode> cache is busy' -ForEach @(
        @{CacheMode='USB'}, @{CacheMode='local'}
    ) {
        $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $stage = Join-Path $work 'Stage'
        $usb = Join-Path $work 'Usb'
        New-Item -ItemType Directory -Path $stage,$usb -Force | Out-Null
        $cache = if ($CacheMode -eq 'USB') { Join-Path $usb 'OSDApps' } else { $stage }
        $resultPath = Join-Path $work 'Results/Latest.json'
        @{DeploymentId='lock-test'; Runtime=@{CacheVolumeLabel='LockTest'; LogPath=(Join-Path $work 'Runtime.log'); ResultPath=$resultPath}; Apps=@(@{Id='GoogleChromeEnterprise';Source='BuiltIn'})} |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json')
        $wrapper = Join-Path $work 'preinstall.ps1'
        $runtime = (Join-Path $moduleRoot 'Runtime/Invoke-OSDAppPreInstall.ps1').Replace("'", "''")
        $escapedStage = $stage.Replace("'", "''")
        $volumeSetup = if ($CacheMode -eq 'USB') {
            "New-PSDrive -Name OSDLockCache -PSProvider FileSystem -Root '$($usb.Replace("'", "''"))' | Out-Null`nfunction global:Get-Volume { [CmdletBinding()]param(); [pscustomobject]@{FileSystemLabel='LockTest';DriveLetter='OSDLockCache'} }"
        }
        else { 'function global:Get-Volume { [CmdletBinding()]param() }' }
        @"
`$ErrorActionPreference = 'Stop'
$volumeSetup
& '$runtime' -StagedPath '$escapedStage'
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $wrapper -Encoding UTF8
        $handle = Enter-OSDAppCacheLock -CachePath $cache -Operation 'existing writer'
        $child = $null
        try {
            $child = Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $wrapper)) -PassThru
            $child.WaitForExit(15000) | Should -BeTrue
            $child.ExitCode | Should -Be 1
            $result = Get-Content -LiteralPath (Join-Path (Split-Path $resultPath -Parent) 'PreInstall.json') -Raw | ConvertFrom-Json
            $result.Status | Should -Be 'Failed'
            $result.FailureType | Should -Be 'CacheLockUnavailable'
            $result.Error | Should -BeLike '*Cannot acquire the OSDApps cache lock*'
            @(Get-ChildItem -LiteralPath $cache -Directory -Force).Count | Should -Be 0
        }
        finally {
            if ($child) {
                if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue }
                $child.Dispose()
            }
            $handle.Dispose()
        }
    }

    It 'blocks a competing process and releases automatically after <ExitMode>' -ForEach @(
        @{ExitMode='normal exit'}, @{ExitMode='forced termination'}
    ) {
        $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work | Out-Null
        $cache = Join-Path $work 'Cache with spaces'
        $ready = Join-Path $work 'ready.txt'
        $release = Join-Path $work 'release.txt'
        $scriptPath = Join-Path $work 'holder.ps1'
        $escapedHelper = $helper.Replace("'", "''")
        $escapedCache = $cache.Replace("'", "''")
        $escapedReady = $ready.Replace("'", "''")
        $escapedRelease = $release.Replace("'", "''")
        @"
`$ErrorActionPreference = 'Stop'
. '$escapedHelper'
`$handle = Enter-OSDAppCacheLock -CachePath '$escapedCache' -Operation 'child writer'
try {
    [IO.File]::WriteAllText('$escapedReady', 'ready')
    `$deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath '$escapedRelease')) {
        if ([DateTime]::UtcNow -gt `$deadline) { throw 'Parent test did not release the child.' }
        Start-Sleep -Milliseconds 50
    }
}
finally { `$handle.Dispose() }
"@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8
        $child = Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $scriptPath)) -PassThru
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $ready)) {
                if ($child.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Child did not acquire its cache lock.' }
                Start-Sleep -Milliseconds 50
            }
            { Enter-OSDAppCacheLock -CachePath $cache -Operation 'competing parent' } | Should -Throw '*Cannot acquire the OSDApps cache lock*'
            # A different cache remains usable while this one is locked.
            $other = Enter-OSDAppCacheLock -CachePath (Join-Path $work 'OtherCache') -Operation 'independent cache'
            $other.Dispose()
            if ($ExitMode -eq 'forced termination') { Stop-Process -Id $child.Id -Force }
            else { Set-Content -LiteralPath $release -Value 'release' }
            $child.WaitForExit(10000) | Should -BeTrue
            $next = Enter-OSDAppCacheLock -CachePath $cache -Operation 'writer after child exit'
            $next.Dispose()
            Test-Path -LiteralPath (Join-Path $cache '.osdapps-cache.lock') | Should -BeTrue
        }
        finally {
            if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue }
            $child.Dispose()
        }
    }
}
