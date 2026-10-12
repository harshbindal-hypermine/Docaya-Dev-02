<# Supply the previous immutable release AND its previous target parameter file. No database down-migration. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [switch]$Execute,
    [string]$ReviewedWhatIfFile = ''
)
& "$PSScriptRoot/invoke-release.ps1" -Operation rollback @PSBoundParameters
