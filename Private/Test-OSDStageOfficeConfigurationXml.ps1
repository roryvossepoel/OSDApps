function Test-OSDStageOfficeConfigurationXml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Office configuration XML not found: $Path"
    }

    try {
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($Path, $settings)
        try {
            while ($reader.Read()) { }
        }
        finally {
            if ($reader) { $reader.Dispose() }
        }
    }
    catch {
        throw "Office configuration XML is not well-formed: $Path. $($_.Exception.Message)"
    }

    # Deliberately no ODT product, channel, locale or licensing validation.
    return $true
}
