function Enter-OSDStageCacheLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][string]$Operation
    )

    # Keep the empty file after release. Deleting/recreating a lock file can
    # let two processes lock different file objects at the same logical path.
    # The live exclusive handle, not file existence or a PID, owns the lock.
    try {
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CachePath)
        [IO.Directory]::CreateDirectory($resolved) | Out-Null
        $lockPath = Join-Path $resolved '.osdstage-cache.lock'
        return [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        $failure = [InvalidOperationException]::new(
            "Cannot acquire the OSDStage cache lock for '$CachePath' before $Operation. The cache may already be in use, or the lock file is inaccessible. No cache operation was started. $($_.Exception.Message)",
            $_.Exception
        )
        $failure.Data['OSDStageCacheLockFailure'] = $true
        throw $failure
    }
}
