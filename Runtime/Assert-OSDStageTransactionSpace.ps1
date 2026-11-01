function Get-OSDStagePathSize {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    [double]$bytes = 0
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop |
            ForEach-Object { $bytes += $_.Length }
    }
    return $bytes
}

function Get-OSDStageAvailableDiskBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    # Resolve PowerShell drives without requiring the destination to exist.
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $root = [IO.Path]::GetPathRoot($resolved)
    if (-not $root -or $root.StartsWith('\\')) {
        throw "Cannot determine local cache volume free space for '$Path'."
    }
    $drive = [IO.DriveInfo]::new($root)
    if (-not $drive.IsReady) { throw "Cache volume '$root' is not ready." }
    return [double]$drive.AvailableFreeSpace
}

function Assert-OSDStageTransactionSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Operation,
        [ValidateRange(0, [double]::MaxValue)][double]$ExpectedBytes = 0,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 0,
        [string]$ExistingPath
    )

    # The old generation is already included in used disk space. Renaming it
    # to a sibling backup consumes no second payload copy. Reserve only the
    # candidate, 20% growth allowance and 64 MB for metadata/working overhead.
    # Without a remote length, the old generation is an estimate, not a bound.
    $basis = 'RemoteOrSourceLength'
    if ($ExpectedBytes -le 0) {
        $basis = 'MinimumFreeSpace'
        if ($ExistingPath) {
            $ExpectedBytes = Get-OSDStagePathSize -Path $ExistingPath
            if ($ExpectedBytes -gt 0) { $basis = 'ExistingGenerationEstimate' }
        }
    }
    $required = [math]::Max(($MinimumFreeSpaceGB * 1GB), ([math]::Ceiling($ExpectedBytes * 1.2) + 64MB))
    $available = Get-OSDStageAvailableDiskBytes -Path $Path
    if ($available -lt $required) {
        throw ('Insufficient free space before {0}: path={1}; available={2:N2} GB; required={3:N2} GB; basis={4}. Existing cache content has not been replaced.' -f $Operation, $Path, ($available / 1GB), ($required / 1GB), $basis)
    }
    [pscustomobject]@{
        Path = $Path
        AvailableBytes = $available
        RequiredBytes = $required
        Basis = $basis
    }
}
