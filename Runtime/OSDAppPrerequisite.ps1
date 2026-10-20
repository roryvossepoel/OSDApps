# Shared runtime acquisition, validation and installed-version checks.
function Get-OSDAppPrerequisiteSpec {
    param(
        [Parameter(Mandatory)][ValidateSet('VisualCppRedist','DotNetRuntime')][string]$Family,
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateSet('Runtime','Desktop')][string]$RuntimeType = 'Desktop',
        [string]$Channel = '10.0'
    )
    if ($Family -eq 'VisualCppRedist') {
        $id = "VisualCppRedist-$Architecture"
        $relative = "BuiltIn\VisualCppRedist\$Architecture"
        $display = "Visual C++ v14 Redistributable ($Architecture)"
        $Channel = '14'; $RuntimeType = 'Runtime'
    }
    else {
        if ($Channel -notmatch '^[1-9][0-9]*\.0$') { throw 'Specify a .NET channel such as 8.0 or 10.0.' }
        $id = "DotNetRuntime-$RuntimeType-$Channel-$Architecture"
        $relative = "BuiltIn\DotNetRuntime\$RuntimeType\$Channel\$Architecture"
        $display = ".NET $RuntimeType Runtime $Channel ($Architecture)"
    }
    [pscustomobject]@{ Id=$id; Family=$Family; Architecture=$Architecture; RuntimeType=$RuntimeType; Channel=$Channel; RelativeRoot=$relative; DisplayName=$display }
}

function Assert-OSDAppPrerequisitePublisher {
    param([Parameter(Mandatory)][string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        [string]$signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=(?:Microsoft Corporation|"Microsoft Corporation")(?=,|$)') {
        throw 'Runtime installer requires a valid Microsoft Corporation Authenticode signature.'
    }
}

function Get-OSDAppPrerequisiteRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Spec)
    if ($Spec.Family -eq 'VisualCppRedist') {
        $uri = "https://aka.ms/vc14/vc_redist.$($Spec.Architecture).exe"
        $request = [Net.HttpWebRequest]::Create($uri)
        $request.Method = 'HEAD'; $request.Timeout = 60000; $request.ReadWriteTimeout = 60000
        $response = $request.GetResponse()
        try {
            $resolved = $response.ResponseUri
            if ($resolved.Scheme -ne 'https' -or $resolved.Host -notin @('download.visualstudio.microsoft.com','download.microsoft.com')) {
                throw 'Unexpected Visual C++ download host.'
            }
            $etag = [string]$response.Headers['ETag']; $modified = [string]$response.Headers['Last-Modified']
            if ($response.ContentLength -le 0 -or (-not $etag -and -not $modified)) { throw 'Visual C++ freshness metadata is incomplete.' }
            [pscustomobject]@{ PackageUri=$uri; ResolvedUri=$resolved.AbsoluteUri; Size=[long]$response.ContentLength; ETag=$etag; LastModified=$modified; Version=$null; Sha512=$null }
        }
        finally { $response.Close() }
        return
    }
    $metadata = Invoke-RestMethod -Uri "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$($Spec.Channel)/releases.json" -TimeoutSec 60 -ErrorAction Stop
    if ([string]$metadata.'channel-version' -ne $Spec.Channel) {
        throw 'The .NET release metadata does not match the requested channel.'
    }
    # Lifecycle status is advisory; installer identity and integrity remain mandatory.
    $supportProperty = $metadata.PSObject.Properties['support-phase']
    $supportPhase = if ($supportProperty) { [string]$supportProperty.Value } else { '' }
    if ($supportPhase -in @('preview','go-live','golive')) { throw 'Preview .NET channels are not supported.' }
    $supportWarning = ''
    if ($supportPhase -eq 'eol') {
        $supportWarning = ".NET $($Spec.Channel) is end of support. Continuing with the latest published stable patch in the explicitly requested channel."
    }
    elseif ($supportPhase -notin @('active','maintenance')) {
        $supportWarning = ".NET $($Spec.Channel) support status could not be confirmed ('$supportPhase'). Continuing only if stable release and installer validation succeed."
    }
    if ($supportWarning) { Write-Warning $supportWarning }
    $version = [string]$metadata.'latest-runtime'
    if ($version -notmatch ('^' + [regex]::Escape($Spec.Channel) + '\.\d+$')) { throw 'Invalid stable .NET runtime version.' }
    $releases = @($metadata.releases | Where-Object { [string]$_.'release-version' -eq $version })
    if ($releases.Count -ne 1) { throw 'Expected exactly one stable .NET release.' }
    $kind = if ($Spec.RuntimeType -eq 'Desktop') { 'windowsdesktop' } else { 'runtime' }
    $component = $releases[0].$kind
    if ([string]$component.version -ne $version) { throw '.NET component version does not match its release.' }
    $files = @($component.files | Where-Object { $_.rid -eq "win-$($Spec.Architecture)" -and $_.name -like '*.exe' })
    if ($files.Count -ne 1 -or [string]$files[0].hash -notmatch '^[a-fA-F0-9]{128}$') { throw 'Expected one .NET installer with a release SHA-512.' }
    $segment = if ($Spec.RuntimeType -eq 'Desktop') { 'WindowsDesktop' } else { 'Runtime' }
    $prefix = if ($Spec.RuntimeType -eq 'Desktop') { 'windowsdesktop-runtime' } else { 'dotnet-runtime' }
    $expected = "https://builds.dotnet.microsoft.com/dotnet/$segment/$version/$prefix-$version-win-$($Spec.Architecture).exe"
    if ([string]$files[0].url -cne $expected) { throw 'Unexpected .NET runtime installer URL.' }
    [pscustomobject]@{ PackageUri=$expected; ResolvedUri=$expected; Size=0; ETag=''; LastModified=''; Version=$version; Sha512=[string]$files[0].hash; SupportWarning=$supportWarning }
}

function Assert-OSDAppPrerequisiteGeneration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Spec, $Release, [switch]$VerifyPublisher)
    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($name in @('Architecture','RuntimeType','Channel')) {
        if ([string]$info.$name -cne [string]$Spec.$name) { throw "Runtime cache $name is incompatible." }
    }
    if ([string]$info.Id -ne $Spec.Family -or [string]$info.VariantId -ne $Spec.Id -or [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$info.Size -le 0) { throw 'Runtime cache identity or integrity metadata is invalid.' }
    $version = [version]$info.Version
    if ($Spec.Family -eq 'VisualCppRedist') {
        if ($version.Major -ne 14 -or [string]$info.PackageUri -cne "https://aka.ms/vc14/vc_redist.$($Spec.Architecture).exe") { throw 'Invalid Visual C++ cache version or source.' }
    }
    else {
        if ("$($version.Major).$($version.Minor)" -ne $Spec.Channel -or [string]$info.Sha512 -notmatch '^[a-fA-F0-9]{128}$') { throw 'Invalid .NET cache version or release hash.' }
        $segment = if ($Spec.RuntimeType -eq 'Desktop') { 'WindowsDesktop' } else { 'Runtime' }
        $prefix = if ($Spec.RuntimeType -eq 'Desktop') { 'windowsdesktop-runtime' } else { 'dotnet-runtime' }
        if ([string]$info.PackageUri -cne "https://builds.dotnet.microsoft.com/dotnet/$segment/$($info.Version)/$prefix-$($info.Version)-win-$($Spec.Architecture).exe") { throw 'Invalid .NET cache source.' }
    }
    if ($Release) {
        foreach ($name in @('PackageUri','ResolvedUri','ETag','LastModified')) {
            if ([string]$info.$name -cne [string]$Release.$name) { throw 'Runtime cache does not match the current release.' }
        }
        if ($Release.Version -and [string]$info.Version -ne [string]$Release.Version) { throw 'Runtime cache version is outdated.' }
        if ($Release.Sha512 -and [string]$info.Sha512 -ne [string]$Release.Sha512) { throw 'Runtime cache release SHA-512 differs.' }
        if ($Release.Size -gt 0 -and [long]$info.Size -ne [long]$Release.Size) { throw 'Runtime cache release size differs.' }
    }
    $package = Join-Path $Root 'Package.exe'
    if ((Get-Item -LiteralPath $package -ErrorAction Stop).Length -ne [long]$info.Size -or
        (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne [string]$info.Sha256) { throw 'Runtime cache size or SHA-256 mismatch.' }
    if ($Spec.Family -eq 'DotNetRuntime' -and (Get-FileHash -LiteralPath $package -Algorithm SHA512).Hash -ne [string]$info.Sha512) { throw '.NET release SHA-512 mismatch.' }
    if ($VerifyPublisher) { Assert-OSDAppPrerequisitePublisher -Path $package }
    $info
}

function Sync-OSDAppPrerequisiteGeneration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Spec, [Parameter(Mandatory)][scriptblock]$Download, [double]$MinimumFreeSpaceGB=1)
    Restore-OSDAppCacheGeneration -Root $Root -Validate { param($candidate) Assert-OSDAppPrerequisiteGeneration -Root $candidate -Spec $Spec -VerifyPublisher } | Out-Null
    $release = Get-OSDAppPrerequisiteRelease -Spec $Spec
    $current = $false
    try { $info = Assert-OSDAppPrerequisiteGeneration -Root $Root -Spec $Spec -Release $release -VerifyPublisher; $current = $true }
    catch { Write-Verbose "Runtime cache requires acquisition: $($_.Exception.Message)" }
    if (-not $current) {
        $downloadAction = $Download
        Invoke-OSDAppBuiltInCacheTransaction -Root $Root -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
            param($candidate)
            $package = Join-Path $candidate 'Package.exe'
            & $downloadAction $release.PackageUri $package | Out-Null
            Assert-OSDAppPrerequisitePublisher -Path $package
            $version = $release.Version
            if ($Spec.Family -eq 'VisualCppRedist') {
                $fileVersion = (Get-Item -LiteralPath $package).VersionInfo.FileVersion
                if ($fileVersion -notmatch '(?<version>14\.\d+\.\d+\.\d+)') { throw 'Cannot determine the signed Visual C++ installer version.' }
                $version = $Matches.version
            }
            [ordered]@{
                Id=$Spec.Family; VariantId=$Spec.Id; DisplayName=$Spec.DisplayName; Cached=$true; Version=$version;
                Architecture=$Spec.Architecture; RuntimeType=$Spec.RuntimeType; Channel=$Spec.Channel;
                VersionSource='Microsoft'; PackageUri=$release.PackageUri; ResolvedUri=$release.ResolvedUri;
                Sha256=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash; Sha512=$release.Sha512;
                Size=(Get-Item -LiteralPath $package).Length; ETag=$release.ETag; LastModified=$release.LastModified;
                SourcePolicy='Evergreen'; SyncMethod=$(if ($Spec.Family -eq 'DotNetRuntime') { 'ReleaseSha512' } else { 'HttpMetadataAndPublisher' });
                SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8
        } -Validate { param($candidate) Assert-OSDAppPrerequisiteGeneration -Root $candidate -Spec $Spec -Release $release -VerifyPublisher } | Out-Null
        $info = Assert-OSDAppPrerequisiteGeneration -Root $Root -Spec $Spec -VerifyPublisher
    }
    $supportWarning = if ($release.PSObject.Properties['SupportWarning']) { [string]$release.SupportWarning } else { '' }
    [pscustomobject]@{ Id=$Spec.Id; Version=$info.Version; Architecture=$Spec.Architecture; Root=$Root; Updated=(-not $current); SupportWarning=$supportWarning }
}

function Get-OSDAppInstalledPrerequisiteVersion {
    param([Parameter(Mandatory)]$Spec)
    $versions = @()
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
        try {
            if ($Spec.Family -eq 'VisualCppRedist') {
                $key = $base.OpenSubKey("SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$($Spec.Architecture)")
                if ($key) {
                    try {
                        $version = [string]$key.GetValue('Version','')
                        if ($key.GetValue('Installed',0) -eq 1 -and $version -match '^v?(14\.\d+\.\d+\.\d+)$') { $versions += [version]$Matches[1] }
                    } finally { $key.Dispose() }
                }
            }
            else {
                $framework = if ($Spec.RuntimeType -eq 'Desktop') { 'Microsoft.WindowsDesktop.App' } else { 'Microsoft.NETCore.App' }
                $key = $base.OpenSubKey("SOFTWARE\dotnet\Setup\InstalledVersions\$($Spec.Architecture)\sharedfx\$framework")
                if ($key) {
                    try { foreach ($name in $key.GetValueNames()) { if ($name -match ('^'+[regex]::Escape($Spec.Channel)+'\.\d+$') -and $key.GetValue($name,0) -eq 1) { $versions += [version]$name } } }
                    finally { $key.Dispose() }
                }
            }
        } finally { $base.Dispose() }
    }
    $latest = $versions | Sort-Object -Descending | Select-Object -First 1
    if ($latest -and $Spec.Family -eq 'DotNetRuntime' -and $Spec.RuntimeType -eq 'Desktop') {
        $coreSpec = Get-OSDAppPrerequisiteSpec -Family DotNetRuntime -Architecture $Spec.Architecture -Channel $Spec.Channel -RuntimeType Runtime
        $core = Get-OSDAppInstalledPrerequisiteVersion -Spec $coreSpec
        if (-not $core) { return $null }
        if ($core -lt $latest) { return $core }
    }
    $latest
}
