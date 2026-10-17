# Selection preview is window-local data. These helpers never invoke staging cmdlets.
function Get-OSDAppUISelectionKey {
    param([Parameter(Mandatory)]$Application)
    '{0}:{1}' -f $Application.Source,$Application.Id
}

function Get-OSDAppUIConfigurationFields {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $definition = @(Get-OSDAppUIBuiltInMetadata | Where-Object Id -eq $Id)
    if ($definition.Count -ne 1) { throw "Unknown built-in: $Id" }
    $command = Get-Command -Name $definition[0].AddCommand -Module OSDApps -CommandType Function -ErrorAction Stop
    # Read literal defaults from our own loaded cmdlet, never from a cached package.
    foreach ($parameter in $command.ScriptBlock.Ast.Body.ParamBlock.Parameters) {
        $name = $parameter.Name.VariablePath.UserPath
        if ($name -eq 'WindowsPath') { continue }
        $metadata = $command.Parameters[$name]
        $default = $null
        if ($parameter.DefaultValue) { $default = $parameter.DefaultValue.SafeGetValue() }
        elseif ($metadata.ParameterType -in @([bool],[switch])) { $default = $false }
        $sets = @($metadata.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
        $choices = @()
        if ($sets.Count) { $choices = @($sets[0].ValidValues) }
        $label = $name -creplace '([a-z])([A-Z])','$1 $2'
        if ($name -eq 'Language' -and $metadata.ParameterType -eq [string[]]) { $label = 'Languages (one per line)' }
        if ($name -eq 'ExcludeApp') { $label = 'Exclude apps (one per line)' }
        if ($name -eq 'AdditionalMsiProperties') { $label = 'Additional MSI properties (one per line)' }
        if ($name -eq 'ConfigurationXml') { $label = 'Custom XML path (optional)' }
        [pscustomobject]@{
            Name=$name; Label=$label; Type=$metadata.ParameterType; Default=$default
            Choices=@($choices); Attributes=$metadata.Attributes
        }
    }
}

function New-OSDAppUIConfiguration {
    param([Parameter(Mandatory)][string]$Id)
    $values = @{}
    foreach ($field in @(Get-OSDAppUIConfigurationFields -Id $Id)) {
        if ($null -ne $field.Default) { $values[$field.Name] = $field.Default }
    }
    $values
}

function Copy-OSDAppUIConfiguration {
    param([Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Configuration)
    $copy = @{}
    foreach ($key in $Configuration.Keys) {
        $value = $Configuration[$key]
        if ($value -is [array]) { $copy[$key] = $value.Clone() } else { $copy[$key] = $value }
    }
    $copy
}

function ConvertTo-OSDAppUIConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][hashtable]$Values)

    $result = @{}
    $customOffice = $Id -eq 'Microsoft365Apps' -and -not [string]::IsNullOrWhiteSpace([string]$Values['ConfigurationXml'])
    foreach ($field in @(Get-OSDAppUIConfigurationFields -Id $Id)) {
        $name = $field.Name
        if ($customOffice -and $name -notin @('ConfigurationXml','OfficeDeploymentToolUri')) { continue }
        $raw = $Values[$name]
        if ($null -eq $raw -or ($raw -is [string] -and [string]::IsNullOrWhiteSpace($raw))) { continue }
        try {
            if ($field.Type -eq [string[]]) {
                # MSI values may contain commas; newline is the common array separator.
                $value = @($raw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if ($name -eq 'Language') { $value = @($value -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            }
            elseif ($field.Type -in @([bool],[switch],[Nullable[bool]])) {
                $value = [System.Convert]::ToBoolean($raw)
            }
            else { $value = [System.Management.Automation.LanguagePrimitives]::ConvertTo($raw,$field.Type) }
            foreach ($entry in @($value)) {
                foreach ($attribute in $field.Attributes) {
                    if ($attribute -is [System.Management.Automation.ValidateSetAttribute] -and $entry -notin $attribute.ValidValues) {
                        throw "Choose from: $($attribute.ValidValues -join ', ')."
                    }
                    if ($attribute -is [System.Management.Automation.ValidateRangeAttribute] -and ($entry -lt $attribute.MinRange -or $entry -gt $attribute.MaxRange)) {
                        throw "Enter a value between $($attribute.MinRange) and $($attribute.MaxRange)."
                    }
                    if ($attribute -is [System.Management.Automation.ValidatePatternAttribute] -and $entry -notmatch $attribute.RegexPattern) {
                        throw 'Value does not match the cmdlet format.'
                    }
                }
            }
            if ($name -match 'Uri$') {
                $uri = $null
                if (-not [uri]::TryCreate([string]$value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('https','http')) {
                    throw 'Enter an absolute HTTP or HTTPS URL.'
                }
            }
            $result[$name] = $value
        }
        catch { throw "${name}: $($_.Exception.Message)" }
    }
    # Fields with cmdlet defaults must remain explicit; blank must not silently reset a choice.
    foreach ($field in @(Get-OSDAppUIConfigurationFields -Id $Id)) {
        if ($customOffice -and $field.Name -ne 'OfficeDeploymentToolUri') { continue }
        if ($null -ne $field.Default -and (-not $result.ContainsKey($field.Name) -or @($result[$field.Name]).Count -eq 0)) {
            throw "$($field.Name): a value is required. Use Reset defaults to restore cmdlet defaults."
        }
    }
    if ($customOffice) { [void](Test-OSDAppOfficeConfigurationXml -Path $result.ConfigurationXml) }
    if ($Id -eq 'CiscoWebex') {
        $webex = @{}
        foreach ($name in @('AutoStartWithWindows','AcceptEula','PreventPreLoginUpdates','EnableOutlookIntegration','DefaultTheme','EmailHint','AdditionalMsiProperties')) {
            if ($result.ContainsKey($name)) { $webex[$name] = $result[$name] }
        }
        $null = New-OSDAppCiscoWebexMsiProperties @webex
    }
    $result
}

function Format-OSDAppUIConfiguration {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.Source -ne 'BuiltIn') { return 'Repository package settings; no built-in options.' }
    $parts = foreach ($field in @(Get-OSDAppUIConfigurationFields -Id $Entry.Id)) {
        if (-not $Entry.Configuration.ContainsKey($field.Name)) { continue }
        $value = $Entry.Configuration[$field.Name]
        # Download URLs can include private query tokens; keep them out of the summary.
        if ($field.Name -match 'Uri$') { continue }
        '{0}: {1}' -f $field.Label,(@($value) -join ', ')
    }
    $parts -join '; '
}

function Set-OSDAppUISelection {
    param([Parameter(Mandatory)][hashtable]$Draft, [Parameter(Mandatory)]$Application, [Parameter(Mandatory)][bool]$Selected)
    $key = Get-OSDAppUISelectionKey -Application $Application
    if (-not $Draft.Entries.ContainsKey($key)) {
        $configuration = if ($Application.Source -eq 'BuiltIn') { New-OSDAppUIConfiguration -Id $Application.Id } else { @{} }
        $display = Get-OSDAppUIDisplayInfo -Application $Application -BuiltInMetadata @(Get-OSDAppUIBuiltInMetadata)
        $Draft.Entries[$key] = [pscustomobject]@{
            Key=$key; Id=[string]$Application.Id; Source=[string]$Application.Source
            DisplayName=$display.DisplayName; PackageType=(Get-OSDAppUIPackageType -Application $Application)
            Configuration=$configuration
        }
    }
    if ($Selected -and -not $Draft.Order.Contains($key)) { [void]$Draft.Order.Add($key) }
    if (-not $Selected) { [void]$Draft.Order.Remove($key) }
}

function Move-OSDAppUISelection {
    param([Parameter(Mandatory)][hashtable]$Draft, [Parameter(Mandatory)][string]$Key, [ValidateSet(-1,1)][int]$Offset)
    $index = $Draft.Order.IndexOf($Key)
    $next = $index + $Offset
    if ($index -lt 0 -or $next -lt 0 -or $next -ge $Draft.Order.Count) { return }
    $Draft.Order.RemoveAt($index)
    $Draft.Order.Insert($next,$Key)
}
