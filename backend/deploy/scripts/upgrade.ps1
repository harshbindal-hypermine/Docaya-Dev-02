[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [string]$MigrationFile = '',
    [switch]$Execute,
    [string]$ReviewedWhatIfFile = ''
)
& "$PSScriptRoot/invoke-release.ps1" -Operation upgrade @PSBoundParameters
