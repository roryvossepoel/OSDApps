function New-OSDStageOfficeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$Channel = 'Current',
        [ValidateSet('x64','x86')][string]$Architecture = 'x64',
        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')][string]$ProductId = 'O365ProPlusRetail',
        [string[]]$Language = @('en-us'),
        [bool]$AcceptEula = $true,
        [bool]$UpdatesEnabled = $true,
        [bool]$SharedComputerLicensing = $false,
        [bool]$DeviceBasedLicensing = $false,
        [string[]]$ExcludeApp,
        [switch]$IncludeVisio,
        [switch]$IncludeProject
    )

    if ($SharedComputerLicensing -and $DeviceBasedLicensing) {
        throw 'SharedComputerLicensing and DeviceBasedLicensing cannot both be enabled.'
    }
    $languages = @($Language | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($languages.Count -eq 0) { throw 'At least one Office language must be specified.' }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('Configuration')
        $writer.WriteStartElement('Add')
        $writer.WriteAttributeString('OfficeClientEdition', $(if ($Architecture -eq 'x64') { '64' } else { '32' }))
        $writer.WriteAttributeString('Channel', $Channel)

        $products = @($ProductId)
        if ($IncludeVisio) { $products += 'VisioProRetail' }
        if ($IncludeProject) { $products += 'ProjectProRetail' }

        foreach ($product in $products) {
            $writer.WriteStartElement('Product')
            $writer.WriteAttributeString('ID', $product)
            foreach ($culture in $languages) {
                $writer.WriteStartElement('Language')
                $writer.WriteAttributeString('ID', $culture)
                $writer.WriteEndElement()
            }
            if ($product -eq $ProductId) {
                foreach ($app in @($ExcludeApp)) {
                    if ([string]::IsNullOrWhiteSpace($app)) { continue }
                    $writer.WriteStartElement('ExcludeApp')
                    $writer.WriteAttributeString('ID', $app)
                    $writer.WriteEndElement()
                }
            }
            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteStartElement('Display')
        $writer.WriteAttributeString('Level', 'None')
        $writer.WriteAttributeString('AcceptEULA', $(if ($AcceptEula) { 'TRUE' } else { 'FALSE' }))
        $writer.WriteEndElement()
        if ($SharedComputerLicensing) {
            $writer.WriteStartElement('Property')
            $writer.WriteAttributeString('Name', 'SharedComputerLicensing')
            $writer.WriteAttributeString('Value', '1')
            $writer.WriteEndElement()
        }
        if ($DeviceBasedLicensing) {
            $writer.WriteStartElement('Property')
            $writer.WriteAttributeString('Name', 'DeviceBasedLicensing')
            $writer.WriteAttributeString('Value', '1')
            $writer.WriteEndElement()
        }
        $writer.WriteStartElement('Updates')
        $writer.WriteAttributeString('Enabled', $(if ($UpdatesEnabled) { 'TRUE' } else { 'FALSE' }))
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally { $writer.Dispose() }
}
