function Write-OSDStageLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [Alias('Event')]
        [string]$EventName,

        [ValidateSet('Debug','Info','Warning','Error')]
        [string]$Level = 'Info',

        [string]$Message,

        [hashtable]$Data,

        [int]$MaxSizeMB = 1,

        [int]$RetainFiles = 3
    )

    $directory = Split-Path -Path $LogPath -Parent
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        $maxBytes = $MaxSizeMB * 1MB
        $length = (Get-Item -LiteralPath $LogPath).Length

        if ($length -ge $maxBytes) {
            for ($i = $RetainFiles - 1; $i -ge 1; $i--) {
                $source = "$LogPath.$i"
                $target = "$LogPath.$($i + 1)"

                if (Test-Path -LiteralPath $source) {
                    Move-Item -LiteralPath $source -Destination $target -Force
                }
            }

            Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force

            $oldest = "$LogPath.$($RetainFiles + 1)"
            if (Test-Path -LiteralPath $oldest) {
                Remove-Item -LiteralPath $oldest -Force
            }
        }
    }

    $type = switch ($Level) {
        'Warning' { 2 }
        'Error'   { 3 }
        default   { 1 }
    }

    $details = @()
    if ($Data) {
        foreach ($key in @($Data.Keys | Sort-Object)) {
            $value = $Data[$key]

            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = @($value) -join ','
            }

            $details += ('{0}={1}' -f $key, $value)
        }
    }

    $logMessage = if ($Message) { "[$EventName] $Message" } else { "[$EventName]" }
    if ($details.Count -gt 0) {
        $logMessage += ' | ' + ($details -join '; ')
    }

    $logMessage = $logMessage -replace '\]LOG\]!>', ']LOG]! >'
    $logMessage = $logMessage -replace '[\r\n\x00-\x1F]+', ' '

    $now = (Get-Date).ToUniversalTime()
    $time = $now.ToString('HH:mm:ss.fff') + '+000'
    $date = $now.ToString('MM-dd-yyyy')
    $thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId

    $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="{5}" file="">' -f $logMessage, $time, $date, $Component, $type, $thread

    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
