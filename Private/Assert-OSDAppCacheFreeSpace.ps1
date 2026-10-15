function Assert-OSDAppCacheFreeSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB,

        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$LogPath,

        [string]$ExistingPath
    )

    $space = Assert-OSDAppTransactionSpace -Path $CachePath -ExistingPath $ExistingPath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation $Operation
    $driveLetter = [System.IO.Path]::GetPathRoot($CachePath).TrimEnd('\').TrimEnd(':')
    $freeGB = [math]::Round($space.AvailableBytes / 1GB, 2)

    if ($LogPath) {
        Write-OSDAppLog -LogPath $LogPath -Component 'Cache' -Event 'FreeSpaceCheck' -Message 'Checked free space on the OSDCloud cache volume.' -Data @{
            Operation          = $Operation
            DriveLetter        = $driveLetter
            FreeSpaceGB        = $freeGB
            MinimumFreeSpaceGB = $MinimumFreeSpaceGB
            RequiredBytes = $space.RequiredBytes
            Basis = $space.Basis
        }
    }

    [pscustomobject]@{
        DriveLetter        = $driveLetter
        FreeSpaceGB        = $freeGB
        MinimumFreeSpaceGB = $MinimumFreeSpaceGB
        Sufficient         = $true
    }
}
