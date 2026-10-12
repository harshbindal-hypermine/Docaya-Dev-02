<#
.SYNOPSIS
    Deploys the Docaya estate to an environment.

.DESCRIPTION
    Technical Architecture Document v1.3, Section 18.5:
    "Deploy - az deployment sub create with the environment parameter file - Release
     pipeline under workload identity federation."

    A what-if preview must have been reviewed and approved by a named person before
    this script is run against any environment.

.PARAMETER Environment
    Environment short name: dev, test or prod.

.PARAMETER ApiImageDigest
    Immutable image digest, for example sha256:abc... A floating tag such as 'latest'
    is prohibited by release policy: the digest is what makes rollback deterministic.

.PARAMETER Location
    Azure region. Defaults to the approved UAE primary region.

.EXAMPLE
    pwsh -File infra/scripts/deploy.ps1 -Environment dev -ApiImageDigest sha256:abc123...
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^sha256:[a-f0-9]{64}$')]
    [string]$ApiImageDigest,

    [Parameter()]
    [string]$Location = 'uaenorth'
)

$ErrorActionPreference = 'Stop'

$infraRoot = Split-Path -Parent $PSScriptRoot
$templateFile = Join-Path $infraRoot 'main.bicep'
$parameterFile = Join-Path $infraRoot "environments/$Environment.bicepparam"

if (-not (Test-Path $parameterFile)) {
    throw "Parameter file not found: $parameterFile"
}

$deploymentName = "docaya-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "Deploying '$Environment' as $deploymentName" -ForegroundColor Cyan
Write-Host "Image digest: $ApiImageDigest" -ForegroundColor Cyan

az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $templateFile `
    --parameters $parameterFile `
    --parameters apiImageDigest=$ApiImageDigest

if ($LASTEXITCODE -ne 0) { throw 'Deployment failed.' }

$resourceGroupName = "rg-docaya-$Environment-$Location"
& (Join-Path $infraRoot 'tests\validate-deployment.ps1') `
    -ResourceGroupName $resourceGroupName `
    -Environment $Environment

if ($LASTEXITCODE -ne 0) { throw 'Post-deployment validation failed.' }

Write-Host 'Deployment and post-deployment validation complete.' -ForegroundColor Green
