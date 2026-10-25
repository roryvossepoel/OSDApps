# Shared validation and execution for staged registry operations. Import has no side effects.
function Resolve-OSDAppRegistryTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $text = $Path -replace '^(?i:Microsoft\.PowerShell\.Core\\)?Registry::', ''
    $match = [regex]::Match($text, '^(?i:(?<Hive>HKLM|HKEY_LOCAL_MACHINE|HKCR|HKEY_CLASSES_ROOT|HKU|HKEY_USERS))(?::)?\\(?<SubKey>.+)$')
    if (-not $match.Success) { throw 'Specify an absolute HKLM, HKCR or HKU path. HKCU and HKCC are not supported.' }
    $subKey = $match.Groups['SubKey'].Value.TrimEnd('\')
    $segments = @($subKey -split '\\')
    if (-not $subKey -or $subKey.Length -gt 32767 -or $subKey -match '[\x00-\x1f/:*?]' -or
        @($segments | Where-Object { $_ -in @('', '.', '..') -or $_.Length -gt 255 -or $_ -ne $_.Trim() }).Count -gt 0 -or
        @($segments | Where-Object { $_ -ieq 'WOW6432Node' }).Count -gt 0) {
        throw 'Invalid registry path. Use -Registry32 instead of an explicit WOW6432Node segment.'
    }
    $root = $match.Groups['Hive'].Value.ToUpperInvariant()
    $hive = 'HKLM'
    if ($root -in @('HKCR','HKEY_CLASSES_ROOT')) { $subKey = 'SOFTWARE\Classes\' + $subKey }
    elseif ($root -in @('HKU','HKEY_USERS')) {
        $hive = 'HKU'
        if ($segments[0] -notmatch '^(?i:\.DEFAULT|S-1-\d+(?:-\d+)+(?:_Classes)?)$' -or $segments.Count -lt 2) {
            throw 'HKU requires an explicit existing loaded hive and a child path. No user hive is created or loaded.'
        }
    }
    [pscustomobject]@{ Hive=$hive; SubKey=$subKey; Path=($hive + '\' + $subKey) }
}

function ConvertTo-OSDAppRegistryData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Type, [AllowNull()][AllowEmptyCollection()][AllowEmptyString()]$Value)
    if ($null -eq $Value) { throw 'A registry value cannot be null. Use an empty string for an empty text value.' }
    switch ($Type) {
        { $_ -in @('String','ExpandString') } {
            if ($Value -isnot [string] -or $Value.Contains([string][char]0)) { throw 'Text registry data must be a string without NUL characters.' }
            return ,$Value
        }
        'MultiString' {
            if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw 'MultiString requires a string array.' }
            $items = @($Value)
            foreach ($item in $items) {
                if ($item -isnot [string] -or $item.Length -eq 0 -or $item.Contains([string][char]0)) { throw 'MultiString elements must be nonempty strings without NUL characters.' }
            }
            return ,([string[]]$items)
        }
        'Binary' {
            if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw 'Binary requires a byte array.' }
            $bytes = [System.Collections.Generic.List[byte]]::new()
            foreach ($item in $Value) {
                $n = 0
                if ($null -eq $item -or -not [int]::TryParse([string]$item, [ref]$n) -or $n -lt 0 -or $n -gt 255) { throw 'Binary elements must be integers from 0 through 255.' }
                $bytes.Add([byte]$n)
            }
            return [Convert]::ToBase64String($bytes.ToArray())
        }
        { $_ -in @('DWord','QWord') } {
            $number = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
            $unsigned = [uint64]0
            if ($number -match '^0[xX][0-9a-fA-F]+$') {
                $unsigned = [uint64]::Parse($number.Substring(2), [Globalization.NumberStyles]::AllowHexSpecifier, [Globalization.CultureInfo]::InvariantCulture)
            }
            elseif ($number -match '^-[0-9]+$') {
                $signed = [int64]::Parse($number, [Globalization.CultureInfo]::InvariantCulture)
                if ($Type -eq 'DWord') {
                    if ($signed -lt [int32]::MinValue) { throw 'DWord data is out of range.' }
                    $unsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$signed),0)
                }
                else { $unsigned = [BitConverter]::ToUInt64([BitConverter]::GetBytes($signed),0) }
            }
            elseif ($number -notmatch '^\+?[0-9]+$' -or -not [uint64]::TryParse($number, [ref]$unsigned)) { throw 'Registry numeric data must be a whole integer in range.' }
            if ($Type -eq 'DWord' -and $unsigned -gt [uint32]::MaxValue) { throw 'DWord data is out of range.' }
            return $unsigned.ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        default { throw "Unsupported registry type '$Type'." }
    }
}

function New-OSDAppRegistryOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Key','Value')][string]$Action,
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Name = '',
        [ValidateSet('String','ExpandString','MultiString','Binary','DWord','QWord')][string]$Type = 'String',
        [AllowNull()][AllowEmptyCollection()][AllowEmptyString()]$Value,
        [switch]$Registry32, [switch]$Registry64
    )
    if ($Registry32 -and $Registry64) { throw 'Specify only one of -Registry32 and -Registry64.' }
    $target = Resolve-OSDAppRegistryTarget -Path $Path
    $view = if ($Registry32) { 'Registry32' } elseif ($Registry64) { 'Registry64' } else { 'Default' }
    if ($Name.Length -gt 16383 -or $Name.Contains([string][char]0)) { throw 'Invalid registry value name.' }
    [pscustomobject]@{
        Action=$Action; Path=$target.Path; View=$view
        Name=$(if ($Action -eq 'Value') { $Name } else { $null })
        Type=$(if ($Action -eq 'Value') { $Type } else { $null })
        Data=$(if ($Action -eq 'Value') { ConvertTo-OSDAppRegistryData -Type $Type -Value $Value } else { $null })
    }
}

function ConvertFrom-OSDAppRegistryData {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Operation)
    switch ([string]$Operation.Type) {
        'DWord' { return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]::Parse([string]$Operation.Data, [Globalization.CultureInfo]::InvariantCulture)),0) }
        'QWord' { return [BitConverter]::ToInt64([BitConverter]::GetBytes([uint64]::Parse([string]$Operation.Data, [Globalization.CultureInfo]::InvariantCulture)),0) }
        'Binary' { return ,([Convert]::FromBase64String([string]$Operation.Data)) }
        'MultiString' { return ,([string[]]@($Operation.Data)) }
        default { return ,([string]$Operation.Data) }
    }
}

function Assert-OSDAppRegistryConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)
    if ($Configuration.SchemaVersion -ne 1 -or $Configuration.Operations -isnot [array] -or
        @($Configuration.Operations).Count -eq 0 -or @($Configuration.Operations).Count -gt 10000) { throw 'Invalid registry configuration.' }
    $seen = @{}
    foreach ($op in $Configuration.Operations) {
        if ($null -eq $op) { throw 'Empty registry operation.' }
        foreach ($field in @('Action','Path','View','Name','Type','Data')) {
            if ($op.PSObject.Properties.Name -notcontains $field) { throw "Registry operation lacks $field." }
        }
        if ([string]$op.Action -notin @('Key','Value') -or [string]$op.View -notin @('Default','Registry32','Registry64')) { throw 'Invalid registry action or view.' }
        $target = Resolve-OSDAppRegistryTarget -Path ([string]$op.Path)
        if ($target.Path -cne [string]$op.Path) { throw 'Registry path must be canonical.' }
        if ($op.Action -eq 'Key') {
            if ($null -ne $op.Name -or $null -ne $op.Type -or $null -ne $op.Data) { throw 'A key-only operation must not contain value data.' }
        }
        else {
            if ($op.Name -isnot [string] -or $op.Name.Length -gt 16383 -or $op.Name.Contains([string][char]0)) { throw 'Invalid registry value name.' }
            if ($op.Type -notin @('String','ExpandString','MultiString','Binary','DWord','QWord') -or $null -eq $op.Data) { throw 'Invalid registry value data.' }
            $value = ConvertFrom-OSDAppRegistryData -Operation $op
            $canonicalData = ConvertTo-OSDAppRegistryData -Type $op.Type -Value $value
            if ((ConvertTo-Json -InputObject $canonicalData -Compress -Depth 5) -cne (ConvertTo-Json -InputObject $op.Data -Compress -Depth 5)) { throw 'Registry data encoding is not canonical.' }
        }
        $identity = @($op.Action,$op.Path,$op.Name,$op.View) | ConvertTo-Json -Compress
        if ($seen.ContainsKey($identity)) { throw 'Duplicate registry operation.' }
        $seen[$identity] = $true
    }
}

function Invoke-OSDAppRegistryOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Operation)
    if ($env:OS -ne 'Windows_NT') { throw 'Registry execution requires Windows.' }
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Registry execution is forbidden in WinPE. Stage only.' }
    if ($Operation.View -eq 'Registry64' -and -not [Environment]::Is64BitOperatingSystem) { throw 'Registry64 was requested on 32-bit Windows.' }
    $target = Resolve-OSDAppRegistryTarget -Path $Operation.Path
    $resolvedView = if ($Operation.View -eq 'Default') {
        if ([Environment]::Is64BitProcess) { 'Registry64' } else { 'Registry32' }
    } else { [string]$Operation.View }
    $hiveEnum = if ($target.Hive -eq 'HKLM') { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::Users }
    $viewEnum = [Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$resolvedView))
    $base = $null; $owner = $null; $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hiveEnum,$viewEnum)
        $owner = $base
        $subKey = [string]$target.SubKey
        if ($target.Hive -eq 'HKU') {
            $parts = $subKey -split '\\',2
            $owner = $base.OpenSubKey($parts[0],$true)
            if ($null -eq $owner) { throw 'The requested HKU hive is not loaded. No hive was created or loaded.' }
            $subKey = $parts[1]
        }
        $key = $owner.OpenSubKey($subKey,$false)
        $keyExisted = $null -ne $key
        $same = $false; $valueExisted = $false
        if ($Operation.Action -eq 'Key') { $same = $keyExisted }
        elseif ($keyExisted) {
            $valueExisted = @($key.GetValueNames()) -contains [string]$Operation.Name
            if ($valueExisted -and [string]$key.GetValueKind($Operation.Name) -eq [string]$Operation.Type) {
                $read = $key.GetValue($Operation.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $data = ConvertTo-OSDAppRegistryData -Type $Operation.Type -Value $read
                $same = (ConvertTo-Json -InputObject $data -Compress -Depth 5) -ceq (ConvertTo-Json -InputObject $Operation.Data -Compress -Depth 5)
            }
        }
        if ($null -ne $key) { $key.Dispose(); $key=$null }
        $outcome = 'Unchanged'
        if (-not $same) {
            $key = $owner.CreateSubKey($subKey,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
            if ($null -eq $key) { throw 'Registry key creation returned no key.' }
            if ($Operation.Action -eq 'Value') {
                $value = ConvertFrom-OSDAppRegistryData -Operation $Operation
                $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind],$Operation.Type,$true))
                $key.SetValue([string]$Operation.Name,$value,$kind)
                $outcome = if ($valueExisted) { 'Updated' } else { 'Created' }
            } else { $outcome = 'Created' }
            $key.Dispose(); $key=$null
        }
        $key = $owner.OpenSubKey($subKey,$false)
        if ($null -eq $key) { throw 'Registry key read-back failed.' }
        if ($Operation.Action -eq 'Value') {
            if (@($key.GetValueNames()) -notcontains [string]$Operation.Name -or [string]$key.GetValueKind($Operation.Name) -ne [string]$Operation.Type) { throw 'Registry value type read-back failed.' }
            $actual = $key.GetValue($Operation.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $actualData = ConvertTo-OSDAppRegistryData -Type $Operation.Type -Value $actual
            if ((ConvertTo-Json -InputObject $actualData -Compress -Depth 5) -cne (ConvertTo-Json -InputObject $Operation.Data -Compress -Depth 5)) { throw 'Registry value data read-back failed.' }
        }
        [pscustomobject]@{ Action=$Operation.Action; Path=$target.Path; Name=$Operation.Name; Type=$Operation.Type; RequestedView=$Operation.View; ResolvedView=$resolvedView; Process64Bit=[Environment]::Is64BitProcess; Status='Succeeded'; Outcome=$outcome; Error=$null }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $owner -and $owner -ne $base) { $owner.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
}
