function Read-OSDAppWiFiProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { throw 'Wi-Fi profile file does not exist.' }
    if ((Get-Item -LiteralPath $LiteralPath).Length -gt 1MB) { throw 'Wi-Fi profile exceeds the 1 MB limit.' }
    $reader=$null
    try {
        $settings=[System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null
        $settings.MaxCharactersInDocument=1MB
        $reader=[System.Xml.XmlReader]::Create((Get-Item -LiteralPath $LiteralPath).FullName,$settings)
        $doc=[System.Xml.XmlDocument]::new()
        $doc.XmlResolver=$null
        $doc.Load($reader)
    }
    catch { throw 'Wi-Fi profile XML could not be read. Check the local file; its contents are not logged.' }
    finally { if($reader){$reader.Dispose()} }
    $ns=[System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace('w','http://www.microsoft.com/networking/WLAN/profile/v1')
    $root=$doc.SelectSingleNode('/w:WLANProfile',$ns)
    if(-not $root){throw 'Expected a Windows WLANProfile XML export.'}
    $name=$root.SelectSingleNode('w:name',$ns)
    if(-not $name -or [string]::IsNullOrWhiteSpace($name.InnerText) -or $name.InnerText.Length -gt 255 -or $name.InnerText -match '[\x00-\x1F]') { throw 'Wi-Fi profile has no valid profile name.' }
    $auth=$root.SelectSingleNode('w:MSM/w:security/w:authEncryption/w:authentication',$ns)
    $oneX=$root.SelectSingleNode('w:MSM/w:security/w:authEncryption/w:useOneX',$ns)
    $encryption=$root.SelectSingleNode('w:MSM/w:security/w:authEncryption/w:encryption',$ns)
    if(-not $auth -or $auth.InnerText -notin @('WPA2PSK','WPA3SAE','open') -or ($oneX -and $oneX.InnerText -ne 'false')) {
        throw 'This version accepts WPA2-Personal, WPA3-Personal or open Wi-Fi profiles only. Enterprise credentials are not staged.'
    }
    $key=$root.SelectSingleNode('w:MSM/w:security/w:sharedKey',$ns)
    if($auth.InnerText -eq 'open') {
        if(-not $encryption -or $encryption.InnerText -ne 'none' -or $key){throw 'Only unencrypted open Wi-Fi is supported; WEP is not supported.'}
    }
    else {
        $protected=if($key){$key.SelectSingleNode('w:protected',$ns)}else{$null}
        $material=if($key){$key.SelectSingleNode('w:keyMaterial',$ns)}else{$null}
        if(-not $protected -or $protected.InnerText -ne 'false' -or -not $material -or [string]::IsNullOrEmpty($material.InnerText)) {
            throw 'Export the Wi-Fi profile with key=clear on the preparation PC. Machine-protected keys cannot be transferred.'
        }
    }
    [pscustomobject]@{Name=$name.InnerText;Xml=$doc.OuterXml}
}

function Protect-OSDAppWiFiDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    # Fixed SIDs work across languages and across the WinPE/offline Windows boundary.
    $acl=[System.Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity=[System.Security.Principal.SecurityIdentifier]::new($sid)
        $rule=[System.Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $LiteralPath -AclObject $acl -ErrorAction Stop
}
