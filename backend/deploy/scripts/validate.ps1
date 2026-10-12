<# Local integrity checks by default. -Online performs read-only Azure/HTTP checks. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationFile,
    [Parameter(Mandatory)][string]$ReleaseDirectory,
    [switch]$Online
)
. "$PSScriptRoot/common.ps1"
$manifest = Assert-Release $ReleaseDirectory
Write-Host "Local integrity/readiness checks passed for candidate $($manifest.version)."
if (-not $Online) { return }
$config = Read-JsonFile $ConfigurationFile
Assert-TargetConfiguration $config
Assert-AzureContext $config
& (Join-Path $ReleaseDirectory 'infra/tests/validate-deployment.ps1') -ResourceGroupName $config.resourceGroupName -Environment $config.environment
$response = Invoke-WebRequest -Uri ($config.publicBaseUrl.TrimEnd('/') + '/') -UseBasicParsing -TimeoutSec 30
if ($response.StatusCode -ne 200) { throw 'Public web check failed.' }
foreach ($endpoint in @('/health/live', '/health/ready')) {
    $health = Invoke-RestMethod -Uri ($config.apiBaseUrl.TrimEnd('/') + $endpoint) -TimeoutSec 30
    if ($health.status -ne 'healthy') { throw "API $endpoint returned an unhealthy status." }
}
Write-Host 'Resource and health checks passed. Connected synthetic lifecycle/security tests remain a separate release gate.'
