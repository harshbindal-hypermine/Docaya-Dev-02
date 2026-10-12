// =============================================================================
// search.bicep
//
// Azure AI Search - the hybrid index and vector store behind Ask Docaya (M10).
//
// Technical Architecture Document v1.3, Section 14.6.4:
//   "Azure AI Search - Indexing identity = Index Data Contributor (write only).
//    API identity = Index Data Reader (query only). API keys disabled; RBAC-only
//    data plane; private endpoint; server-composed filters; documentStatus
//    constrained to Published on every query."
//
// Section 12.4 - permission trimming. A query returns a passage only if its
// aclKeys intersect the caller's security keys. The filter is composed on the
// server; a client can never widen it.
//
// Section 12.6 - only approved, published content is ever indexed.
//
// Provisioning order: step 5 (TAD 18.3).
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

@description('Whether to create a private endpoint (TAD 18.6).')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for search resolution.')
param searchPrivateDnsZoneId string = ''

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var searchServiceName = '${abbreviations.searchService}-docaya-${environmentName}-${location}'

// TAD 18.6 - shared and small in dev, dedicated in test, dedicated with a private
// endpoint in production. Semantic ranking and vector search require Basic or
// above; Standard is required for a private endpoint.
var searchSku = {
  dev: 'basic'
  test: 'standard'
  prod: 'standard'
}

var replicaCount = {
  dev: 1
  test: 2
  // Three replicas are required for the read SLA.
  prod: 3
}

var partitionCount = {
  dev: 1
  test: 1
  prod: 2
}

// -----------------------------------------------------------------------------
// Search service.
// -----------------------------------------------------------------------------

resource searchService 'Microsoft.Search/searchServices@2025-02-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchSku[environmentName]
  }
  identity: {
    // Required so the indexer can reach Blob and the embedding endpoint by
    // managed identity rather than by key.
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: replicaCount[environmentName]
    partitionCount: partitionCount[environmentName]
    hostingMode: 'default'

    // TAD 14.6.4 - "API keys disabled; RBAC-only data plane."
    // This is what makes the identity separation in Section 12.5 real: without
    // it, an admin key would bypass the reader/contributor split entirely.
    disableLocalAuth: true
    authOptions: null

    publicNetworkAccess: privateEndpointsEnabled ? 'disabled' : 'enabled'

    networkRuleSet: {
      ipRules: []
      bypass: 'AzureServices'
    }

    semanticSearch: searchSku[environmentName] == 'basic' ? 'free' : 'standard'
  }
}

// -----------------------------------------------------------------------------
// Private endpoint.
// -----------------------------------------------------------------------------

resource searchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${abbreviations.privateEndpoint}-${searchServiceName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'searchService'
        properties: {
          privateLinkServiceId: searchService.id
          groupIds: ['searchService']
        }
      }
    ]
  }
}

resource searchPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: searchPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.search, '.', '-')
        properties: {
          privateDnsZoneId: searchPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Query logs evidence that permission trimming is applied on every request
// (TAD 12.4).
// -----------------------------------------------------------------------------

resource searchDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: searchService
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
//
// No admin key is emitted: local auth is disabled, so none is usable.
// -----------------------------------------------------------------------------

@description('Search service resource identifier.')
output searchServiceId string = searchService.id

@description('Search service name.')
output searchServiceName string = searchService.name

@description('Search endpoint. Resolves to a private IP when private endpoints are enabled.')
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('Principal identifier of the search service identity, for its grant on Blob and the embedding endpoint.')
output searchPrincipalId string = searchService.identity.principalId
