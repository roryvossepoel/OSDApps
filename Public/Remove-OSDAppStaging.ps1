function Remove-OSDAppStaging {
    <#
    .SYNOPSIS
    Removes selected applications from the pending OSDApps SetupComplete queue.
    .DESCRIPTION
    Unstages app-specific files on the offline Windows volume, without touching
    the USB cache or uninstalling software. The last app also removes only the
    OSDApps-owned SetupComplete blocks and standalone runtime scripts.
    Full Windows requires -TestMode, which is limited to an isolated TEMP folder.
    .EXAMPLE
    Remove-OSDAppStaging -Name MicrosoftTeams -WindowsPath 'C:\' -WhatIf
    .EXAMPLE
    Remove-OSDAppStaging -Name MicrosoftTeams -TestMode -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [string]$WindowsPath,

        [switch]$TestMode
    )

    $winPE = Test-OSDAppWinPE
    if ($TestMode) {
        if ($winPE) {
            throw '-TestMode is only for full Windows; use -WindowsPath in WinPE.'
        }
        if ($PSBoundParameters.ContainsKey('WindowsPath')) {
            throw '-TestMode uses only the isolated TEMP target. Omit -WindowsPath.'
        }
        $target = Get-OSDAppUITestWindowsPath
    }
    else {
        if (-not $winPE) {
            throw 'Removing staged apps on full Windows requires -TestMode to protect the active Windows installation.'
        }
        $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    }

    $stageRoot = Join-Path $target 'Windows\Temp\OSDApps'
    $manifestPath = Join-Path $stageRoot 'DeviceManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "DeviceManifest.json not found: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $manifest -or -not ($manifest.PSObject.Properties.Name -contains 'Apps')) {
        throw "Invalid DeviceManifest.json: Apps property is missing."
    }

    $requested = @($Name | Select-Object -Unique)
    foreach ($id in $requested) {
        if ([string]$id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]$id -match '\.\.') {
            throw "Invalid application ID '$id'."
        }
    }

    $staged = @($manifest.Apps | Where-Object { $null -ne $_ })
    $toRemove = @($staged | Where-Object { [string]$_.Id -in $requested })
    if ($toRemove.Count -eq 0) {
        return [pscustomobject]@{
            WindowsPath = $target
            Removed = @()
            Remaining = @($staged | ForEach-Object { [string]$_.Id })
            Changed = $false
        }
    }

    # Validate all paths BEFORE any change, including the last-app cleanup.
    foreach ($app in $toRemove) {
        $id = [string]$app.Id
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $id -match '\.\.') {
            throw "Invalid staged application ID '$id'."
        }
        if ([string]$app.Source -notin @('BuiltIn','Repository')) {
            throw "Unexpected staged source '$($app.Source)' for '$id'."
        }
    }

    $remaining = @($staged | Where-Object { [string]$_.Id -notin $requested })
    if ($remaining.Count -eq 0) {
        # Preflight validation of the existing OSDApps SetupComplete blocks.
        # A malformed SetupComplete must not be edited, nor may the manifest.
        Remove-OSDAppSetupComplete -WindowsPath $target -WhatIf -ErrorAction Stop | Out-Null
    }

    $action = "Unstage $($toRemove.Count) application(s) from DeviceManifest and the offline Windows staging folder"
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return
    }

    if ($remaining.Count -eq 0) {
        Remove-OSDAppSetupComplete -WindowsPath $target -Confirm:$false -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
    }
    else {
        $manifest.Apps = @($remaining)
        $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
        $manifest | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
    }

    foreach ($app in $toRemove) {
        $id = [string]$app.Id
        $relative = if ($app.Source -eq 'BuiltIn') {
            Join-Path 'BuiltIn' $id
        }
        else {
            Join-Path 'Packages' $id
        }
        $path = Join-Path $stageRoot $relative
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
    }

    if ($remaining.Count -eq 0) {
        # Remove only OSDApps-owned scripts. Leave other files and folders alone.
        foreach ($file in @('Invoke-OSDAppRunner.ps1','Invoke-OSDAppPreInstall.ps1')) {
            $path = Join-Path $stageRoot $file
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'OSDApps.UnstagedApps'
        WindowsPath = $target
        Removed = @($toRemove | ForEach-Object { [string]$_.Id })
        Remaining = @($remaining | ForEach-Object { [string]$_.Id })
        Changed = $true
    }
}
