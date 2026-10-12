// =============================================================================
// servicebus.bicep
//
// Service Bus namespace carrying the domain event catalogue.
//
// Technical Architecture Document v1.3:
//   24.3 Domain Event Catalogue - eleven events, each with named consumers.
//   24.4 Messaging Reliability  - transactional outbox, at-least-once delivery
//        with idempotent consumers, session-enabled ordering per document,
//        bounded retry then dead-letter, and audited operator replay.
//   14.6.4 - "Workflow worker = Send on publishing topics, Receive on its own
//        subscriptions only. Private endpoint; no shared access signature in
//        configuration; dead-letter monitored and replay is an audited operator
//        action."
//
// Provisioning order: step 6 (TAD 18.3). Topics and subscriptions must exist
// before workers start.
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations, messaging, privateDnsZoneNames } from './shared/types.bicep'

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

@description('Whether to create a private endpoint (TAD 18.6).')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for Service Bus resolution.')
param serviceBusPrivateDnsZoneId string = ''

@description('Maximum delivery attempts before a message is dead-lettered. Bounded so a poison message cannot loop indefinitely (TAD 24.4).')
@minValue(1)
@maxValue(100)
param maxDeliveryCount int = 5

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var namespaceName = '${abbreviations.serviceBusNamespace}-docaya-${environmentName}-${location}'

// Premium is required for private endpoints and for zone redundancy. Standard is
// acceptable in dev, where neither is mandated (TAD 18.6).
var usePremium = environmentName != 'dev'

// Subscriptions from TAD 24.3. Each consumer receives only what it is named
// against, so a worker cannot read another worker's traffic.
//
// requiresSession is set where ordering matters. TAD 24.4: "Where order matters -
// stage transitions for one document - messages are session-enabled on the
// document identifier."
var subscriptionDefinitions = [
  {
    name: messaging.promotionSubscription
    // Single consumer of FinalApprovalGranted. Exactly-once effect is enforced by
    // ops.PromotionLedger, whose idempotency key is UNIQUE (TAD 8.5).
    filter: 'eventType = \'FinalApprovalGranted\''
    requiresSession: true
  }
  {
    name: messaging.indexingSubscription
    // Only approved, published content is ever indexed.
    filter: 'eventType IN (\'DocumentPublished\', \'RevisionApproved\', \'AccessPolicyChanged\')'
    requiresSession: false
  }
  {
    name: messaging.notificationSubscription
    filter: 'eventType IN (\'DocumentRegistered\', \'DocumentSubmitted\', \'ReviewDecisionRecorded\', \'SlaRiskChanged\', \'SlaExtensionGranted\', \'DocumentPublished\', \'RevisionApproved\', \'RetentionActionDue\')'
    requiresSession: false
  }
  {
    name: messaging.workflowSubscription
    // Stage transitions for one document must be processed in order.
    filter: 'eventType IN (\'DocumentSubmitted\', \'ReviewDecisionRecorded\', \'SlaRiskChanged\', \'SlaExtensionGranted\')'
    requiresSession: true
  }
  {
    name: messaging.auditSubscription
    // The audit consumes everything; the hash chain must not have gaps.
    filter: '1=1'
    requiresSession: false
  }
]

// -----------------------------------------------------------------------------
// Namespace.
// -----------------------------------------------------------------------------

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: usePremium ? 'Premium' : 'Standard'
    tier: usePremium ? 'Premium' : 'Standard'
    capacity: usePremium ? 1 : null
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    minimumTlsVersion: '1.2'

    // TAD 14.6.4 - "no shared access signature in configuration". Disabling local
    // auth removes SAS entirely, so every send and receive is by managed identity
    // and is attributable to a principal.
    disableLocalAuth: true

    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'
    zoneRedundant: usePremium && posture.zoneRedundant
    premiumMessagingPartitions: usePremium ? 1 : null
  }
}

// -----------------------------------------------------------------------------
// Topic.
//
// One topic carries the whole catalogue. Subscriptions filter it, so adding a
// consumer never requires a publisher change.
// -----------------------------------------------------------------------------

resource documentEventsTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: serviceBusNamespace
  name: messaging.documentEventsTopic
  properties: {
    // Required for session-enabled subscriptions to preserve per-document order.
    supportOrdering: true

    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true

    // Duplicate detection is a second line of defence. The first is the
    // idempotency key every consumer honours (TAD 24.4).
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'

    maxMessageSizeInKilobytes: usePremium ? 1024 : null
    enablePartitioning: false
    status: 'Active'
  }
}

// -----------------------------------------------------------------------------
// Subscriptions.
// -----------------------------------------------------------------------------

resource subscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = [
  for definition in subscriptionDefinitions: {
    parent: documentEventsTopic
    name: definition.name
    properties: {
      requiresSession: definition.requiresSession

      // TAD 24.4 - "Exponential backoff with jitter and a bounded attempt count,
      // then dead-letter." The bound lives here; the backoff lives in host.json.
      maxDeliveryCount: maxDeliveryCount

      // Nothing is silently dropped. A message that cannot be processed or that
      // expires becomes visible in the dead-letter queue, which is alerted on.
      deadLetteringOnMessageExpiration: true
      deadLetteringOnFilterEvaluationExceptions: true

      defaultMessageTimeToLive: 'P14D'

      // Long enough for a promotion activity to complete, short enough that a
      // crashed worker releases the lock quickly.
      lockDuration: 'PT5M'

      enableBatchedOperations: true
      status: 'Active'
    }
  }
]

// Subscription rules. Declared separately because a rule is a child of the
// subscription and cannot be expressed inline.
resource subscriptionRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2024-01-01' = [
  for (definition, i) in subscriptionDefinitions: {
    parent: subscription[i]
    name: 'event-type-filter'
    properties: {
      filterType: 'SqlFilter'
      sqlFilter: {
        sqlExpression: definition.filter
        requiresPreprocessing: false
      }
    }
  }
]

// -----------------------------------------------------------------------------
// Private endpoint.
//
// Premium only: the Standard tier does not support Private Link.
// -----------------------------------------------------------------------------

resource serviceBusPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled && usePremium) {
  name: '${abbreviations.privateEndpoint}-${namespaceName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'namespace'
        properties: {
          privateLinkServiceId: serviceBusNamespace.id
          groupIds: ['namespace']
        }
      }
    ]
  }
}

resource serviceBusPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled && usePremium) {
  parent: serviceBusPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.serviceBus, '.', '-')
        properties: {
          privateDnsZoneId: serviceBusPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Dead-letter depth and age are alerted on from this data (TAD 24.4, 28.2).
// -----------------------------------------------------------------------------

resource serviceBusDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: serviceBusNamespace
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
// No connection string is emitted: local auth is disabled, so none exists.
// -----------------------------------------------------------------------------

@description('Service Bus namespace resource identifier.')
output serviceBusNamespaceId string = serviceBusNamespace.id

@description('Service Bus namespace name.')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Fully qualified namespace, for the managed-identity client.')
output serviceBusFullyQualifiedNamespace string = replace(replace(serviceBusNamespace.properties.serviceBusEndpoint, 'https://', ''), ':443/', '')

@description('Topic resource identifier, for the Send grant held by publishers.')
output documentEventsTopicId string = documentEventsTopic.id

@description('Topic name.')
output documentEventsTopicName string = documentEventsTopic.name

@description('Subscription resource identifiers, so each worker is granted Receive on its own subscription only (TAD 14.6.4).')
output subscriptionIds object = {
  promotion: subscription[0].id
  indexing: subscription[1].id
  notification: subscription[2].id
  workflow: subscription[3].id
  audit: subscription[4].id
}
