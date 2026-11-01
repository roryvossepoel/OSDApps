function global:Set-OSDStageTestPayloadInfo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Id,
        [string]$Architecture = 'x64',
        [hashtable]$Metadata = @{}
    )
    $payload = Get-Item -LiteralPath $Path -ErrorAction Stop
    $record = [ordered]@{Id=$Id;Architecture=$Architecture;Version='1.0.0';Cached=$true}
    foreach ($key in $Metadata.Keys) { $record[$key] = $Metadata[$key] }
    $record.PayloadFileName = $payload.Name
    $record.Sha256 = (Get-FileHash -LiteralPath $payload.FullName -Algorithm SHA256).Hash
    $record.Size = $payload.Length
    $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $payload.DirectoryName 'CacheInfo.json') -Encoding UTF8
}
