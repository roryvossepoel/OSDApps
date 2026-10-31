function Get-OSDStageManifest {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$Uri
    )

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        # Read the bytes ourselves: Invoke-RestMethod can return BOM-prefixed
        # JSON as a string instead of deserializing it, even for application/json.
        $response = Invoke-WebRequest -Uri $Uri -Method Get -UseBasicParsing -ErrorAction Stop
        $stream = $response.RawContentStream
        if ($stream.CanSeek) { $stream.Position = 0 }
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true)
        try {
            $json = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        try {
            $manifest = ConvertFrom-Json -InputObject $json -ErrorAction Stop
        }
        catch {
            throw 'Repository manifest response is not valid JSON.'
        }
        if (-not $json.TrimStart().StartsWith('{')) {
            throw 'Repository manifest response must contain a JSON object.'
        }
        return $manifest
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
