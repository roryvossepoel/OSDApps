function Get-OSDStageHostArchitecture {
    [CmdletBinding()]
    param()

    $raw = [string]$env:PROCESSOR_ARCHITECTURE

    switch ($raw.ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default {
            throw "Unsupported processor architecture '$raw'. OSDStage Client currently supports x64 and arm64 hosts."
        }
    }
}
