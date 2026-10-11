function Get-OSDAppUIBuiltInMetadata {
    [CmdletBinding()]
    param()

    # Resolve metadata from the *loaded module*, not a mutable script-scoped
    # variable. The latter can differ in WinPE PowerShell 5.1 after dot-sourcing
    # private functions via the module loader.
    $moduleInfo = $MyInvocation.MyCommand.Module
    $moduleBase = if ($moduleInfo -and $moduleInfo.ModuleBase) {
        [string]$moduleInfo.ModuleBase
    }
    else {
        [string]$script:moduleRoot
    }
    if ([string]::IsNullOrWhiteSpace($moduleBase)) {
        Write-Warning 'OSDApps built-in metadata: cannot resolve the module location.'
        return
    }

    $metadataPath = Join-Path $moduleBase 'metadata\builtins.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        Write-Warning "OSDApps built-in metadata not found: $metadataPath"
        return
    }
    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        foreach ($app in @($metadata.Applications)) {
            if ($app -and $app.Id) { $app }
        }
    }
    catch {
        Write-Warning "OSDApps built-in metadata could not be read from '$metadataPath': $($_.Exception.Message)"
    }
}

function Get-OSDAppUIDisplayInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Application,
        [object[]]$CatalogApps = @(),
        [object[]]$BuiltInMetadata = @()
    )

    $id = [string]$Application.Id
    $display = [string]$Application.DisplayName
    $vendor = [string]$Application.Vendor

    # PowerShell 5.1 can unwrap a single pipeline result to a scalar object.
    # Do not depend on .Count and [0] on those results: a scalar PSCustomObject
    # is not an array. Resolve candidates as objects with a plain foreach.
    $catalogMatch = $null
    foreach ($candidate in $CatalogApps) {
        if ($null -ne $candidate -and
            [string]::Equals([string]$candidate.Id, $id, [StringComparison]::OrdinalIgnoreCase)) {
            $catalogMatch = $candidate
            break
        }
    }

    if ($null -ne $catalogMatch) {
        if (-not $display -or $display -eq $id) {
            $candidateName = [string]$catalogMatch.DisplayName
            if ($candidateName) { $display = $candidateName }
        }
        if (-not $vendor) { $vendor = [string]$catalogMatch.Vendor }
    }

    if ([string]$Application.Source -eq 'BuiltIn') {
        foreach ($candidate in $BuiltInMetadata) {
            if ($null -eq $candidate -or
                -not [string]::Equals([string]$candidate.Id, $id, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not $display -or $display -eq $id) {
                $candidateName = [string]$candidate.DisplayName
                if ($candidateName) { $display = $candidateName }
            }
            if (-not $vendor) { $vendor = [string]$candidate.Vendor }
            break
        }
    }

    if (-not $display) { $display = $id }
    [pscustomobject]@{
        DisplayName = $display
        Vendor = if ($vendor) { $vendor } else { '-' }
    }
}

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

    # Never show the version from another architecture or channel as though
    # it belongs to the staged application.
    $architecture = [string]$Application.Architecture
    if ($architecture -and $architecture -notin @('Auto','Any')) {
        $matches = @($matches | Where-Object { [string]$_.Architecture -eq $architecture })
    }
    $channel = [string]$Application.Channel
    if ($channel) {
        $matches = @($matches | Where-Object { -not $_.Channel -or [string]$_.Channel -eq $channel })
    }
    if ($matches.Count -eq 0) { return '-' }
    if ($matches.Count -gt 1 -and $architecture -in @('','Auto','Any')) {
        # Multiple architecture variants without an explicit target are ambiguous.
        $variants = @($matches.Architecture | Sort-Object -Unique)
        if ($variants.Count -gt 1) { return '-' }
    }
    $version = [string]$matches[0].Version
    if ($version -eq 'Current') { return 'Not recorded' }
    return $version
}

function Get-OSDAppUIAvailabilityLabel {
    [CmdletBinding()]
    param(
        [string]$Availability,
        [switch]$Offline
    )

    # The cache location and validity are independent of catalog connectivity.
    # The header shows whether online discovery was enabled, not each row.
    switch ($Availability) {
        'Cached'       { 'USB cached'; break }
        'CachedOnly'   { 'USB cached'; break }
        'InvalidCache' { 'USB cache invalid'; break }
        'Online'       { 'Online only'; break }
        'Available'    { 'Not on USB'; break }
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
    $eventName = ''
    if ($message -match '^\[(?<event>[^\]]+)\]\s*') {
        $eventName = $Matches['event']
        $message = $message.Substring($Matches[0].Length)
        # Keep the event name even when a separate CMTrace component exists.
        if (-not $component) { $component = $eventName }
    }
    [pscustomobject]@{
        Timestamp = $time
        Level = $level
        Component = $component
        Event = $eventName
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


function Get-OSDAppUISignatureLabel {
    [CmdletBinding()]
    param(
        [string]$Status,
        [string]$Source
    )

    # Repository ZIPs are validated using their manifest SHA-256 and are not
    # part of the built-in Authenticode signature-check scope.
    if ($Source -eq 'Repository') { return 'N/A' }

    switch ($Status) {
        'Valid'                { 'Signature valid'; break }
        'NotSigned'            { 'Not signed'; break }
        'HashMismatch'         { 'Hash mismatch'; break }
        'NotTrusted'           { 'Not trusted'; break }
        'UnknownError'         { 'Trust unknown'; break }
        'Check failed'         { 'Check failed'; break }
        'File missing'         { 'File missing'; break }
        'Unavailable in WinPE' { 'WinPE: not checked'; break }
        'Not assessed'         { 'Not assessed'; break }
        default                { 'Not checked' }
    }
}
