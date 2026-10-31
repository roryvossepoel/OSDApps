function Save-OSDStageVerifiedBuiltInDownload {
    [CmdletBinding(DefaultParameterSetName='Exact')]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory,ParameterSetName='Exact')][string]$DestinationPath,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$DestinationDirectory,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$ExpectedExtension,
        [Parameter(Mandatory)][string]$Activity,
        [int]$ProgressId = 20,
        [int]$ParentProgressId = -1
    )
    if (Test-OSDStageWinPE) { throw 'Signed built-in cache synchronization requires full Windows.' }
    $directory = if ($PSCmdlet.ParameterSetName -eq 'Vendor') { $DestinationDirectory } else { Split-Path -Path $DestinationPath -Parent }
    $token = [guid]::NewGuid().ToString('N')
    $candidateDirectory = Join-Path $directory ('.osdstage-download-' + $token)
    $backup = Join-Path $directory ('.osdstage-previous-' + $token)
    New-Item -ItemType Directory -Path $candidateDirectory -Force -ErrorAction Stop | Out-Null
    $hadPrevious = $false
    $promoted = $false
    try {
        $parameters = @{ Uri=$Uri; Activity=$Activity; ProgressId=$ProgressId; ParentProgressId=$ParentProgressId }
        if ($PSCmdlet.ParameterSetName -eq 'Vendor') {
            $parameters.DestinationDirectory = $candidateDirectory
            $parameters.ExpectedExtension = $ExpectedExtension
        }
        else {
            $parameters.DestinationPath = Join-Path $candidateDirectory (Split-Path -Path $DestinationPath -Leaf)
        }
        $downloaded = Save-OSDStageDownload @parameters
        if (-not $downloaded -or -not $downloaded.FullName) { throw 'Download did not return its exact vendor payload path.' }
        $candidate = Resolve-OSDStageBuiltInPayloadPath -Path ([string]$downloaded.FullName)
        $DestinationPath = Join-Path $directory (Split-Path -Path $candidate -Leaf)
        Assert-OSDStageBuiltInSignature -Id $Id -FilePath $candidate | Out-Null
        $hadPrevious = Test-Path -LiteralPath $DestinationPath -PathType Leaf
        if ($hadPrevious) { Move-Item -LiteralPath $DestinationPath -Destination $backup -ErrorAction Stop }
        try {
            Move-Item -LiteralPath $candidate -Destination $DestinationPath -ErrorAction Stop
            $promoted = $true
        }
        catch {
            if ($hadPrevious -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
                Move-Item -LiteralPath $backup -Destination $DestinationPath -ErrorAction Stop
            }
            throw
        }
        [pscustomobject]@{
            Id=$Id; DestinationPath=$DestinationPath; FullName=$DestinationPath
            Name=(Split-Path -Path $DestinationPath -Leaf); SignatureVerified=$true
        }
    }
    finally {
        if (Test-Path -LiteralPath $candidateDirectory) { Remove-Item -LiteralPath $candidateDirectory -Recurse -Force -ErrorAction SilentlyContinue }
        if ($promoted -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
    }
}
