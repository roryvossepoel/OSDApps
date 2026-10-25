function Save-OSDAppRegistryStaging {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Operation, [string]$WindowsPath)
    if (-not (Test-OSDAppWinPE)) { throw 'Stage registry changes in WinPE after OSDCloud, not on the preparation PC.' }
    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $stage = Join-Path $target 'Windows\Temp\OSDApps'
    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $packageRoot = Join-Path $stage 'Packages\RegistrySettings'
    $archivePath = Join-Path $packageRoot 'Package.zip'
    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $m -or $m.PSObject.Properties.Name -notcontains 'Apps') { throw 'Existing device manifest is invalid.' }
        $m
    } else { [pscustomobject]@{SchemaVersion=1; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Apps=@()} }
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $previous = @($manifest.Apps | Where-Object Id -eq 'RegistrySettings')
    if ($previous.Count -gt 1) { throw 'Duplicate RegistrySettings entry in device manifest.' }
    $operations = @()
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    if ($previous.Count -eq 1) {
        $entry = $previous[0]
        if ($entry.Source -ne 'Repository' -or $entry.Type -ne 'RepositoryPackage' -or
            $entry.PackageType -ne 'Script' -or $entry.RegistryStageSchema -ne 1 -or
            -not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $entry.Archive.Sha256) {
            throw 'Existing RegistrySettings is not an intact locally staged registry script. Nothing was replaced.'
        }
        $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $configEntry = $zip.GetEntry('Package/config.json')
            if ($null -eq $configEntry -or $configEntry.Length -gt 16MB) { throw 'Missing or oversized registry configuration in script package.' }
            $reader = [IO.StreamReader]::new($configEntry.Open(),[Text.Encoding]::UTF8)
            try { $config = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
            finally { $reader.Dispose() }
            Assert-OSDAppRegistryConfiguration -Configuration $config
            $operations = @($config.Operations)
        } finally { $zip.Dispose() }
    }
    elseif (Test-Path -LiteralPath $packageRoot) { throw 'Unowned RegistrySettings staging directory exists. Nothing was replaced.' }
    $operations = @($operations | Where-Object {
        -not ($_.Action -eq $Operation.Action -and $_.Path -ieq $Operation.Path -and
            $_.Name -ieq $Operation.Name -and $_.View -eq $Operation.View)
    }) + @($Operation)
    $config = [pscustomobject]@{
        SchemaVersion=1; DeploymentId=$manifest.DeploymentId
        ResultPath=(Join-Path (Split-Path ([string]$manifest.Runtime.ResultPath) -Parent) 'Registry-Result.json')
        Operations=@($operations)
    }
    Assert-OSDAppRegistryConfiguration -Configuration $config
    $scripts = @(
        @{ Source=(Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRegistry.ps1'); Entry='Package/Install.ps1' }
        @{ Source=(Join-Path $moduleRoot 'Runtime\OSDAppRegistry.ps1'); Entry='Package/OSDAppRegistry.ps1' }
    )
    foreach ($script in $scripts) {
        if (-not (Test-Path -LiteralPath $script.Source -PathType Leaf)) { throw 'Registry runtime script is missing from this module.' }
    }
    New-Item -ItemType Directory -Path (Split-Path $packageRoot -Parent) -Force | Out-Null
    $transaction = Join-Path (Split-Path $packageRoot -Parent) ('.registry-' + [guid]::NewGuid().ToString('N'))
    $backup = $transaction + '.previous'
    $manifestTemp = $manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $promoted = $false; $committed = $false; $backedUp = $false
    try {
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        $candidate = Join-Path $transaction 'Package.zip'
        $zip = [IO.Compression.ZipFile]::Open($candidate,[IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($script in $scripts) {
                $stream = $zip.CreateEntry($script.Entry).Open()
                try { $bytes=[IO.File]::ReadAllBytes($script.Source); $stream.Write($bytes,0,$bytes.Length) }
                finally { $stream.Dispose() }
            }
            $stream = $zip.CreateEntry('Package/config.json').Open()
            try { $bytes=[Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Depth 15)); $stream.Write($bytes,0,$bytes.Length) }
            finally { $stream.Dispose() }
        } finally { $zip.Dispose() }
        $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        # Reuse the existing verified local script-package runner, not a new execution engine.
        $app = [pscustomobject]@{
            Id='RegistrySettings'; DisplayName='Registry settings'; Vendor='OSDApps'
            Source='Repository'; Type='RepositoryPackage'; PackageType='Script'; Version='1.0.0'; Architecture='any'
            Archive=[pscustomobject]@{Sha256=$hash}; SuccessCodes=@(0)
            RegistryStageSchema=1; RegistryOperationCount=$operations.Count
        }
        $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
        $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestTemp -Encoding UTF8
        Add-OSDAppSetupComplete -WindowsPath $target -Confirm:$false -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $packageRoot) { Move-Item -LiteralPath $packageRoot -Destination $backup -ErrorAction Stop; $backedUp=$true }
        Move-Item -LiteralPath $transaction -Destination $packageRoot -ErrorAction Stop
        $promoted = $true
        Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force -ErrorAction Stop
        $committed = $true
    }
    finally {
        if (-not $committed) {
            if ($promoted -and (Test-Path -LiteralPath $packageRoot)) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
            if ($backedUp) { Move-Item -LiteralPath $backup -Destination $packageRoot -ErrorAction Stop }
        }
        if ($committed -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if (Test-Path -LiteralPath $transaction) { Remove-Item -LiteralPath $transaction -Recurse -Force }
        if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp -Force }
    }
    [pscustomobject]@{
        PSTypeName='OSDApps.StagedApp'; Name='RegistrySettings'; PackageType='Script'; Source='Repository'
        WindowsPath=$target; StagedPath=$packageRoot; Version='1.0.0'; OperationCount=$operations.Count
        RegistryPath=$Operation.Path; RegistryView=$Operation.View; Action=$Operation.Action
    }
}
