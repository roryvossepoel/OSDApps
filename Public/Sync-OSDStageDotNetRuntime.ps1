function Sync-OSDStageDotNetRuntime {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateSet('8.0','9.0','10.0')][string]$Channel = '10.0',
        [ValidateSet('Runtime','Desktop')][string]$RuntimeType = 'Desktop',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDStageWinPE) { throw 'Use Add-OSDStageDotNetRuntime in WinPE; synchronization requires full Windows.' }
    $cachePath = Get-OSDStageCachePath
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDStagePrerequisiteSpec -Family DotNetRuntime -Architecture $arch -Channel $Channel -RuntimeType $RuntimeType
        $root = Join-Path $cachePath $spec.RelativeRoot
        if (-not $PSCmdlet.ShouldProcess($root, 'Synchronize verified runtime cache')) { continue }
        $lock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'Runtime cache synchronization'
        try {
            $sync = Sync-OSDStagePrerequisiteGeneration -Root $root -Spec $spec -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Download {
                param($uri,$destination)
                Save-OSDStageDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Activity 'Downloading Microsoft runtime'
            }
            [pscustomobject]@{ PSTypeName='OSDStage.BuiltInCache'; Id=$spec.Id; Version=$sync.Version; Architecture=$arch; CachePath=$root; Cached=$true; Updated=$sync.Updated }
        } finally { $lock.Dispose() }
    }
}
