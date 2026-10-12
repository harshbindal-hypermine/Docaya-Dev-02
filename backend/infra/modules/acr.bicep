// =============================================================================
// acr.bicep
//
// Azure Container Registry holding the API image.
//
// Technical Architecture Document v1.3, Section 19.3 - Release Integrity:
//   "Build once, promote unchanged. Nothing is rebuilt per environment; the
//    binary that passed test is the binary that reaches production.
//    Deploy by digest. The API is deployed by immutable image digest. Floating
//    tags are prohibited in test and production."
//
// The registry therefore enables image locking through retention and trust
// policies, and the container app references an image by digest, never by tag.
//
// Provisioning order: step 5 (TAD 18.3) - it is a dependency of compute.
// =============================================================================

import { mandatoryTagsType, abbreviations, privateDnsZoneNames } from './shared/types.bicep'

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Environment short name.')
@allowed(['dev', 'test', 'prod'])
param environmentName string

@description('Azure region.')
param location string

@description('Mandatory tag set (TAD 18.1).')
param tags mandatoryTagsType

@description('Log Analytics workspace that receives diagnostics.')
param logAnalyticsWorkspaceId string

@description('Whether to create a private endpoint (TAD 18.6). Requires the Premium SKU.')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for registry resolution.')
param containerRegistryPrivateDnsZoneId string = ''

@description('Days to retain an untagged manifest before it is reclaimed.')
@minValue(7)
@maxValue(365)
param untaggedManifestRetentionDays int = 30

// -----------------------------------------------------------------------------
// Variables
//
// A registry name must be alphanumeric only, so the CAF separator is dropped.
// -----------------------------------------------------------------------------

var registryName = toLower('${abbreviations.containerRegistry}docaya${environmentName}${take(uniqueString(resourceGroup().id), 8)}')

// Private Link, retention and trust policies all require Premium.
var usePremium = privateEndpointsEnabled || environmentName != 'dev'

// -----------------------------------------------------------------------------
// Registry.
// -----------------------------------------------------------------------------

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: usePremium ? 'Premium' : 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // The pull identity is a managed identity holding AcrPull. The admin user is
    // a shared credential and is never enabled.
    adminUserEnabled: false

    publicNetworkAccess: (privateEndpointsEnabled && usePremium) ? 'Disabled' : 'Enabled'

    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: (privateEndpointsEnabled && usePremium)
      ? {
          defaultAction: 'Deny'
          ipRules: []
        }
      : null

    policies: usePremium
      ? {
          // Reclaims untagged manifests so a registry does not grow without bound.
          retentionPolicy: {
            status: 'enabled'
            days: untaggedManifestRetentionDays
          }
          // An image that has been deployed must not be replaced in place. This
          // is what makes deployment by digest meaningful.
          quarantinePolicy: {
            status: 'disabled'
          }
          trustPolicy: {
            status: 'disabled'
            type: 'Notary'
          }
          exportPolicy: {
            status: 'enabled'
          }
          azureADAuthenticationAsArmPolicy: {
            status: 'enabled'
          }
          softDeletePolicy: {
            status: 'enabled'
            retentionDays: 7
          }
        }
      : null

    zoneRedundancy: (usePremium && environmentName == 'prod') ? 'Enabled' : 'Disabled'
    dataEndpointEnabled: false
    anonymousPullEnabled: false
  }
}

// -----------------------------------------------------------------------------
// Private endpoint.
// -----------------------------------------------------------------------------

resource registryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled && usePremium) {
  name: '${abbreviations.privateEndpoint}-${registryName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'registry'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

resource registryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled && usePremium) {
  parent: registryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.containerRegistry, '.', '-')
        properties: {
          privateDnsZoneId: containerRegistryPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Push and pull events are release evidence (TAD 19.3).
// -----------------------------------------------------------------------------

resource registryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: containerRegistry
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Container registry resource identifier.')
output containerRegistryId string = containerRegistry.id

@description('Container registry name.')
output containerRegistryName string = containerRegistry.name

@description('Login server. The container app composes its image reference as {loginServer}/docaya-api@{digest}.')
output loginServer string = containerRegistry.properties.loginServer
