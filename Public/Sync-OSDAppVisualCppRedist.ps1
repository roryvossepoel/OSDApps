function Sync-OSDAppVisualCppRedist {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDAppWinPE) { throw 'Use Add-OSDAppVisualCppRedist in WinPE; synchronization requires full Windows.' }
    $cachePath = Get-OSDAppCachePath
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDAppPrerequisiteSpec -Family VisualCppRedist -Architecture $arch
        $root = Join-Path $cachePath $spec.RelativeRoot
        if (-not $PSCmdlet.ShouldProcess($root, 'Synchronize verified runtime cache')) { continue }
        $lock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'Runtime cache synchronization'
        try {
            $sync = Sync-OSDAppPrerequisiteGeneration -Root $root -Spec $spec -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Download {
                param($uri,$destination)
                Save-OSDAppDownload -Uri $uri -DestinationPath $destination -Activity 'Downloading Microsoft runtime'
            }
            [pscustomobject]@{ PSTypeName='OSDApps.BuiltInCache'; Id=$spec.Id; Version=$sync.Version; Architecture=$arch; CachePath=$root; Cached=$true; Updated=$sync.Updated }
        } finally { $lock.Dispose() }
    }
}
