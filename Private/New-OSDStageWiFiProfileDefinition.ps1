function New-OSDStageWiFiProfileDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SSID,
        [Parameter(Mandatory)][ValidateSet('WPA2Personal','WPA3Personal','Open')][string]$Security,
        [object]$Password,
        [string]$ProfileName,
        [ValidateSet('Auto','Manual')][string]$ConnectionMode='Auto',
        [switch]$Hidden
    )

    $utf8=[System.Text.UTF8Encoding]::new($false,$true)
    try {$ssidBytes=$utf8.GetBytes($SSID)}
    catch {throw 'SSID must contain valid Unicode text.'}
    if([string]::IsNullOrWhiteSpace($SSID) -or $ssidBytes.Length -gt 32 -or $SSID -match '[\x00-\x1F]') {
        throw 'SSID must contain 1 to 32 UTF-8 bytes and no control characters.'
    }
    if(-not $PSBoundParameters.ContainsKey('ProfileName')){$ProfileName=$SSID}
    if([string]::IsNullOrWhiteSpace($ProfileName) -or $ProfileName.Length -gt 255 -or $ProfileName -match '[\x00-\x1F]') {
        throw 'ProfileName must contain 1 to 255 characters and no control characters.'
    }
    try {[System.Xml.XmlConvert]::VerifyXmlChars($ProfileName) | Out-Null}
    catch {throw 'ProfileName must contain valid XML text.'}

    $plain=$null
    $writer=$null
    $pointer=[IntPtr]::Zero
    try {
        if($Security -eq 'Open') {
            if($PSBoundParameters.ContainsKey('Password')){throw 'Open networks do not accept Password.'}
        }
        else {
            if($Password -is [System.Security.SecureString]) {
                $pointer=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                $plain=[System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            }
            elseif($Password -is [string]){$plain=$Password}
            else {throw 'Personal networks require Password as a string or SecureString.'}
            # Validate here, rather than using validation attributes that echo rejected secrets.
            if($plain.Length -lt 8 -or $plain.Length -gt 63 -or $plain -match '[^\x20-\x7E]') {
                throw 'Password must contain 8 to 63 printable ASCII characters.'
            }
        }

        $authentication=switch($Security){'WPA2Personal'{'WPA2PSK'} 'WPA3Personal'{'WPA3SAE'} 'Open'{'open'}}
        $encryption=if($Security -eq 'Open'){'none'}else{'AES'}
        $ns='http://www.microsoft.com/networking/WLAN/profile/v1'
        $buffer=[System.Text.StringBuilder]::new()
        $settings=[System.Xml.XmlWriterSettings]::new()
        $settings.OmitXmlDeclaration=$true
        $writer=[System.Xml.XmlWriter]::Create($buffer,$settings)
        $writer.WriteStartElement('WLANProfile',$ns)
        $writer.WriteElementString('name',$ns,$ProfileName)
        $writer.WriteStartElement('SSIDConfig',$ns)
        $writer.WriteStartElement('SSID',$ns)
        $writer.WriteElementString('hex',$ns,([BitConverter]::ToString($ssidBytes).Replace('-','')))
        $writer.WriteElementString('name',$ns,$SSID)
        $writer.WriteEndElement()
        $writer.WriteElementString('nonBroadcast',$ns,([bool]$Hidden).ToString().ToLowerInvariant())
        $writer.WriteEndElement()
        $writer.WriteElementString('connectionType',$ns,'ESS')
        $writer.WriteElementString('connectionMode',$ns,$ConnectionMode.ToLowerInvariant())
        $writer.WriteStartElement('MSM',$ns)
        $writer.WriteStartElement('security',$ns)
        $writer.WriteStartElement('authEncryption',$ns)
        $writer.WriteElementString('authentication',$ns,$authentication)
        $writer.WriteElementString('encryption',$ns,$encryption)
        $writer.WriteElementString('useOneX',$ns,'false')
        $writer.WriteEndElement()
        if($Security -ne 'Open') {
            $writer.WriteStartElement('sharedKey',$ns)
            $writer.WriteElementString('keyType',$ns,'passPhrase')
            $writer.WriteElementString('protected',$ns,'false')
            $writer.WriteElementString('keyMaterial',$ns,$plain)
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.Flush()
        [pscustomobject]@{Name=$ProfileName;Xml=$buffer.ToString()}
    }
    finally {
        if($writer){$writer.Dispose()}
        if($pointer -ne [IntPtr]::Zero){[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
        $plain=$null
    }
}
