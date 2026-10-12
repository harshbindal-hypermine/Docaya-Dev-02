<#
.SYNOPSIS
    Detects configuration drift in a deployed environment.

.DESCRIPTION
    Technical Architecture Document v1.3, Section 18.5:
    "Drift detection - Scheduled what-if against the deployed environment; unexpected
     drift raises an alert."

    Intended to run on a schedule. A non-zero exit means the deployed estate no longer
    matches the template and must be investigated.

.PARAMETER Environment
    Environment short name: dev, test or prod.

.PARAMETER Location
    Azure region. Defaults to the approved UAE primary region.

.EXAMPLE
    pwsh -File infra/scripts/drift-detect.ps1 -Environment prod
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter()]
    [string]$Location = 'uaenorth'
)

$ErrorActionPreference = 'Stop'

$infraRoot = Split-Path -Parent $PSScriptRoot
$templateFile = Join-Path $infraRoot 'main.bicep'
$parameterFile = Join-Path $infraRoot "environments/$Environment.bicepparam"

Write-Host "Checking '$Environment' for drift" -ForegroundColor Cyan

$result = az deployment sub what-if `
    --location $Location `
    --template-file $templateFile `
    --parameters $parameterFile `
    --no-pretty-print | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw 'Drift check failed to run.' }

# Ignore and NoChange are expected. Anything else is drift.
$drifted = $result.changes | Where-Object { $_.changeType -notin @('Ignore', 'NoChange') }

if ($drifted) {
    Write-Host "Drift detected in '$Environment':" -ForegroundColor Red
    foreach ($change in $drifted) {
        Write-Host "  [$($change.changeType)] $($change.resourceId)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "No drift detected in '$Environment'." -ForegroundColor Green
