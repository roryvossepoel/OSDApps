[CmdletBinding()]
param([string]$ConfigPath)

function ConvertTo-OSDAppDefaultAssociations {
    param([Parameter(Mandatory)][object[]]$Associations)
    if ($Associations.Count -eq 0 -or $Associations.Count -gt 2048) { throw 'Specify 1 to 2048 default associations.' }
    $seen=@{}
    foreach ($item in $Associations) {
        if ($null -eq $item) { throw 'An association cannot be null.' }
        $id=$item.Identifier;$progId=$item.ProgId;$name=$item.AppName
        if ($id -isnot [string] -or $id -notmatch '^(?:\.[\p{L}\p{N}][\p{L}\p{N}._+-]{0,253}|[A-Za-z][A-Za-z0-9+.-]{0,254})$') {
            throw 'Identifier must be a file extension including its dot, or a URI scheme without a colon.'
        }
        if ($progId -isnot [string] -or $progId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,511}$') { throw 'ProgId must be a literal registered Windows handler ID, not an executable path or command.' }
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 512 -or $name -ne $name.Trim() -or $name -match '[\x00-\x1F]') { throw 'AppName must be nonempty display text of at most 512 characters without control characters.' }
        $null=[Xml.XmlConvert]::VerifyXmlChars($name)
        if ($seen.ContainsKey($id)) { throw ('Duplicate association identifier: ' + $id) }
        $seen[$id]=$true
        [pscustomobject]@{Identifier=$id.ToLowerInvariant();ProgId=$progId;AppName=$name}
    }
}

function Read-OSDAppDefaultAssociationsXml {
    param([Parameter(Mandatory)][string]$Path)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 1MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Association XML must be a regular file no larger than 1 MiB.' }
    $settings=[Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=1MB
    $reader=[Xml.XmlReader]::Create($file.FullName,$settings)
    try { $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader) } finally { $reader.Dispose() }
    $root=$doc.DocumentElement
    if ($null -eq $root -or $root.Name -cne 'DefaultAssociations' -or $root.NamespaceURI -ne '' -or $root.Attributes.Count -ne 0) {
        throw 'Expected DefaultAssociations without namespaces or policy attributes. Version and Suggested policy XML are not supported by this initial-default import.'
    }
    $items=@(foreach ($node in $root.ChildNodes) {
        if ($node.NodeType -in @([Xml.XmlNodeType]::Comment,[Xml.XmlNodeType]::Whitespace,[Xml.XmlNodeType]::SignificantWhitespace)) { continue }
        if ($node.NodeType -ne [Xml.XmlNodeType]::Element -or $node.Name -cne 'Association' -or $node.HasChildNodes -or $node.Attributes.Count -ne 3) { throw 'Only empty Association elements with Identifier, ProgId and ApplicationName are supported.' }
        foreach ($attribute in $node.Attributes) {
            if ($attribute.Name -cnotin @('Identifier','ProgId','ApplicationName')) { throw ('Unsupported association attribute: ' + $attribute.Name) }
        }
        [pscustomobject]@{Identifier=$node.GetAttribute('Identifier');ProgId=$node.GetAttribute('ProgId');AppName=$node.GetAttribute('ApplicationName')}
    })
    ConvertTo-OSDAppDefaultAssociations -Associations $items
}

function ConvertTo-OSDAppDefaultAssociationsXml {
    param([Parameter(Mandatory)][object[]]$Associations)
    $items=@(ConvertTo-OSDAppDefaultAssociations -Associations $Associations)
    $builder=[Text.StringBuilder]::new()
    $settings=[Xml.XmlWriterSettings]::new();$settings.OmitXmlDeclaration=$true;$settings.Indent=$true
    $writer=[Xml.XmlWriter]::Create($builder,$settings)
    try {
        $writer.WriteStartElement('DefaultAssociations')
        foreach ($item in $items) {
            $writer.WriteStartElement('Association')
            $writer.WriteAttributeString('Identifier',$item.Identifier)
            $writer.WriteAttributeString('ProgId',$item.ProgId)
            $writer.WriteAttributeString('ApplicationName',$item.AppName)
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement();$writer.Flush()
        $builder.ToString()
    }
    finally { $writer.Dispose() }
}

function Merge-OSDAppDefaultAssociations {
    param([object[]]$Baseline=@(),[Parameter(Mandatory)][object[]]$Overrides)
    $result=@()
    if ($Baseline.Count) { $result=@(ConvertTo-OSDAppDefaultAssociations -Associations $Baseline) }
    $updates=@(ConvertTo-OSDAppDefaultAssociations -Associations $Overrides)
    foreach ($item in $updates) {
        $result=@($result | Where-Object Identifier -ine $item.Identifier) + @($item)
    }
    ConvertTo-OSDAppDefaultAssociations -Associations $result
}

function Assert-OSDAppDefaultAssociationConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id=[guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 1 -or -not [guid]::TryParse([string]$Configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or $Configuration.Associations -isnot [System.Collections.IList]) { throw 'Invalid default associations configuration.' }
    $null=@(ConvertTo-OSDAppDefaultAssociations -Associations @($Configuration.Associations))
}

function Assert-OSDAppDefaultAssociationContext {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Default associations runtime requires full Windows.' }
    if (-not [Environment]::Is64BitProcess -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { throw 'Default associations runtime requires native 64-bit PowerShell running as SYSTEM during SetupComplete.' }
    $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    if ($cv.InstallationType -ne 'Client' -or [int]$cv.CurrentBuildNumber -lt 22000) { throw 'This initial-default implementation requires Windows 11 client.' }
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\ApplicationDefaults')) {
        if (Test-Path -LiteralPath $path) {
            $policy=Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace([string]$policy.DefaultAssociationsConfiguration)) { throw 'An existing default-associations policy can override initial defaults. Resolve that policy before this import.' }
        }
    }
}

function Invoke-OSDAppAssociationDism {
    param(
        [Parameter(Mandatory)][ValidateSet('Export','Import')][string]$Action,
        [Parameter(Mandatory)][string]$XmlPath,
        [Parameter(Mandatory)][string]$LogPath,
        [ValidateRange(1,600)][int]$TimeoutSeconds=300
    )
    foreach ($path in @($XmlPath,$LogPath)) {
        if (-not [IO.Path]::IsPathRooted($path) -or $path -match '["\x00-\x1F]' -or $path.EndsWith('\')) { throw 'DISM paths must be absolute file paths without quotes or control characters.' }
    }
    $arguments='/Online /{0}-DefaultAppAssociations:"{1}" /NoRestart /English /LogPath:"{2}"' -f $Action,$XmlPath,$LogPath
    $process=[Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName=Join-Path $env:SystemRoot 'System32\dism.exe'
        $process.StartInfo.Arguments=$arguments
        $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
        if (-not $process.Start()) { throw 'Unable to start DISM.' }
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) {
            $process.Kill();$null=$process.WaitForExit(5000)
            throw 'DISM timed out. Servicing may already have changed the image; no rollback, retry or reboot is requested.'
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'DISM output capture timed out; no retry is requested.' }
        [pscustomobject]@{Action=$Action;ExitCode=$process.ExitCode;StandardOutput=$stdout.Result;StandardError=$stderr.Result;LogPath=$LogPath}
    }
    finally { $process.Dispose() }
}

function Invoke-OSDAppDefaultAssociationConfiguration {
    param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][string]$WorkDirectory)
    Assert-OSDAppDefaultAssociationConfiguration -Configuration $Configuration
    $record=[ordered]@{
        SchemaVersion=1;DeploymentId=[string]$Configuration.DeploymentId;Status='Failed';Outcome='Failed'
        RequestedCount=@($Configuration.Associations).Count;BaselineCount=0;ImportedCount=0
        Export=$null;Import=$null;RestartNeeded=$false;RebootRequested=$false;UserDefaultsVerified=$false
        Associations=@($Configuration.Associations);Error=$null
    }
    try {
        Assert-OSDAppDefaultAssociationContext
        # All files belong to this single attempt; never reuse an earlier export after a failed command.
        $attempt=Join-Path $WorkDirectory ('Attempt-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $attempt -ErrorAction Stop | Out-Null
        $baselinePath=Join-Path $attempt 'Baseline.xml'
        $mergedPath=Join-Path $attempt 'Merged.xml'
        $record.Export=Invoke-OSDAppAssociationDism -Action Export -XmlPath $baselinePath -LogPath (Join-Path $attempt 'Export.log')
        if ($record.Export.ExitCode -ne 0) { throw ('DISM baseline export failed with exit code {0}; import was not attempted.' -f $record.Export.ExitCode) }
        $baseline=@(Read-OSDAppDefaultAssociationsXml -Path $baselinePath)
        $record.BaselineCount=$baseline.Count
        $merged=@(Merge-OSDAppDefaultAssociations -Baseline $baseline -Overrides @($Configuration.Associations))
        [IO.File]::WriteAllText($mergedPath,(ConvertTo-OSDAppDefaultAssociationsXml -Associations $merged),[Text.UTF8Encoding]::new($false))
        $record.Import=Invoke-OSDAppAssociationDism -Action Import -XmlPath $mergedPath -LogPath (Join-Path $attempt 'Import.log')
        if ($record.Import.ExitCode -notin @(0,3010)) { throw ('DISM association import failed with exit code {0}; no retry or rollback is requested.' -f $record.Import.ExitCode) }
        $record.ImportedCount=$merged.Count
        $record.RestartNeeded=($record.Import.ExitCode -eq 3010)
        $record.Status='Succeeded';$record.Outcome='ImportedForFirstSignIn'
    }
    catch { $record.Error=$_.Exception.Message }
    [pscustomobject]$record
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference='Stop'
try {
    if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot 'config.json' }
    $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $record=Invoke-OSDAppDefaultAssociationConfiguration -Configuration $configuration -WorkDirectory $PSScriptRoot
    $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force -ErrorAction Stop | Out-Null
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -ErrorAction Stop
    if ($record.Status -eq 'Failed') { Write-Error $record.Error -ErrorAction Continue;exit 1 }
    if ($record.RestartNeeded) { exit 3010 }
    exit 0
}
catch { Write-Error $_.Exception.Message -ErrorAction Continue;exit 1 }
