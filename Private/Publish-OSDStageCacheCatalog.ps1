function Publish-OSDStageCacheCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    # One explicit commit boundary for a fully prepared cache transaction.
    # Kept separate from package moves to allow deterministic failure injection
    # without mocking the platform Move-Item cmdlet (and breaking rollback).
    Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
}
