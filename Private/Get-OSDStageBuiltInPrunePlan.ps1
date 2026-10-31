function Get-OSDStageBuiltInPrunePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CachePath)

    # Only direct children of BuiltIn are owned by this namespace cleanup.
    # Known app internals and transaction recovery belong to their app handlers.
    $metadataPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'metadata\builtins.json'
    $metadata = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $known = @{}
    foreach ($app in @($metadata.Packages)) {
        $id = [string]$app.Id
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $id -match '\.\.' -or $known.ContainsKey($id)) {
            throw 'Built-in metadata is invalid; no cache content was pruned.'
        }
        $known[$id] = $true
    }
    if ($known.Count -eq 0) { throw 'Built-in metadata is empty; no cache content was pruned.' }

    $root = Join-Path $CachePath 'BuiltIn'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($path in @($CachePath, $root)) {
        if (((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Cache pruning through a linked cache root is not supported.'
        }
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
        if ($known.ContainsKey($item.Name) -and $item.PSIsContainer) { continue }
        $reason = $null
        $pending = [System.Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
        $pending.Push($item)
        while ($pending.Count -gt 0 -and -not $reason) {
            $current = $pending.Pop()
            if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reason = 'Contains a filesystem link; manual review required.'
            }
            elseif ($current.Name -match '\.osdstage-' -or $current.Name -eq '.staging') {
                $reason = 'Contains transaction or recovery content; preserve for recovery or manual review.'
            }
            elseif ($current -is [System.IO.DirectoryInfo]) {
                foreach ($child in @(Get-ChildItem -LiteralPath $current.FullName -Force -ErrorAction Stop)) { $pending.Push($child) }
            }
        }
        [pscustomobject]@{
            Path = $item.FullName
            Name = $item.Name
            Action = if ($reason) { 'Review' } else { 'Remove' }
            Reason = if ($reason) { $reason } else { 'Not a managed built-in app directory.' }
        }
    }
}
