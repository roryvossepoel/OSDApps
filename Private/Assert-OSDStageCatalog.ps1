function Assert-OSDStageCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog)

    if ([string]$Catalog.SchemaVersion -ne '2' -or
        $Catalog.PSObject.Properties.Name -notcontains 'Packages' -or
        $Catalog.Packages -isnot [array]) {
        throw 'Invalid OSDStage catalog. Expected SchemaVersion 2 and a Packages array.'
    }
    foreach ($entry in $Catalog.Packages) {
        if ($entry.PSObject.Properties.Name -notcontains 'Architectures' -or
            $entry.Architectures -isnot [array] -or $entry.Architectures.Count -eq 0) {
            throw "Catalog package '$($entry.Id)' must contain a non-empty Architectures array."
        }
    }
}
