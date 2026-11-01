function Resolve-OSDStageWindowsPath {
    [CmdletBinding()]
    param(
        [string]$WindowsPath
    )

    if ($WindowsPath) {
        $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "WindowsPath does not exist or is not a directory: $resolved"
        }
        return $resolved
    }

    $candidates = @(
        Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'X' } |
            ForEach-Object {
                $root = "$($_.DriveLetter):\"
                $systemHive = Join-Path $root 'Windows\System32\Config\SYSTEM'
                if (Test-Path -LiteralPath $systemHive -PathType Leaf) { $root }
            }
    )

    if ($candidates.Count -eq 0) { throw 'No offline Windows installation was found.' }
    if ($candidates.Count -gt 1) { throw "Multiple Windows installations were found: $($candidates -join ', ')." }
    return $candidates[0]
}