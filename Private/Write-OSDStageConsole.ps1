function Write-OSDStageConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Info','Warning','Error','Success')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'OSDStage'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $label = switch ($Level) {
        'Warning' { 'WARN' }
        'Error'   { 'ERROR' }
        'Success' { 'INFO' }
        default   { 'INFO' }
    }

    $line = '[{0}] [{1}] {2}: {3}' -f $timestamp, $label, $Component, $Message

    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Success' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
}