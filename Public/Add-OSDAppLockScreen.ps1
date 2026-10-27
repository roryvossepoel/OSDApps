function Add-OSDAppLockScreen {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,Position=0)][Alias('Name')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Id,
        [switch]$Enforce,
        [switch]$SkipCacheRefresh,
        [string]$WindowsPath
    )
    if ($PSCmdlet.ShouldProcess($Id,'Stage LockScreen image for offline Windows')) {
        Save-OSDAppBackground -Kind LockScreen -Id $Id -Enforce:$Enforce -SkipCacheRefresh:$SkipCacheRefresh -WindowsPath $WindowsPath
    }
}
