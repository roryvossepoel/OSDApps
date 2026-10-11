function Save-OSDAppVerifiedBuiltInDownload {
    <#
    .SYNOPSIS
    Downloads a signed built-in MSI/EXE into a separate candidate, validates
    signature and expected publisher before replacing a cached file.
    .NOTES
    The original file is preserved when download or validation fails.
    This does not apply to outer ZIP containers or downloaded MSIX payloads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$Activity,
        [int]$ProgressId = 20,
        [int]$ParentProgressId = -1
    )

    if (Test-OSDAppWinPE) {
        throw 'Signed built-in cache synchronization requires full Windows.'
    }
    $directory = Split-Path -Path $DestinationPath -Parent
    $basename = [IO.Path]::GetFileNameWithoutExtension($DestinationPath)
    $extension = [IO.Path]::GetExtension($DestinationPath)
    $token = [guid]::NewGuid().ToString('N')
    $candidate = Join-Path $directory ("$basename.$token.candidate$extension")
    $backup = Join-Path $directory ("$basename.$token.previous$extension")
    $hadPrevious = $false
    $promoted = $false

    try {
        Save-OSDAppDownload -Uri $Uri -DestinationPath $candidate -Activity $Activity -ProgressId $ProgressId -ParentProgressId $ParentProgressId | Out-Null
        Assert-OSDAppBuiltInSignature -Id $Id -FilePath $candidate | Out-Null

        $hadPrevious = Test-Path -LiteralPath $DestinationPath -PathType Leaf
        if ($hadPrevious) {
            Move-Item -LiteralPath $DestinationPath -Destination $backup -ErrorAction Stop
        }
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
            Id=$Id
            DestinationPath=$DestinationPath
            SignatureVerified=$true
        }
    }
    finally {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        }
        # Retain the backup after an incomplete promotion/rollback for recovery.
        if ($promoted -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        }
    }
}
