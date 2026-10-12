<#
.SYNOPSIS
    Previews an infrastructure change without applying it.

.DESCRIPTION
    Technical Architecture Document v1.3, Section 18.5:
    "Preview - az deployment sub what-if - Reviewed and approved by a named person
     before any environment change."

    Section 17.3 requires this script to exist before any deployment is attempted.

.PARAMETER Environment
    Environment short name: dev, test or prod.

.PARAMETER Location
    Azure region. Defaults to the approved UAE primary region.

.EXAMPLE
    pwsh -File infra/scripts/what-if.ps1 -Environment dev
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

if (-not (Test-Path $templateFile)) {
    throw "Template not found: $templateFile"
}

if (-not (Test-Path $parameterFile)) {
    throw "Parameter file not found: $parameterFile"
}

Write-Host "Compiling $templateFile" -ForegroundColor Cyan
az bicep build --file $templateFile --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }

Write-Host "Previewing '$Environment' in $Location" -ForegroundColor Cyan
Write-Host 'Review this output with a named approver before deploying.' -ForegroundColor Yellow

az deployment sub what-if `
    --location $Location `
    --template-file $templateFile `
    --parameters $parameterFile

if ($LASTEXITCODE -ne 0) { throw 'what-if failed.' }
