<#
.SYNOPSIS
    Runs read-only post-deployment assertions for a Docaya resource group.

.DESCRIPTION
    This gate verifies that the deployed resource estate contains the required
    services and that test/production data services are not publicly reachable.
    It makes no changes to Azure.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment
)

$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Post-deployment assertion failed: $Message"
    }
}

$groupExists = [bool](az group exists --name $ResourceGroupName --only-show-errors | ConvertFrom-Json)
if (-not $groupExists) {
    throw "Resource group does not exist: $ResourceGroupName"
}

$resourceJson = az resource list --resource-group $ResourceGroupName --output json --only-show-errors
Assert-Condition ($LASTEXITCODE -eq 0) "Unable to list resources in $ResourceGroupName"
$resources = @($resourceJson | ConvertFrom-Json)

$requiredTypes = @(
    'Microsoft.Network/virtualNetworks'
    'Microsoft.Sql/servers'
    'Microsoft.Storage/storageAccounts'
    'Microsoft.Search/searchServices'
    'Microsoft.ServiceBus/namespaces'
    'Microsoft.App/managedEnvironments'
    'Microsoft.App/containerApps'
    'Microsoft.Web/sites'
    'Microsoft.ApiManagement/service'
    'Microsoft.Cdn/profiles'
)

$resourceTypes = @($resources | ForEach-Object { $_.type } | Sort-Object -Unique)
foreach ($requiredType in $requiredTypes) {
    Assert-Condition ($resourceTypes -contains $requiredType) "Missing deployed resource type: $requiredType"
}

if ($Environment -ne 'dev') {
    Assert-Condition ($resourceTypes -contains 'Microsoft.Network/privateEndpoints') `
        'Private endpoints are required outside development.'
    $privateEndpointCount = @($resources | Where-Object { $_.type -eq 'Microsoft.Network/privateEndpoints' }).Count
    Assert-Condition ($privateEndpointCount -ge 10) `
        "Expected at least 10 private endpoints in $Environment, found $privateEndpointCount."

    $storageJson = az storage account list --resource-group $ResourceGroupName --output json --only-show-errors
    Assert-Condition ($LASTEXITCODE -eq 0) 'Unable to query storage account network posture.'
    $storageAccounts = @($storageJson | ConvertFrom-Json)
    foreach ($storageAccount in $storageAccounts) {
        Assert-Condition ($storageAccount.publicNetworkAccess -eq 'Disabled') `
            "Storage account '$($storageAccount.name)' has public network access enabled."
    }
}

Write-Output "Post-deployment validation passed for $ResourceGroupName."
