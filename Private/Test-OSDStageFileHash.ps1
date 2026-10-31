function Test-OSDStageFileHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $actual.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)
}
