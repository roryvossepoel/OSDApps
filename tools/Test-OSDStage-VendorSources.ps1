#Requires -Version 5.1
<#
.SYNOPSIS
Checks selected OSDStage vendor sources without downloading installers or changing caches.
.DESCRIPTION
Run from a separate Windows PowerShell process on the preparation PC.
Saves OSDStage 0.49.1 from PSGallery to a new temporary directory. Uses its real
7Zip, VS Code and prerequisite release resolvers, vendor filename validator,
and Office descriptor parser. Fixed endpoints match that module version.
Checks the x64 apps, Firefox Rapid en-US, Office MonthlyEnterprise,
VC++ x86/x64, .NET Runtime 10.0 x86 and Desktop Runtime 10.0 x64.
Does not enumerate USB drives or call staging, sync, cleanup or install commands.
HTTP headers establish reachability, not payload integrity or installation success.
Only the small Office descriptor is downloaded; installers are not saved or read.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-OSDStage-VendorSources.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SourceValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -ne $Object) {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    }
    return $Default
}

function Read-SourceResponse {
    param($Response, $Module, [string]$Extension)
    $null = $Response.EnsureSuccessStatusCode()
    $finalUri = $Response.RequestMessage.RequestUri
    if ($finalUri.Scheme -ne 'https') { throw 'Vendor response did not use HTTPS.' }
    $type = ''
    if ($null -ne $Response.Content.Headers.ContentType) {
        $type = [string]$Response.Content.Headers.ContentType.MediaType
    }
    if ($type -match '(?i)(text/|html|json|xml)') {
        throw "Unexpected payload content type: $type"
    }
    $length = $Response.Content.Headers.ContentLength
    if ($null -ne $length -and $length -le 0) { throw 'Vendor returned an empty payload.' }
    $fileName = & $Module {
        param($Reply, $Suffix)
        Get-OSDStageDownloadFileName -Response $Reply -ExpectedExtension $Suffix
    } $Response $Extension
    [pscustomobject]@{
        FileName = [string]$fileName
        FinalUri = [string]$finalUri.AbsoluteUri
        ContentLength = $length
        ContentType = $type
        ETag = [string]$Response.Headers.ETag
        LastModified = [string]$Response.Content.Headers.LastModified
    }
}

function Get-SourceHeaders {
    param([uri]$Uri, $Module, [string]$Extension)
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 10
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [timespan]::FromSeconds(30)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('OSDStage-SourceCheck/1.0')
    $response = $null
    try {
        # GET headers matches the module's metadata request. Never read the body.
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        Read-SourceResponse -Response $response -Module $Module -Extension $Extension
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
    }
}

function Get-OfficeSourceDescriptor {
    param($Module, [string]$WorkRoot, [uri]$Uri)
    $directory = Join-Path $WorkRoot 'OfficeDescriptor'
    $null = New-Item -ItemType Directory -Path $directory
    $cab = Join-Path $directory 'v64.cab'
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [timespan]::FromSeconds(30)
    $client.MaxResponseContentBufferSize = 1MB
    $null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Cache-Control', 'no-cache')
    $response = $null
    try {
        # Buffered request: timeout and 1 MiB limit also cover the descriptor body.
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        $metadata = Read-SourceResponse -Response $response -Module $Module -Extension '.cab'
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        if ($bytes.Length -eq 0) { throw 'Office descriptor was empty.' }
        [IO.File]::WriteAllBytes($cab, $bytes)
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
    }
    $version = & $Module {
        param($CabPath, $Destination)
        $xml = Expand-OSDStageOfficeDescriptor -CabPath $CabPath -DestinationPath $Destination
        Get-OSDStageOfficeDescriptorVersion -Path $xml -Architecture x64 -ChannelId '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
    } $cab $directory
    [pscustomobject]@{ Version=[string]$version; Metadata=$metadata }
}

function Invoke-SourceCheck {
    param($Case, $Module, [string]$WorkRoot)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $uri = [string]$Case.Uri
    $version = 'Not exposed by metadata'
    $metadata = $null
    $expectedSize = 0L
    $releaseHash = ''
    $status = 'Passed'
    $errorText = ''
    try {
        if ($Case.Kind -eq 'OfficeDescriptor') {
            $office = Get-OfficeSourceDescriptor -Module $Module -WorkRoot $WorkRoot -Uri $uri
            $version = $office.Version
            $metadata = $office.Metadata
        }
        else {
            if ($Case.Kind -ne 'Fixed') {
                $release = & $Module {
                    param($Item)
                    switch ($Item.Kind) {
                        '7Zip' { Get-OSDStage7ZipRelease -Architecture x64 }
                        'VSCode' { Get-OSDStageVisualStudioCodeRelease -Architecture x64 }
                        'VC' {
                            $spec = Get-OSDStagePrerequisiteSpec -Family VisualCRedist -Architecture $Item.Architecture
                            Get-OSDStagePrerequisiteRelease -Spec $spec
                        }
                        'DotNet' {
                            $spec = Get-OSDStagePrerequisiteSpec -Family DotNetRuntime -Architecture $Item.Architecture -RuntimeType $Item.RuntimeType -Channel '10.0'
                            Get-OSDStagePrerequisiteRelease -Spec $spec
                        }
                        default { throw 'Unknown source resolver.' }
                    }
                } $Case
                $uri = [string]$release.PackageUri
                $resolvedVersion = Get-SourceValue $release 'Version'
                if ($resolvedVersion) { $version = [string]$resolvedVersion }
                $expectedSize = [long](Get-SourceValue $release 'Size' 0)
                $releaseHash = [string](Get-SourceValue $release 'Sha256' '')
                if (-not $releaseHash) { $releaseHash = [string](Get-SourceValue $release 'Sha512' '') }
            }
            $metadata = Get-SourceHeaders -Uri $uri -Module $Module -Extension $Case.Extension
            if ($expectedSize -gt 0 -and $null -ne $metadata.ContentLength -and
                $expectedSize -ne [long]$metadata.ContentLength) {
                throw 'Release metadata size differs from the HTTP payload size.'
            }
        }
    }
    catch {
        $status = 'Failed'
        $errorText = $_.Exception.Message
    }
    finally { $watch.Stop() }
    [pscustomobject][ordered]@{
        Id = $Case.Id
        Status = $status
        AdvertisedVersion = $version
        FileName = [string](Get-SourceValue $metadata 'FileName' '')
        SourceUri = $uri
        FinalUri = [string](Get-SourceValue $metadata 'FinalUri' '')
        ContentLength = Get-SourceValue $metadata 'ContentLength'
        ContentType = [string](Get-SourceValue $metadata 'ContentType' '')
        ETag = [string](Get-SourceValue $metadata 'ETag' '')
        LastModified = [string](Get-SourceValue $metadata 'LastModified' '')
        AdvertisedHash = $releaseHash
        PayloadHashVerified = $false
        DurationSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
        Error = $errorText
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        throw 'Run this source check in full Windows on the preparation PC, not in WinPE.'
    }
    $null = Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ('OSDStage-VendorSources-' + [guid]::NewGuid().ToString('N'))
    $moduleRoot = Join-Path $workRoot 'Modules'
    $null = New-Item -ItemType Directory -Path $moduleRoot -Force
    Write-Host '1. Saving OSDStage 0.49.1 to a temporary directory...' -ForegroundColor Cyan
    Save-Module -Name OSDStage -RequiredVersion '0.49.1' -Repository PSGallery -Path $moduleRoot -Force -ErrorAction Stop
    $manifest = Join-Path $moduleRoot 'OSDStage\0.49.1\OSDStage.psd1'
    $moduleInfo = Test-ModuleManifest -Path $manifest -ErrorAction Stop
    if ($moduleInfo.Version -ne [version]'0.49.1') { throw 'Unexpected downloaded module version.' }
    Get-Module OSDStage | Remove-Module -Force
    $modules = @(Import-Module -Name $manifest -Force -PassThru -ErrorAction Stop)
    $matching = @($modules | Where-Object { $_.Name -eq 'OSDStage' })
    if ($matching.Count -ne 1) { throw 'Expected exactly one imported OSDStage module.' }
    $module = $matching[0]
    $expectedBase = [IO.Path]::GetFullPath((Split-Path -Path $manifest -Parent))
    if ([IO.Path]::GetFullPath($module.ModuleBase) -ine $expectedBase) { throw 'The temporary OSDStage module was not loaded.' }

    # Fixed sources are the x64 defaults in OSDStage 0.49.1. No Sync/Add command is called.
    $cases = @(
        @{ Id='Office-ODT-x64'; Kind='Fixed'; Extension='.exe'; Uri='https://officecdn.microsoft.com/pr/wsus/setup.exe' }
        @{ Id='Office-MonthlyEnterprise-x64'; Kind='OfficeDescriptor'; Extension='.cab'; Uri='https://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6/Office/Data/v64.cab' }
        @{ Id='MicrosoftTeams-x64'; Kind='Fixed'; Extension='.msix'; Uri='https://go.microsoft.com/fwlink/?linkid=2196106' }
        @{ Id='MicrosoftTeams-Bootstrapper'; Kind='Fixed'; Extension='.exe'; Uri='https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204' }
        @{ Id='AdobeAcrobatUnified-x64'; Kind='Fixed'; Extension='.zip'; Uri='https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip' }
        @{ Id='GoogleChromeEnterprise-x64'; Kind='Fixed'; Extension='.msi'; Uri='https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' }
        @{ Id='Firefox-Rapid-en-US-x64'; Kind='Fixed'; Extension='.msi'; Uri='https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US' }
        @{ Id='CiscoWebex-x64'; Kind='Fixed'; Extension='.msi'; Uri='https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi' }
        @{ Id='ZoomWorkplace-x64'; Kind='Fixed'; Extension='.msi'; Uri='https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64' }
        @{ Id='7Zip-x64'; Kind='7Zip'; Extension='.exe'; Uri='' }
        @{ Id='VisualStudioCode-x64'; Kind='VSCode'; Extension='.exe'; Uri='' }
        @{ Id='VisualCRedist-x86'; Kind='VC'; Architecture='x86'; Extension='.exe'; Uri='' }
        @{ Id='VisualCRedist-x64'; Kind='VC'; Architecture='x64'; Extension='.exe'; Uri='' }
        @{ Id='DotNet-Runtime-10.0-x86'; Kind='DotNet'; Architecture='x86'; RuntimeType='Runtime'; Extension='.exe'; Uri='' }
        @{ Id='DotNet-Desktop-10.0-x64'; Kind='DotNet'; Architecture='x64'; RuntimeType='Desktop'; Extension='.exe'; Uri='' }
    )
    Write-Host '2. Checking vendor metadata and payload response headers...' -ForegroundColor Cyan
    $results = [Collections.Generic.List[object]]::new()
    foreach ($case in $cases) {
        Write-Host ('   Checking: ' + $case.Id)
        $result = Invoke-SourceCheck -Case $case -Module $module -WorkRoot $workRoot
        $results.Add($result)
        if ($result.Status -eq 'Failed') { Write-Warning ($result.Id + ': ' + $result.Error) }
    }
    $failed = @($results | Where-Object { $_.Status -eq 'Failed' })
    $csvPath = Join-Path $workRoot 'VendorSources.csv'
    $jsonPath = Join-Path $workRoot 'VendorSources.json'
    $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    [ordered]@{
        CheckedAtUtc = [datetime]::UtcNow.ToString('o')
        ModuleVersion = [string]$module.Version
        ModulePath = $module.ModuleBase
        Scope = 'Selected built-in sources: HTTP headers and release metadata only; no installer verification.'
        Checks = @($results.ToArray())
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    Write-Host ''
    $results | Format-Table Id, Status, AdvertisedVersion, FileName -AutoSize -Wrap
    [pscustomobject]@{
        ModuleVersion = [string]$module.Version
        SourceChecks = $results.Count
        Passed = $results.Count - $failed.Count
        Failed = $failed.Count
        CacheWriteOperations = 0
        InstallerDownloads = 0
        ReportDirectory = $workRoot
    } | Format-List
    if ($failed.Count -gt 0) {
        $failed | Format-List Id, SourceUri, FinalUri, Error
        throw 'One or more source checks failed. Send the summary and errors; do not change or clear the cache.'
    }
    Write-Host 'OSDStage VENDOR SOURCE METADATA CHECK PASSED!' -ForegroundColor Green
    Write-Host 'No apps installed, no cache changes, no staging or SetupComplete rerun.'
    Write-Host 'This does not validate installer bytes, signatures, cache health or installation success.'
    Write-Host 'Send the summary back. No deployment or reboot is required.'
}
catch {
    Write-Host ('SOURCE CHECK FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
