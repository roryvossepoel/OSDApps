function Add-OSDAppDotNetRuntime {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateSet('8.0','9.0','10.0')][string]$Channel = '10.0',
        [ValidateSet('Runtime','Desktop')][string]$RuntimeType = 'Desktop',
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    Assert-OSDAppSourceEnabled -Source BuiltIn
    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $cachePath = $null
    try { $cachePath = Get-OSDAppCachePath } catch { Write-Verbose 'No USB cache; acquisition will use the OS disk.' }
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture $arch -Channel $Channel -RuntimeType $RuntimeType
        if (-not $PSCmdlet.ShouldProcess($target, "Stage $($spec.DisplayName) and integrate SetupComplete")) { continue }
        $result = Add-OSDAppPrerequisiteInternal -Spec $spec -CachePath $cachePath -WindowsPath $target -InstallTimeoutMinutes $InstallTimeoutMinutes -Confirm:$false
        $manifestPath = Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Add-OSDAppSetupComplete -WindowsPath $target -Confirm:$false | Out-Null
        $result
    }
    if ($cachePath -and -not $WhatIfPreference -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'Keep the OSDCloud USB flash drive connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }
}
