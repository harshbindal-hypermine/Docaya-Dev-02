<#
.SYNOPSIS
    Validates the compiled Docaya infrastructure template without deploying it.

.DESCRIPTION
    This is the blocking template-unit-test gate described by TAD 18.5. It
    compiles the complete Bicep module graph, verifies the required Azure
    resource types are present, and checks the security-sensitive source
    invariants that cannot be evaluated from an unbound ARM expression.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TemplateFile = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($TemplateFile)) {
    $TemplateFile = Join-Path $PSScriptRoot '..\main.bicep'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Infrastructure assertion failed: $Message"
    }
}

function Get-ResourceNodes {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Container
    )

    if ($null -eq $Container) {
        return
    }

    foreach ($property in $Container.PSObject.Properties) {
        $value = $property.Value
        if ($null -eq $value) {
            continue
        }

        $propertyNames = @($value.PSObject.Properties.Name)
        if ($propertyNames -contains 'type') {
            Write-Output $value

            if ($null -ne $value.resources) {
                Get-ResourceNodes -Container $value.resources
            }

            if ($null -ne $value.properties -and
                $null -ne $value.properties.template -and
                $null -ne $value.properties.template.resources) {
                Get-ResourceNodes -Container $value.properties.template.resources
            }
        }
    }
}

$templateFile = [IO.Path]::GetFullPath($TemplateFile)
Assert-Condition (Test-Path $templateFile) "Bicep file was not found: $templateFile"

$compiledFile = Join-Path ([IO.Path]::GetTempPath()) "docaya-infra-$PID.json"
$diagnosticsFile = Join-Path ([IO.Path]::GetTempPath()) "docaya-infra-$PID.log"

try {
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & az bicep build --file $templateFile --outfile $compiledFile 2> $diagnosticsFile
    $bicepExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference
    Assert-Condition ($bicepExitCode -eq 0) "Bicep compilation failed. See $diagnosticsFile"

    $template = Get-Content -Path $compiledFile -Raw | ConvertFrom-Json
    $resources = @(Get-ResourceNodes -Container $template.resources)
    Assert-Condition ($resources.Count -gt 0) 'The compiled template contains no resources.'

    $requiredTypes = @(
        'Microsoft.Network/virtualNetworks'
        'Microsoft.Network/privateEndpoints'
        'Microsoft.ManagedIdentity/userAssignedIdentities'
        'Microsoft.Sql/servers'
        'Microsoft.Storage/storageAccounts'
        'Microsoft.Search/searchServices'
        'Microsoft.ServiceBus/namespaces'
        'Microsoft.App/managedEnvironments'
        'Microsoft.App/containerApps'
        'Microsoft.Web/sites'
        'Microsoft.ApiManagement/service'
        'Microsoft.Cdn/profiles'
        'Microsoft.Authorization/roleAssignments'
        'Microsoft.Authorization/policyAssignments'
    )

    $resourceTypes = @($resources | ForEach-Object { $_.type } | Sort-Object -Unique)
    foreach ($requiredType in $requiredTypes) {
        Assert-Condition ($resourceTypes -contains $requiredType) "Required resource type is missing: $requiredType"
    }

    $infraRoot = Split-Path -Parent $templateFile
    $functionsSource = Get-Content (Join-Path $infraRoot 'modules\functions.bicep') -Raw
    $containerAppSource = Get-Content (Join-Path $infraRoot 'modules\containerapp.bicep') -Raw
    $serviceBusSource = Get-Content (Join-Path $infraRoot 'modules\servicebus.bicep') -Raw

    Assert-Condition ([regex]::Matches($functionsSource, 'resource taskHub.*PrivateEndpoint').Count -eq 4) `
        'The Durable task hub must have Blob, File, Queue and Table private endpoints.'
    Assert-Condition ($functionsSource.Contains("publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'")) `
        'Task-hub storage public network access must follow the environment posture.'
    Assert-Condition ($functionsSource.Contains("defaultAction: privateEndpointsEnabled ? 'Deny' : 'Allow'")) `
        'Task-hub storage network ACLs must deny public traffic when private endpoints are enabled.'
    Assert-Condition ($containerAppSource.Contains('@${apiImageDigest}')) `
        'The API container image must be addressed by immutable digest.'
    Assert-Condition (-not $serviceBusSource.Contains('useePremium')) `
        'The Service Bus premium-tier variable contains a stale misspelling.'

    $orphanModules = @(
        'container-app.bicep'
        'networking.bicep'
        'postgresql.bicep'
        'redis.bicep'
        'security.bicep'
        'service-bus.bicep'
    )
    foreach ($orphanModule in $orphanModules) {
        Assert-Condition (-not (Test-Path (Join-Path $infraRoot "modules\$orphanModule"))) `
            "Orphan module must not be present: $orphanModule"
    }

    Write-Output "Infrastructure template validation passed ($($resources.Count) compiled resources)."
}
finally {
    Remove-Item -LiteralPath $compiledFile, $diagnosticsFile -Force -ErrorAction SilentlyContinue
}
