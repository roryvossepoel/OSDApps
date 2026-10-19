function New-OSDAppZoomWorkplaceMsiProperties {
    [CmdletBinding()]
    param(
        [switch]$NoDesktopShortcut,
        [string]$SsoHost,
        [hashtable]$ZConfig,
        [hashtable]$ZRecommend
    )

    $properties = [System.Collections.Generic.List[string]]::new()
    $properties.Add('ALLUSERS=1')
    if ($NoDesktopShortcut) { $properties.Add('zNoDesktopShortCut=True') }
    if ($SsoHost) {
        # Accept a vanity host, never an arbitrary command-line fragment or URL path.
        if ($SsoHost -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') {
            throw 'SsoHost must be a Zoom vanity host without a scheme, path, spaces or quotes.'
        }
        $properties.Add(('zSSOHost="{0}"' -f $SsoHost))
    }

    $deprecated = @('EnableSilentAutoUpdate','AlwaysCheckLatestVersion','ZoomAutoUpdate','SetUpdatingChannel')
    foreach ($group in @('ZConfig','ZRecommend')) {
        $settings = if ($group -eq 'ZConfig') { $ZConfig } else { $ZRecommend }
        if (-not $settings -or $settings.Count -eq 0) { continue }
        $pairs = [System.Collections.Generic.List[string]]::new()
        $seen = @{}
        foreach ($key in @($settings.Keys | Sort-Object)) {
            if ($key -isnot [string] -or $key -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
                throw "$group keys must be Zoom setting names containing letters, digits or underscores."
            }
            if ($seen.ContainsKey($key)) { throw "Duplicate Zoom setting '$key' in $group." }
            $seen[$key] = $true
            if ($key -in $deprecated) {
                throw "Zoom no longer supports '$key'; use documented Enterprise Auto Update policies."
            }
            $value = $settings[$key]
            if ($value -is [bool]) { $value = if ($value) { '1' } else { '0' } }
            elseif ($value -is [int] -or $value -is [long]) { $value = $value.ToString([Globalization.CultureInfo]::InvariantCulture) }
            elseif ($value -isnot [string]) { throw "Zoom setting '$key' must have a string, Boolean or integer value." }
            if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1F\x7F";]' -or $value.EndsWith('\')) {
                throw "Zoom setting '$key' contains an empty value, quote, separator, control character or trailing backslash."
            }
            $pairs.Add(('{0}={1}' -f $key, $value))
        }
        $properties.Add(('{0}="{1}"' -f $group, ($pairs -join ';')))
    }
    $properties.ToArray()
}
