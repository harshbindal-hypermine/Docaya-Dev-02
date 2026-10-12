// =============================================================================
// functions.bicep
//
// Functions plan, application and the Durable task hub storage account.
//
// Technical Architecture Document v1.3:
//   16.1 - snet-func hosts the workers. Inbound from Service Bus and timer
//          triggers; outbound to snet-pe and allow-listed Graph.
//   8.5  - Durable Functions hold orchestration state, so a worker restart
//          resumes rather than replaying committed side effects.
//   14.7 - Functions reach SQL, Blob, Service Bus, Graph and Search by managed
//          identity. No secret anywhere in the path.
//
// The task hub needs its own storage account, separate from the document staging
// account, so orchestration state and document content never share a blast
// radius or a role assignment.
//
// Provisioning order: step 7 (TAD 18.3).
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations } from './shared/types.bicep'

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

@description('Per-environment posture (TAD 18.6).')
param posture environmentPostureType

@description('Log Analytics workspace that receives diagnostics.')
param logAnalyticsWorkspaceId string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Resource identifier of snet-func.')
param funcSubnetId string

@description('Whether private endpoints are enabled for this environment.')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string

@description('Private DNS zone for Blob private endpoints.')
param blobPrivateDnsZoneId string

@description('Private DNS zone for File private endpoints.')
param filePrivateDnsZoneId string

@description('Private DNS zone for Queue private endpoints.')
param queuePrivateDnsZoneId string

@description('Private DNS zone for Table private endpoints.')
param tablePrivateDnsZoneId string

@description('Resource identifier of the workflow workload identity.')
param workflowIdentityResourceId string

@description('Client identifier of the workflow workload identity.')
param workflowIdentityClientId string

@description('Resource identifiers of the additional identities the host presents for promotion and indexing.')
param additionalIdentityResourceIds array = []

@description('Key Vault URI.')
param keyVaultUri string

@description('Fully qualified SQL server name.')
param sqlServerFqdn string

@description('SQL database name.')
param sqlDatabaseName string

@description('Fully qualified Service Bus namespace.')
param serviceBusFullyQualifiedNamespace string

@description('Service Bus topic carrying the domain event catalogue.')
param documentEventsTopicName string

@description('Azure AI Search endpoint.')
param searchEndpoint string

@description('Blob service endpoint of the document staging account.')
param blobEndpoint string

@description('Azure OpenAI endpoint.')
param openAiEndpoint string

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var planName = '${abbreviations.appServicePlan}-docaya-func-${environmentName}-${location}'
var functionAppName = '${abbreviations.functionApp}-docaya-${environmentName}-${location}'
var taskHubStorageName = toLower('stdocayafn${environmentName}${take(uniqueString(resourceGroup().id), 8)}')

// Elastic Premium is required for virtual network integration and for the
// always-ready instances that keep a Durable orchestration responsive.
var planSku = {
  dev: { name: 'EP1', tier: 'ElasticPremium', family: 'EP', capacity: 1 }
  test: { name: 'EP1', tier: 'ElasticPremium', family: 'EP', capacity: 1 }
  prod: { name: 'EP2', tier: 'ElasticPremium', family: 'EP', capacity: 2 }
}

var identityMap = reduce(
  union([workflowIdentityResourceId], additionalIdentityResourceIds),
  {},
  (accumulator, identityId) => union(accumulator, { '${identityId}': {} })
)

// -----------------------------------------------------------------------------
// Durable task hub storage.
//
// Separate from the document staging account so orchestration state and document
// content never share a role assignment.
// -----------------------------------------------------------------------------

resource taskHubStorage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: taskHubStorageName
  location: location
  tags: union(tags, {
    purpose: 'Durable task hub state. Holds no document content.'
  })
  sku: {
    name: posture.zoneRedundant ? 'Standard_ZRS' : 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false

    // The Functions host authenticates to its own task hub with the workload
    // identity, so no account key is needed (TAD 14.7 - "No secret").
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true

    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateEndpointsEnabled ? 'Deny' : 'Allow'
    }

    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
        queue: { enabled: true, keyType: 'Account' }
        table: { enabled: true, keyType: 'Account' }
      }
    }
  }
}

// Durable Functions uses Blob, Queue and Table data planes for orchestration
// state. File is provisioned as well because the Functions host can use the
// content share during deployment and scale operations. In test and production
// every data plane stays on the private endpoint subnet.
resource taskHubBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${taskHubStorageName}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: taskHubStorage.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource taskHubBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: taskHubBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZoneId
        }
      }
    ]
  }
}

resource taskHubFilePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${taskHubStorageName}-file-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'file'
        properties: {
          privateLinkServiceId: taskHubStorage.id
          groupIds: ['file']
        }
      }
    ]
  }
}

resource taskHubFilePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: taskHubFilePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'file'
        properties: {
          privateDnsZoneId: filePrivateDnsZoneId
        }
      }
    ]
  }
}

resource taskHubQueuePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${taskHubStorageName}-queue-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'queue'
        properties: {
          privateLinkServiceId: taskHubStorage.id
          groupIds: ['queue']
        }
      }
    ]
  }
}

resource taskHubQueuePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: taskHubQueuePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'queue'
        properties: {
          privateDnsZoneId: queuePrivateDnsZoneId
        }
      }
    ]
  }
}

resource taskHubTablePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${taskHubStorageName}-table-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'table'
        properties: {
          privateLinkServiceId: taskHubStorage.id
          groupIds: ['table']
        }
      }
    ]
  }
}

resource taskHubTablePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: taskHubTablePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'table'
        properties: {
          privateDnsZoneId: tablePrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Plan.
// -----------------------------------------------------------------------------

resource functionsPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  sku: planSku[environmentName]
  kind: 'elastic'
  properties: {
    reserved: true
    maximumElasticWorkerCount: environmentName == 'prod' ? 20 : 5
    zoneRedundant: posture.zoneRedundant
  }
}

// -----------------------------------------------------------------------------
// Function application.
// -----------------------------------------------------------------------------

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    // The host presents the workflow identity by default and can select the
    // promotion or indexing identity per operation.
    type: 'UserAssigned'
    userAssignedIdentities: identityMap
  }
  properties: {
    serverFarmId: functionsPlan.id
    httpsOnly: true

    // TAD 16.1 - workers live in snet-func and reach data services through
    // snet-pe. Route all traffic so nothing bypasses the NSG.
    virtualNetworkSubnetId: funcSubnetId
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: false

    // Workers are driven by queue and timer, not by inbound HTTP. Public network
    // access is disabled so there is no reachable surface.
    publicNetworkAccess: 'Disabled'

    clientAffinityEnabled: false

    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|10.0'
      alwaysOn: false
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      functionsRuntimeScaleMonitoringEnabled: true

      // Pre-warmed instances keep a Durable orchestration responsive after a
      // period of inactivity.
      preWarmedInstanceCount: environmentName == 'prod' ? 2 : 1

      cors: {
        allowedOrigins: []
      }

      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          // Identity-based connection to the task hub. The __accountName form
          // tells the host to acquire a token rather than look for a key.
          name: 'AzureWebJobsStorage__accountName'
          value: taskHubStorage.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: workflowIdentityClientId
        }
        {
          // Identity-based Service Bus connection, matching the trigger
          // attribute Connection = "DocayaServiceBus".
          name: 'DocayaServiceBus__fullyQualifiedNamespace'
          value: serviceBusFullyQualifiedNamespace
        }
        {
          name: 'DocayaServiceBus__credential'
          value: 'managedidentity'
        }
        {
          name: 'DocayaServiceBus__clientId'
          value: workflowIdentityClientId
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: workflowIdentityClientId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'ConnectionStrings__DocayaSql'
          value: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
        }
        {
          name: 'Docaya__KeyVaultUri'
          value: keyVaultUri
        }
        {
          name: 'Docaya__ServiceBus__DocumentEventsTopic'
          value: documentEventsTopicName
        }
        {
          name: 'Docaya__ServiceBus__PromotionSubscription'
          value: 'promotion'
        }
        {
          name: 'Docaya__ServiceBus__IndexingSubscription'
          value: 'indexing'
        }
        {
          name: 'Docaya__ServiceBus__NotificationSubscription'
          value: 'notification'
        }
        {
          name: 'Docaya__Search__Endpoint'
          value: searchEndpoint
        }
        {
          name: 'Docaya__Storage__BlobEndpoint'
          value: blobEndpoint
        }
        {
          name: 'Docaya__OpenAi__Endpoint'
          value: openAiEndpoint
        }
        {
          name: 'Docaya__FeatureFlags__AskAnsweringEnabled'
          value: string(posture.askAnsweringEnabled)
        }
        {
          name: 'Docaya__OperatingTimeZone'
          value: 'Arabian Standard Time'
        }
        {
          name: 'Docaya__Sla__UrgentWorkingDays'
          value: '12'
        }
        {
          name: 'Docaya__Sla__NormalWorkingDays'
          value: '30'
        }
        {
          name: 'Docaya__Sla__WarningWindowWorkingDays'
          value: '3'
        }
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
// -----------------------------------------------------------------------------

resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: functionApp
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

@description('Function application resource identifier.')
output functionAppId string = functionApp.id

@description('Function application name.')
output functionAppName string = functionApp.name

@description('Durable task hub storage account name.')
output taskHubStorageAccountName string = taskHubStorage.name

@description('Durable task hub storage account resource identifier, for the queue and table grants held by the workflow identity.')
output taskHubStorageAccountId string = taskHubStorage.id

@description('Functions plan resource identifier.')
output functionsPlanId string = functionsPlan.id
