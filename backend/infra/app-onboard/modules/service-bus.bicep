param location string
param tags object
param serviceBusNamespaceName string

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource documentEvents 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: namespace
  name: 'document-events'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
  }
}

resource outboxDispatch 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: 'outbox-dispatch'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    lockDuration: 'PT1M'
  }
}

output serviceBusNamespaceId string = namespace.id
output serviceBusNamespaceName string = namespace.name
output documentEventsTopicName string = documentEvents.name
output outboxDispatchQueueName string = outboxDispatch.name
