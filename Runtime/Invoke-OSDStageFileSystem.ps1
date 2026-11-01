[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

function Assert-OSDStageFileSystemPath {
    param([Parameter(Mandatory)][string]$Path)
    # Destination syntax is checked in WinPE, but variables are expanded only in Windows.
    $pathText = $Path.Replace('/', '\')
    if ($pathText -notmatch '^(?:[A-Za-z]:\\|%(?:SystemDrive|SystemRoot|windir|ProgramData|ProgramFiles|ProgramFiles\(x86\))%\\).+' -or
        $pathText -match '[*?"<>|\x00-\x1f]' -or $pathText -ne $pathText.Trim()) {
        throw 'Use a literal local absolute path or a supported machine directory variable; roots and wildcards are not allowed.'
    }
    $tail = $pathText -replace '^(?:[A-Za-z]:\\|%[^%]+%\\)', ''
    if ($tail.Contains(':') -or $tail.Contains('%')) { throw 'Alternate data streams and embedded environment variables are not supported.' }
    foreach ($part in $tail.TrimEnd('\').Split('\')) {
        if (-not $part -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'Empty, relative, trailing-dot/space and reserved device path components are not supported.'
        }
    }
}

function Assert-OSDStageFileSystemOperation {
    param([Parameter(Mandatory)]$Operation)
    if ([string]$Operation.Kind -notin @('Directory','File') -or [string]$Operation.Action -notin @('Create','Remove')) { throw 'Invalid file system operation.' }
    Assert-OSDStageFileSystemPath -Path ([string]$Operation.Path)
    if ($Operation.Force -isnot [bool] -or $Operation.Recurse -isnot [bool]) { throw 'Force and Recurse must be Boolean values.' }
    if ($Operation.Recurse -and ($Operation.Kind -ne 'Directory' -or $Operation.Action -ne 'Remove')) { throw 'Recurse is only valid when removing a directory.' }
    if ($Operation.Kind -eq 'File' -and $Operation.Action -eq 'Create') {
        if ($Operation.Data -isnot [string] -or $Operation.Data.Length -gt 22369624) { throw 'File content is limited to 16 MiB per operation.' }
        $bytes = [Convert]::FromBase64String($Operation.Data)
        if ($bytes.Length -gt 16MB) { throw 'File content is limited to 16 MiB per operation.' }
    }
}

function Assert-OSDStageFileSystemConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id = [guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 2 -or
        -not [guid]::TryParse([string]$Configuration.DeploymentId, [ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or
        @($Configuration.Operations).Count -eq 0) { throw 'Invalid file system configuration.' }
    foreach ($operation in @($Configuration.Operations)) { Assert-OSDStageFileSystemOperation -Operation $operation }
}

function Resolve-OSDStageFileSystemPath {
    param([Parameter(Mandatory)][string]$Path)
    Assert-OSDStageFileSystemPath -Path $Path
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Replace('/', '\'))
    if ($expanded.Contains('%') -or $expanded -notmatch '^[A-Za-z]:\\') { throw 'Destination could not be resolved to a local Windows drive.' }
    $resolved = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    # Do not allow a file operation to destroy OS roots or this deployment's own data.
    $roots = @($env:windir, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)})
    if ($env:SystemDrive) { $roots += "$env:SystemDrive\Users" }
    foreach ($root in $roots) {
        if ($root -and [string]::Equals($resolved, $root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'A protected system directory cannot be targeted.' }
    }
    foreach ($owned in @("$env:windir\Temp\OSDStage", "$env:ProgramData\OSDStage", "$env:windir\Setup\Scripts")) {
        if ($resolved -ieq $owned -or $resolved.StartsWith($owned + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $owned.StartsWith($resolved + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'A deployment directory or its ancestor cannot be targeted.' }
    }
    return $resolved
}

function Assert-OSDStageFileSystemNoLink {
    param([Parameter(Mandatory)][string]$Path)
    $current = $Path
    while ($current) {
        try { $attributes = [IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException] { $attributes = $null }
        catch [IO.DirectoryNotFoundException] { $attributes = $null }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse points, junctions and symbolic links are not supported.' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-OSDStageFileSystemTree {
    param([Parameter(Mandatory)][string]$Path)
    # Enumerate one level at a time, refusing links before descending.
    foreach ($child in [IO.Directory]::GetFileSystemEntries($Path)) {
        $attributes = [IO.File]::GetAttributes($child)
        if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The directory contains a reparse point; nothing was removed.' }
        if ($attributes -band [IO.FileAttributes]::Directory) { Get-OSDStageFileSystemTree -Path $child }
        $child
    }
}

function Invoke-OSDStageFileSystemOperation {
    param([Parameter(Mandatory)]$Operation)
    Assert-OSDStageFileSystemOperation -Operation $Operation
    $path = Resolve-OSDStageFileSystemPath -Path $Operation.Path
    Assert-OSDStageFileSystemNoLink -Path $path
    $isFile = [IO.File]::Exists($path)
    $isDirectory = [IO.Directory]::Exists($path)
    if (($Operation.Kind -eq 'File' -and $isDirectory) -or ($Operation.Kind -eq 'Directory' -and $isFile)) { throw 'The destination exists with a different item type.' }
    $outcome = 'Unchanged'
    if ($Operation.Action -eq 'Remove') {
        if (-not $isFile -and -not $isDirectory) { $outcome = 'AlreadyAbsent' }
        else {
            $children = @()
            if ($isDirectory) {
                if (-not $Operation.Recurse -and [IO.Directory]::GetFileSystemEntries($path).Length -gt 0) { throw 'A nonempty directory requires Recurse.' }
                if ($Operation.Recurse) { $children = @(Get-OSDStageFileSystemTree -Path $path) }
            }
            $targets = @($children) + @($path)
            # Validate the whole tree before changing attributes or removing anything.
            foreach ($item in $targets) {
                if (-not $Operation.Force -and ([IO.File]::GetAttributes($item) -band [IO.FileAttributes]::ReadOnly)) { throw 'A read-only item requires Force.' }
            }
            foreach ($item in $targets) {
                Assert-OSDStageFileSystemNoLink -Path $item
                $attributes = [IO.File]::GetAttributes($item)
                if ($Operation.Force) { [IO.File]::SetAttributes($item, ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly))) }
                if ($attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($item, $false) }
                else { [IO.File]::Delete($item) }
            }
            $outcome = 'Removed'
        }
    }
    elseif ($Operation.Kind -eq 'Directory') {
        if (-not $isDirectory) { [IO.Directory]::CreateDirectory($path) | Out-Null; $outcome = 'Created' }
    }
    else {
        $bytes = [Convert]::FromBase64String([string]$Operation.Data)
        $same = $false
        if ($isFile) {
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $stream = [IO.File]::OpenRead($path)
                try { $before = [Convert]::ToBase64String($sha.ComputeHash($stream)) } finally { $stream.Dispose() }
                $same = $before -ceq [Convert]::ToBase64String($sha.ComputeHash($bytes))
            } finally { $sha.Dispose() }
            if (-not $same -and -not $Operation.Force) { throw 'Different file content already exists; use Force to overwrite.' }
        }
        if (-not $same) {
            $parent = [IO.Path]::GetDirectoryName($path)
            [IO.Directory]::CreateDirectory($parent) | Out-Null
            $temp = Join-Path $parent ('.osdstage-' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                [IO.File]::WriteAllBytes($temp, $bytes)
                Assert-OSDStageFileSystemNoLink -Path $path
                if ($isFile) {
                    $attributes = [IO.File]::GetAttributes($path)
                    [IO.File]::SetAttributes($path, ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
                    try { [IO.File]::Replace($temp, $path, [NullString]::Value) }
                    finally { if ([IO.File]::Exists($path)) { [IO.File]::SetAttributes($path, $attributes) } }
                    $outcome = 'Replaced'
                }
                else { [IO.File]::Move($temp, $path); $outcome = 'Created' }
            }
            finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
        }
    }
    [pscustomobject]@{Kind=[string]$Operation.Kind;Action=[string]$Operation.Action;Path=$path;Status='Succeeded';Outcome=$outcome;Error=$null}
}

function Invoke-OSDStageFileSystemConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    Assert-OSDStageFileSystemConfiguration -Configuration $Configuration
    # Reject unresolved/protected destinations before the first operation.
    foreach ($op in @($Configuration.Operations)) { Resolve-OSDStageFileSystemPath -Path $op.Path | Out-Null }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($op in @($Configuration.Operations)) {
        try { $items.Add((Invoke-OSDStageFileSystemOperation -Operation $op)) }
        catch {
            $items.Add([pscustomobject]@{Kind=[string]$op.Kind;Action=[string]$op.Action;Path=[string]$op.Path;Status='Failed';Outcome='Failed';Error=$_.Exception.Message})
        }
    }
    $failed = @($items | Where-Object Status -eq 'Failed').Count
    [pscustomobject]@{
        SchemaVersion=2;DeploymentId=[string]$Configuration.DeploymentId;Status=if($failed){'Failed'}else{'Succeeded'}
        OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed);FailedOperationCount=$failed
        RestartNeeded=$false;RebootRequested=$false;Items=@($items);Error=if($failed){"$failed file system operation(s) failed."}else{$null}
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
try {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'File system runtime requires full Windows.' }
    $configuration = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $record = Invoke-OSDStageFileSystemConfiguration -Configuration $configuration
    $resultPath = [Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if ($record.Status -eq 'Failed') { exit 1 }
    exit 0
}
catch { Write-Error 'File system configuration failed; no file content is included in this diagnostic.' -ErrorAction Continue; exit 1 }
