// =============================================================================
// signalr.bicep
//
// SignalR Service for real-time notification push (M7).
//
// Technical Architecture Document v1.3, appendix A:
//   "SignalR Service - Real-time notification push. Private endpoint."
//
// Reconciliation register: Azure Cache for Redis was removed from the v1.3
// baseline - "session and presence needs are met by the API and SignalR."
//
// Provisioning order: step 7 (TAD 18.3).
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

@description('Private DNS zone identifier for SignalR resolution.')
param signalRPrivateDnsZoneId string = ''

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var signalRName = '${abbreviations.signalR}-docaya-${environmentName}-${location}'

// Private Link requires Premium. Standard is acceptable in dev.
var usePremium = privateEndpointsEnabled && environmentName != 'dev'

var signalRSku = usePremium
  ? { name: 'Premium_P1', tier: 'Premium', capacity: 1 }
  : { name: 'Standard_S1', tier: 'Standard', capacity: 1 }

// -----------------------------------------------------------------------------
// SignalR Service.
// -----------------------------------------------------------------------------

resource signalR 'Microsoft.SignalRService/signalR@2024-03-01' = {
  name: signalRName
  location: location
  tags: tags
  sku: signalRSku
  kind: 'SignalR'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Default mode: the API acts as the hub server. Serverless would bypass the
    // authorization pipeline, which is not acceptable for a permission-trimmed
    // notification stream.
    features: [
      {
        flag: 'ServiceMode'
        value: 'Default'
      }
      {
        flag: 'EnableConnectivityLogs'
        value: 'True'
      }
      {
        flag: 'EnableMessagingLogs'
        value: 'True'
      }
      {
        flag: 'EnableLiveTrace'
        value: 'False'
      }
    ]

    // The API connects with a managed identity. Disabling local auth removes the
    // access key, so no shared secret exists (TAD 14.7 - "No secret").
    disableLocalAuth: true
    disableAadAuth: false

    publicNetworkAccess: usePremium ? 'Disabled' : 'Enabled'

    tls: {
      clientCertEnabled: false
    }

    cors: {
      // Browsers reach SignalR through the negotiated endpoint issued by the
      // API, so no wildcard origin is permitted here.
      allowedOrigins: []
    }

    networkACLs: {
      defaultAction: usePremium ? 'Deny' : 'Allow'
      publicNetwork: {
        allow: usePremium ? [] : ['ClientConnection', 'ServerConnection', 'RESTAPI']
      }
      privateEndpoints: []
    }
  }
}

// -----------------------------------------------------------------------------
// Private endpoint.
// -----------------------------------------------------------------------------

resource signalRPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (usePremium) {
  name: '${abbreviations.privateEndpoint}-${signalRName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'signalr'
        properties: {
          privateLinkServiceId: signalR.id
          groupIds: ['signalr']
        }
      }
    ]
  }
}

resource signalRPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (usePremium) {
  parent: signalRPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.signalR, '.', '-')
        properties: {
          privateDnsZoneId: signalRPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
// -----------------------------------------------------------------------------

resource signalRDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: signalR
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
// No connection string is emitted: local auth is disabled, so none is usable.
// -----------------------------------------------------------------------------

@description('SignalR Service resource identifier.')
output signalRId string = signalR.id

@description('SignalR Service name.')
output signalRName string = signalR.name

@description('SignalR hostname, for the managed-identity client.')
output signalRHostName string = signalR.properties.hostName
