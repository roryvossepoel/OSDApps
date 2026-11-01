function Resolve-OSDStageCachedPackageId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string[]]$Name
    )

    $catalogPath = Join-Path $CachePath 'CacheCatalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        return @($Name)
    }

    $catalog = Get-OSDStageManifest -Path $catalogPath
    if (-not ($catalog.PSObject.Properties.Name -contains 'Packages')) {
        throw "Cache catalog '$catalogPath' is missing Packages."
    }

    $resolved = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($requestedName in $Name) {
        $owners = @(
            $catalog.Packages |
                Where-Object {
                    $_.Id -ieq $requestedName -or
                    @($_.Aliases | Where-Object { $_ -ieq $requestedName }).Count -gt 0
                } |
                Select-Object -ExpandProperty Id -Unique
        )
        if ($owners.Count -gt 1) {
            throw "Cache catalog identity '$requestedName' is ambiguous: $($owners -join ', ')."
        }
        $resolvedName = if ($owners.Count -eq 1) { [string]$owners[0] } else { [string]$requestedName }
        if ($seen.Add($resolvedName)) {
            $resolved.Add($resolvedName)
        }
    }

    @($resolved)
}
