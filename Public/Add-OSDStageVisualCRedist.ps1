function Add-OSDStageVisualCRedist {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn
    $target = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
    $cachePath = $null
    try { $cachePath = Get-OSDStageCachePath } catch { Write-Verbose 'No USB cache; acquisition will use the OS disk.' }
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDStagePrerequisiteSpec -Family VisualCRedist -Architecture $arch
        if (-not $PSCmdlet.ShouldProcess($target, "Stage $($spec.DisplayName) and integrate SetupComplete")) { continue }
        $result = Add-OSDStagePrerequisiteInternal -Spec $spec -CachePath $cachePath -WindowsPath $target -InstallTimeoutMinutes $InstallTimeoutMinutes -Confirm:$false
        $manifestPath = Join-Path $target 'Windows\Temp\OSDStage\DeviceManifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest $manifest
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Add-OSDStageSetupComplete -WindowsPath $target -Confirm:$false | Out-Null
        $result
    }
    if ($cachePath -and -not $WhatIfPreference -and -not $script:OSDStageCacheMediaWarningShown) {
        Write-Warning 'Keep the OSDCloud USB flash drive connected until OOBE is displayed.'
        $script:OSDStageCacheMediaWarningShown = $true
    }
}
