function New-OSDStageOfficeDownloadConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$DownloadRoot
    )

    [xml]$xml = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
    $add = $xml.Configuration.Add
    if (-not $add) { throw 'Office configuration does not contain an Add element.' }
    $add.SetAttribute('SourcePath', $DownloadRoot)

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.Xml.XmlWriter]::Create($DestinationPath, $settings)
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}
