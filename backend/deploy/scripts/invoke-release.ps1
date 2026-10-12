[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('install', 'upgrade', 'rollback')][string]$Operation,
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [string]$MigrationFile = '',
    [switch]$Execute,
    [string]$ReviewedWhatIfFile = ''
)
. "$PSScriptRoot/common.ps1"
if (-not $Execute) {
    & "$PSScriptRoot/new-plan.ps1" -Operation $Operation -ConfigurationFile $ConfigurationFile -ReleaseDirectory $ReleaseDirectory -MigrationFile $MigrationFile
    return
}
# All local blockers are evaluated before any Azure command or side effect.
$manifest = Assert-Release $ReleaseDirectory
$config = Read-JsonFile $ConfigurationFile
Assert-TargetConfiguration $config
if ($manifest.apiImageDigest -ne $config.apiImageDigest) { throw 'Target image digest differs from the selected release manifest.' }
$targetParameters = Read-JsonFile $config.parameterFile
if ($targetParameters.parameters.releaseVersion.value -ne $manifest.version) { throw 'Target parameter releaseVersion differs from the selected release.' }
if (-not $ReviewedWhatIfFile -or -not (Test-Path -LiteralPath $ReviewedWhatIfFile -PathType Leaf) -or (Get-Item -LiteralPath $ReviewedWhatIfFile).Length -eq 0) {
    throw 'Supply the non-empty what-if evidence reviewed for this exact release and target.'
}
if ($Operation -eq 'rollback' -and -not $config.rollbackCompatibleDatabase) { throw 'Rollback requires confirmed database backward compatibility.' }
if ($Operation -eq 'upgrade' -and $MigrationFile -and -not (Test-Path -LiteralPath $MigrationFile -PathType Leaf)) { throw 'Migration file does not exist.' }
foreach ($tool in @('az', 'swa')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required tool not installed: $tool" } }
if ($Operation -eq 'install' -or $MigrationFile) {
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { throw 'Install sqlcmd before database migration.' }
}
Assert-AzureContext $config
# Pre-existing image is deliberate: current Bicep cannot bootstrap its own empty registry.
Invoke-Checked az @('acr', 'repository', 'show', '--name', $config.registryName, '--image', "docaya-api@$($config.apiImageDigest)", '--output', 'none', '--only-show-errors')
$deploymentName = "docaya-$Operation-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
Invoke-Checked az @('deployment', 'sub', 'create', '--name', $deploymentName, '--location', $config.location, '--template-file', (Join-Path $ReleaseDirectory 'infra/main.json'), '--parameters', "@$($config.parameterFile)", '--output', 'none', '--only-show-errors')
if ($Operation -eq 'install') {
    & "$PSScriptRoot/migrate-database.ps1" -ConfigurationFile $ConfigurationFile -SqlDirectory (Join-Path $ReleaseDirectory 'sql') -Execute
} elseif ($Operation -eq 'upgrade' -and $MigrationFile) {
    & "$PSScriptRoot/migrate-database.ps1" -ConfigurationFile $ConfigurationFile -MigrationFile $MigrationFile -Execute
}
Invoke-Checked az @('functionapp', 'deployment', 'source', 'config-zip', '--resource-group', $config.resourceGroupName, '--name', $config.functionAppName, '--src', (Join-Path $ReleaseDirectory 'functions.zip'), '--build-remote', 'false', '--output', 'none', '--only-show-errors')
Invoke-Checked swa @('deploy', (Join-Path $ReleaseDirectory 'web'), '--app-name', $config.staticWebAppName, '--resource-group', $config.resourceGroupName, '--subscription-id', $config.subscriptionId, '--tenant-id', $config.tenantId, '--env', 'production')
& "$PSScriptRoot/validate.ps1" -ConfigurationFile $ConfigurationFile -ReleaseDirectory $ReleaseDirectory -Online
Write-Host "Release $($manifest.version) completed; deployment $deploymentName."
