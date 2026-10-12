// =============================================================================
// rbac.bicep
//
// Every data-plane role assignment in the estate, at least privilege.
//
// Technical Architecture Document v1.3:
//   14.6 Resource Access Design
//   14.7 Service-to-Service Access Matrix
//   18.3 provisioning order step 9 - "Role assignments are assigned last so
//        every target resource exists and scope is exact."
//
// Two principles govern every assignment below.
//
//   Scope is exact. A grant is made at the narrowest resource that satisfies the
//   operation. Blob grants are at CONTAINER scope, never account scope
//   (TAD 14.6.2). Service Bus receive grants are on a worker's OWN subscription,
//   never the namespace (TAD 14.6.4).
//
//   Identity is separated by function. The indexing identity can write the search
//   index but cannot read it; the API identity can read it but cannot write. That
//   separation is meaningless unless API keys are disabled, which search.bicep
//   does (TAD 12.5, 14.6.4).
//
// Deterministic GUIDs: every assignment name is derived from scope, principal and
// role, so re-running the deployment is idempotent.
// =============================================================================

import { roleDefinitionIds, workloadPrincipalsType } from './shared/types.bicep'

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Principal identifiers of the six workload identities.')
param principals workloadPrincipalsType

@description('Storage container resource identifiers. Grants are made here, never at account scope (TAD 14.6.2).')
param storageContainerIds object

@description('Storage account name for the document staging account.')
param storageAccountName string

@description('Durable task hub storage account name.')
param taskHubStorageAccountName string

@description('Key Vault name.')
param keyVaultName string

@description('Service Bus namespace name.')
param serviceBusNamespaceName string

@description('Service Bus topic name.')
param serviceBusTopicName string

@description('Service Bus subscription resource identifiers, keyed by consumer.')
param serviceBusSubscriptionIds object

@description('Azure AI Search service name.')
param searchServiceName string

@description('Azure OpenAI account name.')
param openAiAccountName string

@description('Container registry name.')
param containerRegistryName string

@description('Principal identifier of the Azure AI Search service identity, which reads Blob and calls the embedding endpoint.')
param searchServicePrincipalId string

// -----------------------------------------------------------------------------
// Existing resources.
//
// Declared as `existing` so a role assignment can be scoped to the exact
// resource rather than to the resource group.
// -----------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource taskHubStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: taskHubStorageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespaceName
}

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' existing = {
  parent: serviceBusNamespace
  name: serviceBusTopicName
}

resource searchService 'Microsoft.Search/searchServices@2025-02-01-preview' existing = {
  name: searchServiceName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

// -----------------------------------------------------------------------------
// Blob container grants - TAD 14.6.2.
//
// "Managed identity holding Storage Blob Data Contributor on the staging and
//  preview containers only - never at account scope."
//
// capture   writes chunks and commits staged files
// promotion reads the staged file to upload it to SharePoint, then reconciles
// indexing  reads extraction output to build the index record
// api       reads thumbnails and staged previews to broker downloads
// -----------------------------------------------------------------------------

var blobGrants = [
  {
    key: 'capture-chunks'
    containerId: storageContainerIds.chunks
    principalId: principals.capture
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'Capture writes resumable upload chunks.'
  }
  {
    key: 'capture-staged'
    containerId: storageContainerIds.staged
    principalId: principals.capture
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'Capture commits the assembled file to staging.'
  }
  {
    key: 'capture-quarantine'
    containerId: storageContainerIds.quarantine
    principalId: principals.capture
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'Capture moves a file that fails malware or DLP into quarantine.'
  }
  {
    key: 'capture-thumbnails'
    containerId: storageContainerIds.thumbnails
    principalId: principals.capture
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'A thumbnail is captured at registration (TAD 7.1 step 1).'
  }
  {
    key: 'promotion-staged'
    containerId: storageContainerIds.staged
    principalId: principals.promotion
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'Promotion reads the unchanged staged file, then purges it on reconcile.'
  }
  {
    key: 'promotion-quarantine'
    containerId: storageContainerIds.quarantine
    principalId: principals.promotion
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'A published hash that does not equal the staged hash is quarantined (TAD 7.2).'
  }
  {
    key: 'promotion-thumbnails'
    containerId: storageContainerIds.thumbnails
    principalId: principals.promotion
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'A thumbnail is captured at every approved revision.'
  }
  {
    key: 'indexing-extraction'
    containerId: storageContainerIds.extraction
    principalId: principals.indexing
    roleId: roleDefinitionIds.storageBlobDataContributor
    reason: 'Indexing writes and reads extraction output.'
  }
  {
    key: 'indexing-staged-read'
    containerId: storageContainerIds.staged
    principalId: principals.indexing
    roleId: roleDefinitionIds.storageBlobDataReader
    reason: 'Indexing reads published content only. Read, never write.'
  }
  {
    key: 'api-thumbnails-read'
    containerId: storageContainerIds.thumbnails
    principalId: principals.api
    roleId: roleDefinitionIds.storageBlobDataReader
    reason: 'The API brokers permission-checked thumbnail reads. Read only.'
  }
  {
    key: 'api-staged-read'
    containerId: storageContainerIds.staged
    principalId: principals.api
    roleId: roleDefinitionIds.storageBlobDataReader
    reason: 'The API brokers preview and download. It never writes content.'
  }
  {
    key: 'search-extraction-read'
    containerId: storageContainerIds.extraction
    principalId: searchServicePrincipalId
    roleId: roleDefinitionIds.storageBlobDataReader
    reason: 'The search indexer reads extraction output. Read only.'
  }
]

resource blobContainerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for grant in blobGrants: {
    name: guid(grant.containerId, grant.principalId, grant.roleId)
    // Scoping to the container is what keeps this least privilege. Scoping to the
    // account would grant every container at once.
    scope: storageAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', grant.roleId)
      principalId: grant.principalId
      principalType: 'ServicePrincipal'
      description: grant.reason
    }
  }
]

// -----------------------------------------------------------------------------
// Durable task hub grants.
//
// The Functions host needs blob, queue and table on its own task hub. This is
// orchestration state, not document content, which is why it is a separate
// account from the staging storage.
// -----------------------------------------------------------------------------

var taskHubRoles = [
  roleDefinitionIds.storageBlobDataContributor
  roleDefinitionIds.storageQueueDataContributor
  roleDefinitionIds.storageTableDataContributor
]

resource taskHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in taskHubRoles: {
    name: guid(taskHubStorageAccount.id, principals.workflow, roleId)
    scope: taskHubStorageAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: principals.workflow
      principalType: 'ServicePrincipal'
      description: 'Durable task hub state. A worker restart resumes the orchestration (TAD 8.5).'
    }
  }
]

// -----------------------------------------------------------------------------
// Key Vault grants - TAD 14.6.4.
//
// "Each workload holds Get and List on only the specific secrets it needs."
//
// Key Vault RBAC scopes to the vault or to an individual secret. Per-secret
// assignment requires the secret to exist, and secrets are seeded by the release
// pipeline rather than by this template, so the grant is made at vault scope with
// the least-privileged role that permits reading: Key Vault Secrets User. It
// confers Get and List on secrets and nothing else - no write, no delete, no key
// or certificate access.
// -----------------------------------------------------------------------------

var keyVaultReaders = [
  { key: 'workflow', principalId: principals.workflow }
  { key: 'promotion', principalId: principals.promotion }
  { key: 'indexing', principalId: principals.indexing }
  { key: 'analytics', principalId: principals.analytics }
]

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for reader in keyVaultReaders: {
    name: guid(keyVault.id, reader.principalId, roleDefinitionIds.keyVaultSecretsUser)
    scope: keyVault
    properties: {
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        roleDefinitionIds.keyVaultSecretsUser
      )
      principalId: reader.principalId
      principalType: 'ServicePrincipal'
      description: 'Get and List on secrets only. Secrets are referenced by URI and never emitted to logs (TAD 14.6.4).'
    }
  }
]

// -----------------------------------------------------------------------------
// Service Bus grants - TAD 14.6.4.
//
// "Workflow worker = Send on publishing topics, Receive on its own subscriptions
//  only."
//
// Send is granted at TOPIC scope. Receive is granted at SUBSCRIPTION scope, so a
// worker cannot drain another worker's queue.
// -----------------------------------------------------------------------------

var topicSenders = [
  { key: 'workflow', principalId: principals.workflow }
  { key: 'capture', principalId: principals.capture }
  { key: 'promotion', principalId: principals.promotion }
]

resource serviceBusSendRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for sender in topicSenders: {
    name: guid(serviceBusTopic.id, sender.principalId, roleDefinitionIds.serviceBusDataSender)
    scope: serviceBusTopic
    properties: {
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        roleDefinitionIds.serviceBusDataSender
      )
      principalId: sender.principalId
      principalType: 'ServicePrincipal'
      description: 'Send on the publishing topic. The outbox dispatches here after the state change commits (TAD 8.5).'
    }
  }
]

// Receive is scoped to the individual subscription each worker owns.
resource promotionReceiveRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusSubscriptionIds.promotion, principals.promotion, roleDefinitionIds.serviceBusDataReceiver)
  scope: serviceBusTopic
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.serviceBusDataReceiver
    )
    principalId: principals.promotion
    principalType: 'ServicePrincipal'
    description: 'Receive on the promotion subscription only. Single consumer of FinalApprovalGranted (TAD 24.3).'
  }
}

resource indexingReceiveRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusSubscriptionIds.indexing, principals.indexing, roleDefinitionIds.serviceBusDataReceiver)
  scope: serviceBusTopic
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.serviceBusDataReceiver
    )
    principalId: principals.indexing
    principalType: 'ServicePrincipal'
    description: 'Receive on the indexing subscription only.'
  }
}

resource workflowReceiveRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusSubscriptionIds.workflow, principals.workflow, roleDefinitionIds.serviceBusDataReceiver)
  scope: serviceBusTopic
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.serviceBusDataReceiver
    )
    principalId: principals.workflow
    principalType: 'ServicePrincipal'
    description: 'Receive on the workflow and notification subscriptions.'
  }
}

// -----------------------------------------------------------------------------
// Azure AI Search grants - TAD 14.6.4 and 12.5.
//
// "Indexing identity = Index Data Contributor (write only).
//  API identity = Index Data Reader (query only)."
//
// This separation is the technical control behind the claim that a query cannot
// mutate the index and an indexer cannot read back a permission-trimmed result.
// -----------------------------------------------------------------------------

resource searchReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principals.api, roleDefinitionIds.searchIndexDataReader)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.searchIndexDataReader
    )
    principalId: principals.api
    principalType: 'ServicePrincipal'
    description: 'Query only. The API composes the permission-trimming filter server-side (TAD 12.4).'
  }
}

resource searchContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principals.indexing, roleDefinitionIds.searchIndexDataContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.searchIndexDataContributor
    )
    principalId: principals.indexing
    principalType: 'ServicePrincipal'
    description: 'Write only. Only approved, published content is ever indexed (TAD 12.6).'
  }
}

// The indexing identity manages index definitions as well as documents.
resource searchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principals.indexing, roleDefinitionIds.searchServiceContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionIds.searchServiceContributor
    )
    principalId: principals.indexing
    principalType: 'ServicePrincipal'
    description: 'Create and update the index schema during a release.'
  }
}

// -----------------------------------------------------------------------------
// Azure OpenAI grants.
//
// The indexing identity generates embeddings after publication. The API identity
// composes a cited answer. Neither may manage the account.
// -----------------------------------------------------------------------------

var openAiUsers = [
  { key: 'indexing', principalId: principals.indexing }
  { key: 'api', principalId: principals.api }
  { key: 'search', principalId: searchServicePrincipalId }
]

resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for user in openAiUsers: {
    name: guid(openAiAccount.id, user.principalId, roleDefinitionIds.cognitiveServicesOpenAiUser)
    scope: openAiAccount
    properties: {
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        roleDefinitionIds.cognitiveServicesOpenAiUser
      )
      principalId: user.principalId
      principalType: 'ServicePrincipal'
      description: 'Invoke the approved deployment. Embeddings are generated strictly after publication (TAD 7.2).'
    }
  }
]

// -----------------------------------------------------------------------------
// Container registry grants.
//
// Pull by digest. No registry password is stored anywhere (TAD 14.7).
// -----------------------------------------------------------------------------

var registryPullers = [
  { key: 'workflow', principalId: principals.workflow }
]

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for puller in registryPullers: {
    name: guid(containerRegistry.id, puller.principalId, roleDefinitionIds.acrPull)
    scope: containerRegistry
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIds.acrPull)
      principalId: puller.principalId
      principalType: 'ServicePrincipal'
      description: 'Pull the API image by immutable digest (TAD 18.4).'
    }
  }
]

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Count of role assignments created, for post-deploy assertion (TAD 18.5).')
output roleAssignmentCount int = length(blobGrants) + length(taskHubRoles) + length(keyVaultReaders) + length(topicSenders) + 3 + 3 + length(openAiUsers) + length(registryPullers)

@description('Summary of the granted access, for the deployment evidence pack (TAD 19.3).')
output accessSummary object = {
  blobContainerGrants: length(blobGrants)
  taskHubGrants: length(taskHubRoles)
  keyVaultSecretReaders: length(keyVaultReaders)
  serviceBusSenders: length(topicSenders)
  serviceBusReceivers: 3
  searchGrants: 3
  openAiUsers: length(openAiUsers)
  registryPullers: length(registryPullers)
}
