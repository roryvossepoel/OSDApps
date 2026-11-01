function Get-OSDStageCachePath {
    [CmdletBinding()]
    param()

    $label = (Get-OSDStageConfiguration).CacheVolumeLabel

    $volumes = @(
        Get-Volume -ErrorAction Stop |
            Where-Object {
                $_.FileSystemLabel -eq $label -and
                $_.DriveLetter
            }
    )

    if ($volumes.Count -eq 0) {
        throw "No volume with label '$label' was found."
    }

    if ($volumes.Count -gt 1) {
        throw "Multiple volumes with label '$label' were found."
    }

    return "$($volumes[0].DriveLetter):\OSDStage"
}
