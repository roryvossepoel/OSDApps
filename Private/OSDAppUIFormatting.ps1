function Get-OSDAppUIDisplayVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Application)

    # "Current" is a vendor acquisition policy, not a concrete version.
    if ([string]$Application.Source -eq 'BuiltIn') { return 'Current' }
    $version = [string]$Application.Version
    if (-not [string]::IsNullOrWhiteSpace($version)) { return $version }
    return '-'
}

function Get-OSDAppUICachedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Application,
        [object[]]$CacheEntries = @()
    )

    $id = [string]$Application.Id
    $ids = if ($id -eq 'MicrosoftTeams') { @('MicrosoftTeams','Teams') } else { @($id) }
    $matches = @($CacheEntries | Where-Object { [string]$_.Id -in $ids -and $_.Valid -and -not [string]::IsNullOrWhiteSpace([string]$_.Version) })
    if ($matches.Count -eq 0) { return '-' }
    $version = [string]$matches[0].Version
    if ($version -eq 'Current') { return 'Not recorded' }
    return $version
}

function Get-OSDAppUIAvailabilityLabel {
    [CmdletBinding()]
    param([string]$Availability)

    switch ($Availability) {
        'Cached'       { 'USB cached'; break }
        'CachedOnly'   { 'USB cached (offline)'; break }
        'InvalidCache' { 'USB cache invalid'; break }
        'Online'       { 'Online only'; break }
        'Available'    { 'Vendor available'; break }
        'Unavailable'  { 'Not available'; break }
        default        { if ($Availability) { $Availability } else { '-' } }
    }
}

function ConvertFrom-OSDAppUILogLine {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Line)

    $time = ''
    $level = 'Info'
    $component = ''
    $message = $Line
    $pattern = '^<!\[LOG\[(?<message>.*?)\]LOG\]!><(?<attributes>.*)>$'
    $match = [regex]::Match([string]$Line,$pattern)
    if ($match.Success) {
        $message = $match.Groups['message'].Value
        $attrs = @{}
        foreach ($m in [regex]::Matches($match.Groups['attributes'].Value,'(?<key>[A-Za-z]+)="(?<value>[^"]*)"')) {
            $attrs[$m.Groups['key'].Value.ToLowerInvariant()] = $m.Groups['value'].Value
        }
        if ($attrs['date'] -and $attrs['time']) {
            $time = "$($attrs['date']) $($attrs['time'])"
        }
        elseif ($attrs['time']) { $time = $attrs['time'] }
        $component = [string]$attrs['component']
        $level = switch ([string]$attrs['type']) {
            '3' { 'Error'; break }
            '2' { 'Warning'; break }
            default { 'Info' }
        }
    }
    if (-not $component -and $message -match '^\[(?<event>[^\]]+)\]\s*') {
        $component = $Matches['event']
        $message = $message.Substring($Matches[0].Length)
    }
    [pscustomobject]@{
        Timestamp = $time
        Level = $level
        Component = $component
        Message = $message
        Raw = $Line
    }
}

function Get-OSDAppUILogRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1,2000)][int]$Tail = 500
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Log file not found: $Path"
    }
    foreach ($line in @(Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction Stop)) {
        ConvertFrom-OSDAppUILogLine -Line ([string]$line)
    }
}
