function Get-OSDStageArchiveSpaceEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Archive,
        [Parameter(Mandatory)][string]$ExistingPath
    )

    if ($Archive.PSObject.Properties['Uri'] -and $Archive.Uri) {
        # Some repositories reject HEAD or omit Content-Length. A bounded
        # metadata probe must not make an otherwise usable repository fail.
        try {
            $response = Invoke-WebRequest -Uri $Archive.Uri -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $length = 0L
            if ([long]::TryParse([string]$response.Headers['Content-Length'], [ref]$length) -and $length -gt 0) {
                return [double]$length
            }
        }
        catch { Write-Verbose "Archive length unavailable: $($_.Exception.Message)" }
        # No extraction occurs in the repository cache: candidates contain
        # Package.zip only. Unknown sizes use at least 1 GB per changed package.
        return [math]::Max([double]1GB, [double](Get-OSDStagePathSize -Path $ExistingPath))
    }
    if ($Archive.PSObject.Properties['SourcePath'] -and $Archive.SourcePath) {
        return [double](Get-Item -LiteralPath $Archive.SourcePath -ErrorAction Stop).Length
    }
    throw 'Package archive has neither Uri nor SourcePath.'
}
