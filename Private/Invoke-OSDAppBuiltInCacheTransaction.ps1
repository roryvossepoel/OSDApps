function Invoke-OSDAppBuiltInCacheTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$Build,
        [Parameter(Mandatory)][scriptblock]$Validate
    )

    $transactionRoot = "$Root.osdapps-new-$([guid]::NewGuid().ToString('N'))"
    $backupRoot = "$Root.osdapps-old-$([guid]::NewGuid().ToString('N'))"
    $hadPrevious = Test-Path -LiteralPath $Root -PathType Container
    $promoted = $false

    try {
        New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
        & $Build $transactionRoot
        & $Validate $transactionRoot | Out-Null

        if ($hadPrevious) {
            Move-Item -LiteralPath $Root -Destination $backupRoot -ErrorAction Stop
        }

        try {
            Move-Item -LiteralPath $transactionRoot -Destination $Root -ErrorAction Stop
            $promoted = $true
        }
        catch {
            if ($hadPrevious -and
                (Test-Path -LiteralPath $backupRoot -PathType Container) -and
                -not (Test-Path -LiteralPath $Root)) {
                Move-Item -LiteralPath $backupRoot -Destination $Root -ErrorAction Stop
            }
            throw
        }

        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction Stop
        }

        # The newly promoted generation has already passed the caller's full
        # validation gate. Residue from older interrupted transactions can now
        # be removed without risking the only usable generation.
        $parent = Split-Path -Path $Root -Parent
        $leaf = Split-Path -Path $Root -Leaf
        Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like "$leaf.osdapps-new-*" -or
                $_.Name -like "$leaf.osdapps-old-*"
            } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }

        [pscustomobject]@{
            Root          = $Root
            HadPrevious   = $hadPrevious
            Promoted      = $promoted
            Transactional = $true
        }
    }
    finally {
        if (Test-Path -LiteralPath $transactionRoot) {
            Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ((Test-Path -LiteralPath $backupRoot -PathType Container) -and
            -not (Test-Path -LiteralPath $Root)) {
            Move-Item -LiteralPath $backupRoot -Destination $Root -ErrorAction SilentlyContinue
        }
        if ($promoted -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
