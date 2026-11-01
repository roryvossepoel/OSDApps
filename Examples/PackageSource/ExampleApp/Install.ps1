[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Replace this example with the app's unattended installation.
# Package.zip must contain this script at:
#
# Package/
# ├── Install.ps1
# └── <payload>
#
# Return a normal process exit code or throw when installation fails.

Write-Output 'Example OSDStage package.'
exit 0
