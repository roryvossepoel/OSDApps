function Remove-OSDAppStaleOfficeCacheVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OfficeRoot,
        [Parameter(Mandatory)][string]$ActiveVersion
    )

    $dataPath = Join-Path $OfficeRoot 'Office\Data'
    $activePath = Join-Path $dataPath $ActiveVersion
    if (-not (Test-Path -LiteralPath $activePath -PathType Container)) {
        throw "Active Office cache version folder is missing: $activePath"
    }
    if (@(Get-ChildItem -LiteralPath $activePath -File -Recurse -ErrorAction Stop).Count -eq 0) {
        throw "Active Office cache version folder contains no files: $activePath"
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in @(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction Stop)) {
        if ($directory.Name -eq $ActiveVersion -or $directory.Name -notmatch '^\d+\.\d+\.\d+\.\d+$') {
            continue
        }

        $quarantinePath = Join-Path $dataPath ('.osdapps-prune-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $directory.FullName -Destination $quarantinePath -ErrorAction Stop
        try {
            Remove-Item -LiteralPath $quarantinePath -Recurse -Force -ErrorAction Stop
            $removed.Add($directory.Name)
        }
        catch {
            if (Test-Path -LiteralPath $quarantinePath -PathType Container) {
                Move-Item -LiteralPath $quarantinePath -Destination $directory.FullName -ErrorAction SilentlyContinue
            }
            throw
        }
    }

    foreach ($cab in @(Get-ChildItem -LiteralPath $dataPath -File -ErrorAction Stop)) {
        if ($cab.Name -notmatch '^v(?:32|64)_(\d+\.\d+\.\d+\.\d+)\.cab$') {
            continue
        }
        $cabVersion = $Matches[1]
        if ($cabVersion -eq $ActiveVersion) {
            continue
        }

        $quarantinePath = Join-Path $dataPath ('.osdapps-prune-' + [guid]::NewGuid().ToString('N') + '.cab')
        Move-Item -LiteralPath $cab.FullName -Destination $quarantinePath -ErrorAction Stop
        try {
            Remove-Item -LiteralPath $quarantinePath -Force -ErrorAction Stop
            if (-not $removed.Contains($cabVersion)) { $removed.Add($cabVersion) }
        }
        catch {
            if (Test-Path -LiteralPath $quarantinePath -PathType Leaf) {
                Move-Item -LiteralPath $quarantinePath -Destination $cab.FullName -ErrorAction SilentlyContinue
            }
            throw
        }
    }

    @($removed)
}
