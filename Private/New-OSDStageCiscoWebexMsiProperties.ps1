function New-OSDStageCiscoWebexMsiProperties {
    [CmdletBinding()]
    param(
        [bool]$AutoStartWithWindows = $false,
        [bool]$AcceptEula = $true,
        [bool]$PreventPreLoginUpdates = $false,
        [Nullable[bool]]$EnableOutlookIntegration,
        [ValidateSet('Light','Dark')][string]$DefaultTheme,
        [string]$EmailHint,
        [string[]]$AdditionalMsiProperties
    )

    $properties = [System.Collections.Generic.List[string]]::new()
    $properties.Add('ALLUSERS=1')
    if ($AcceptEula) {
        $properties.Add('ACCEPT_EULA=TRUE')
    }
    $autoStart = if ($AutoStartWithWindows) { 'TRUE' } else { 'FALSE' }
    $properties.Add("AUTOSTART_WITH_WINDOWS=$autoStart")
    if ($PreventPreLoginUpdates) {
        $properties.Add('PREVENT_PRELOGIN_UPDATES=1')
    }
    # Omission preserves Cisco's default; explicit false disables the Outlook UI control.
    if ($null -ne $EnableOutlookIntegration) {
        $outlook = if ($EnableOutlookIntegration) { '1' } else { '0' }
        $properties.Add("ENABLEOUTLOOKINTEGRATION=$outlook")
    }
    if ($DefaultTheme) {
        $properties.Add("DEFAULT_THEME=$DefaultTheme")
    }
    if ($EmailHint) {
        # ALLUSERS=1 must never bake an individual user's email into the machine.
        if ($EmailHint -notin @('$userPrincipalName','$mail','$SAMAccountName')) {
            throw 'EmailHint must be a Cisco sign-in placeholder: $userPrincipalName, $mail or $SAMAccountName. Fixed email addresses cannot be used with ALLUSERS=1.'
        }
        $properties.Add("EMAIL=$EmailHint")
    }

    $managed = @('ALLUSERS','ACCEPT_EULA','AUTOSTART_WITH_WINDOWS','PREVENT_PRELOGIN_UPDATES','ENABLEOUTLOOKINTEGRATION','DEFAULT_THEME','EMAIL')
    $seen = @{}
    foreach ($property in $AdditionalMsiProperties) {
        $match = [regex]::Match([string]$property, '^([A-Za-z_][A-Za-z0-9_]*)=(.+)$')
        if ([string]::IsNullOrWhiteSpace($property) -or -not $match.Success) {
            throw "AdditionalMsiProperties must contain non-empty NAME=VALUE pairs; invalid property: '$property'."
        }
        $name = $match.Groups[1].Value.ToUpperInvariant()
        $value = $match.Groups[2].Value
        if ($name -in $managed) {
            throw "Use the dedicated CiscoWebex parameter for reserved MSI property '$name'."
        }
        if ($seen.ContainsKey($name)) {
            throw "Duplicate CiscoWebex additional MSI property: '$name'."
        }
        if ($value -match '[\x00-\x1F"]' -or $value.Contains([char]39) -or $value.Contains([char]96)) {
            throw "Additional MSI property '$name' contains an unsupported quote or control character."
        }
        $seen[$name] = $true
        if ($value -match '\s') {
            $properties.Add(('{0}="{1}"' -f $name, $value))
        }
        else {
            $properties.Add(('{0}={1}' -f $name, $value))
        }
    }
    $properties.ToArray()
}
