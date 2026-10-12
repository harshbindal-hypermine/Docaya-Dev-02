[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [switch]$Execute,
    [string]$ReviewedWhatIfFile = ''
)
& "$PSScriptRoot/invoke-release.ps1" -Operation install @PSBoundParameters
