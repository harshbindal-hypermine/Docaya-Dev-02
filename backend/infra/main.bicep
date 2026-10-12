// =============================================================================
// main.bicep - subscription-scope composition root for the Docaya estate.
//
// Technical Architecture Document v1.3, Sections 18.1 to 18.4.
//
// Assumes a BLANK Azure subscription. This template creates the resource group
// and every resource inside it, in the dependency order defined by Section 18.3.
//
// Contains no secret and no tenant value. Secrets are referenced from Key Vault
// by URI; tenant-specific values arrive from the environment parameter file or
// from the release pipeline under workload identity federation (TAD 19.3).
//
// -----------------------------------------------------------------------------
// Deploy
// -----------------------------------------------------------------------------
//
//   # Preview. Reviewed and approved by a named person before any change.
//   az deployment sub what-if \
//     --location uaenorth \
//     --template-file infra/main.bicep \
//     --parameters infra/environments/dev.bicepparam
//
//   # Apply.
//   az deployment sub create \
//     --location uaenorth \
//     --template-file infra/main.bicep \
//     --parameters infra/environments/dev.bicepparam
//
// -----------------------------------------------------------------------------
// Provisioning order - TAD 18.3
// -----------------------------------------------------------------------------
//
//   1  Network          Private endpoints need the subnet and DNS zone first.
//   2  Identity         Role assignments in step 9 need these principal IDs.
//   3  Observability    Every later diagnostic setting targets this workspace.
//   4  Key Vault        Later modules reference secrets by URI, not by value.
//   5  Data             SQL, Blob, Search, embedding endpoint, registry.
//   6  Messaging        Topics must exist before workers start.
//   7  Compute          Apps must reach dependencies on first start.
//   8  Edge             Routing targets must exist and be healthy.
//   9  RBAC             Assigned last so every target exists and scope is exact.
//  10  Policy           Guardrails applied once the estate is complete.
//
// =============================================================================

targetScope = 'subscription'

import { mandatoryTagsType, environmentPostureType, abbreviations } from './modules/shared/types.bicep'

// -----------------------------------------------------------------------------
// Parameters - environment identity
// -----------------------------------------------------------------------------

@description('Environment short name. One resource group per environment; shared or cross-environment groups are not used (TAD 18.1).')
@allowed(['dev', 'test', 'prod'])
param environmentName string

@description('Azure region. Approved UAE region as primary; the paired region is used only for backup and recovery, never for live processing (TAD 18.1).')
param location string

@description('Regions in which a Docaya resource may be created. Enforced by policy (TAD 18.1).')
param approvedRegions array = [location]

@description('Release version recorded on every resource and in the release manifest (TAD 19.3).')
param releaseVersion string = '1.3.0'

@description('Accountable team or individual.')
param owner string

@description('Chargeback code.')
@minLength(1)
param costCentre string

@description('Highest classification of data this environment may hold (TAD 18.6).')
@allowed(['synthetic', 'anonymised', 'official-internal'])
param dataClassification string

// -----------------------------------------------------------------------------
// Parameters - release
// -----------------------------------------------------------------------------

@description('API image referenced by immutable digest, for example sha256:... A floating tag is prohibited by release policy and is what makes rollback deterministic (TAD 18.4).')
@minLength(71)
@maxLength(71)
param apiImageDigest string

// -----------------------------------------------------------------------------
// Parameters - identity and access
// -----------------------------------------------------------------------------

@description('Object identifier of the Entra group that administers Azure SQL. A group, never an individual, so administration survives a leaver (TAD 14.8).')
@minLength(36)
param sqlAdminGroupObjectId string

@description('Display name of the Entra group that administers Azure SQL.')
param sqlAdminGroupName string

@description('Entra tenant identifier used to compose the token issuer validated at the gateway.')
param entraTenantId string = tenant().tenantId

@description('Application ID URI of the Docaya API, validated as the token audience (TAD 24.1).')
param apiAudience string

// -----------------------------------------------------------------------------
// Parameters - operations
// -----------------------------------------------------------------------------

@description('Address space for the virtual network. Must not overlap any on-premises or peered range.')
param vnetAddressPrefix string = '10.40.0.0/16'

@description('Email address that receives operational alerts. Routed to the on-call rota, never to an individual (TAD 28.3).')
@minLength(3)
param alertEmailAddress string

@description('Publisher email shown on API Management service notifications.')
@minLength(3)
param apiManagementPublisherEmail string

@description('CIDR ranges permitted to reach administrative paths. Empty disables the allow-list (TAD 16.3).')
param administrativeIpAllowList array = []

@description('Custom email sender domain for notifications. Empty uses an Azure-managed domain, which suits dev and test only.')
param notificationSenderDomain string = ''

@description('Data residency for stored notification content. Must match the client residency commitment (TAD 12.7).')
param communicationDataLocation string = 'UAE'

@description('Whether to provision dedicated Power BI Embedded capacity (TAD 25.2).')
param powerBiDedicatedCapacityEnabled bool = false

@description('Object identifiers of the Entra principals that administer Power BI capacity.')
param powerBiCapacityAdministrators array = []

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// TAD 18.1 - rg-docaya-{env}-{region}, one per environment.
var resourceGroupName = '${abbreviations.resourceGroup}-docaya-${environmentName}-${location}'

// TAD 18.1 - the mandatory tag set, applied to every resource by the template.
var tags mandatoryTagsType = {
  workload: 'docaya'
  environment: environmentName
  owner: owner
  costCentre: costCentre
  dataClassification: dataClassification
  residency: 'uae'
  releaseVersion: releaseVersion
}

// TAD 18.6 - Environment Matrix. One place where every per-environment
// difference is decided, so a module never re-derives posture from the name.
var posturesByEnvironment = {
  dev: {
    zoneRedundant: false
    privateEndpointsEnabled: false
    telemetryRetentionDays: 30
    sqlPointInTimeRetentionDays: 7
    geoRedundantBackup: false
    askAnsweringEnabled: true
    apiMinReplicas: 1
    apiMaxReplicas: 3
  }
  test: {
    zoneRedundant: true
    privateEndpointsEnabled: true
    telemetryRetentionDays: 90
    sqlPointInTimeRetentionDays: 14
    geoRedundantBackup: false
    askAnsweringEnabled: true
    apiMinReplicas: 2
    apiMaxReplicas: 10
  }
  prod: {
    zoneRedundant: true
    privateEndpointsEnabled: true
    telemetryRetentionDays: 180
    sqlPointInTimeRetentionDays: 35
    geoRedundantBackup: true
    // TAD 6.3 - Ask answering is feature-flagged on the POC outcome in
    // production. It ships off and is turned on deliberately.
    askAnsweringEnabled: false
    apiMinReplicas: 3
    apiMaxReplicas: 30
  }
}

var posture environmentPostureType = posturesByEnvironment[environmentName]

// -----------------------------------------------------------------------------
// Resource group
// -----------------------------------------------------------------------------

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// =============================================================================
// Step 1 - Network
//
// Private endpoints cannot be created before the subnet and DNS zone exist.
// =============================================================================

module network 'modules/network.bicep' = {
  scope: resourceGroup
  name: 'network'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
  }
}

// =============================================================================
// Step 2 - Managed identities
//
// Role assignments in step 9 reference these principal identifiers.
// =============================================================================

module identity 'modules/identity.bicep' = {
  scope: resourceGroup
  name: 'identity'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// =============================================================================
// Step 3 - Observability
//
// Diagnostic settings on every later resource target this workspace.
// =============================================================================

module observability 'modules/observability.bicep' = {
  scope: resourceGroup
  name: 'observability'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    alertEmailAddress: alertEmailAddress
    // Alerts from a non-representative environment are noise, not signal.
    alertsEnabled: environmentName != 'dev'
  }
}

// =============================================================================
// Step 4 - Key Vault
//
// Later modules reference secrets by URI rather than by value.
// =============================================================================

module keyVault 'modules/keyvault.bicep' = {
  scope: resourceGroup
  name: 'keyvault'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    keyVaultPrivateDnsZoneId: network.outputs.privateDnsZoneIds.keyVault
  }
}

// =============================================================================
// Step 5 - Data
//
// All created with public network access disabled from the outset, never
// hardened afterwards.
// =============================================================================

module sql 'modules/sql.bicep' = {
  scope: resourceGroup
  name: 'sql'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    entraAdminObjectId: sqlAdminGroupObjectId
    entraAdminName: sqlAdminGroupName
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    sqlPrivateDnsZoneId: network.outputs.privateDnsZoneIds.sqlServer
  }
}

module storage 'modules/storage.bicep' = {
  scope: resourceGroup
  name: 'storage'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    blobPrivateDnsZoneId: network.outputs.privateDnsZoneIds.blob
  }
}

module search 'modules/search.bicep' = {
  scope: resourceGroup
  name: 'search'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    searchPrivateDnsZoneId: network.outputs.privateDnsZoneIds.search
  }
}

module aiEndpoint 'modules/aiendpoint.bicep' = {
  scope: resourceGroup
  name: 'aiendpoint'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    openAiPrivateDnsZoneId: network.outputs.privateDnsZoneIds.openAi
  }
}

module containerRegistry 'modules/acr.bicep' = {
  scope: resourceGroup
  name: 'acr'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    containerRegistryPrivateDnsZoneId: network.outputs.privateDnsZoneIds.containerRegistry
  }
}

// =============================================================================
// Step 6 - Messaging
//
// Topics and subscriptions must exist before workers start.
// =============================================================================

module serviceBus 'modules/servicebus.bicep' = {
  scope: resourceGroup
  name: 'servicebus'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    serviceBusPrivateDnsZoneId: network.outputs.privateDnsZoneIds.serviceBus
  }
}

// =============================================================================
// Step 7 - Compute
//
// Applications must be able to resolve and reach their dependencies on first
// start, which is why every data and messaging module precedes them.
// =============================================================================

module containerApp 'modules/containerapp.bicep' = {
  scope: resourceGroup
  name: 'containerapp'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    applicationInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    appSubnetId: network.outputs.appSubnetId
    apiIdentityResourceId: identity.outputs.resourceIds.api
    apiIdentityClientId: identity.outputs.clientIds.api
    apiIdentityPrincipalId: identity.outputs.principalIds.api
    entraAuthority: '${environment().authentication.loginEndpoint}${entraTenantId}/v2.0'
    apiAudience: apiAudience
    virtualNetworkId: network.outputs.virtualNetworkId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    apiImageDigest: apiImageDigest
    keyVaultUri: keyVault.outputs.keyVaultUri
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: sql.outputs.databaseName
    serviceBusFullyQualifiedNamespace: serviceBus.outputs.serviceBusFullyQualifiedNamespace
    searchEndpoint: search.outputs.searchEndpoint
    blobEndpoint: storage.outputs.blobEndpoint
    openAiEndpoint: aiEndpoint.outputs.openAiEndpoint
  }
}

module functions 'modules/functions.bicep' = {
  scope: resourceGroup
  name: 'functions'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    posture: posture
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    applicationInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    funcSubnetId: network.outputs.funcSubnetId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    blobPrivateDnsZoneId: network.outputs.privateDnsZoneIds.blob
    filePrivateDnsZoneId: network.outputs.privateDnsZoneIds.file
    queuePrivateDnsZoneId: network.outputs.privateDnsZoneIds.queue
    tablePrivateDnsZoneId: network.outputs.privateDnsZoneIds.table
    workflowIdentityResourceId: identity.outputs.resourceIds.workflow
    workflowIdentityClientId: identity.outputs.clientIds.workflow
    // The host also presents the promotion and indexing identities, so an
    // activity can act as exactly the principal its operation requires.
    additionalIdentityResourceIds: [
      identity.outputs.resourceIds.promotion
      identity.outputs.resourceIds.indexing
      identity.outputs.resourceIds.capture
    ]
    keyVaultUri: keyVault.outputs.keyVaultUri
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: sql.outputs.databaseName
    serviceBusFullyQualifiedNamespace: serviceBus.outputs.serviceBusFullyQualifiedNamespace
    documentEventsTopicName: serviceBus.outputs.documentEventsTopicName
    searchEndpoint: search.outputs.searchEndpoint
    blobEndpoint: storage.outputs.blobEndpoint
    openAiEndpoint: aiEndpoint.outputs.openAiEndpoint
  }
}

module signalR 'modules/signalr.bicep' = {
  scope: resourceGroup
  name: 'signalr'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointsEnabled: posture.privateEndpointsEnabled
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    signalRPrivateDnsZoneId: network.outputs.privateDnsZoneIds.signalR
  }
}

module communication 'modules/communication.bicep' = {
  scope: resourceGroup
  name: 'communication'
  params: {
    environmentName: environmentName
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    dataLocation: communicationDataLocation
    customSenderDomain: notificationSenderDomain
  }
}

module analytics 'modules/analytics.bicep' = {
  scope: resourceGroup
  name: 'analytics'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    dedicatedCapacityEnabled: powerBiDedicatedCapacityEnabled
    capacityAdministrators: powerBiCapacityAdministrators
  }
}

// =============================================================================
// Step 8 - Edge
//
// Routing targets must exist and be healthy before traffic is accepted.
// =============================================================================

module staticWebApp 'modules/staticwebapp.bicep' = {
  scope: resourceGroup
  name: 'staticwebapp'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

module apiManagement 'modules/apim.bicep' = {
  scope: resourceGroup
  name: 'apim'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    applicationInsightsId: observability.outputs.applicationInsightsId
    applicationInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    edgeSubnetId: network.outputs.edgeSubnetId
    apiBackendFqdn: containerApp.outputs.apiInternalFqdn
    publisherEmail: apiManagementPublisherEmail
    entraTenantId: entraTenantId
    apiAudience: apiAudience
  }
}

module frontDoor 'modules/frontdoor.bicep' = {
  scope: resourceGroup
  name: 'frontdoor'
  params: {
    environmentName: environmentName
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    staticWebAppHostname: staticWebApp.outputs.defaultHostname
    // Detection in dev so a false positive does not block development.
    wafPreventionEnabled: environmentName != 'dev'
    administrativeIpAllowList: administrativeIpAllowList
  }
}

// =============================================================================
// Step 9 - Data-plane RBAC
//
// Assigned last so every target resource exists and the scope is exact.
// =============================================================================

module rbac 'modules/rbac.bicep' = {
  scope: resourceGroup
  name: 'rbac'
  params: {
    principals: identity.outputs.principalIds
    storageContainerIds: storage.outputs.containerIds
    storageAccountName: storage.outputs.storageAccountName
    taskHubStorageAccountName: functions.outputs.taskHubStorageAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    serviceBusTopicName: serviceBus.outputs.documentEventsTopicName
    serviceBusSubscriptionIds: serviceBus.outputs.subscriptionIds
    searchServiceName: search.outputs.searchServiceName
    openAiAccountName: aiEndpoint.outputs.openAiAccountName
    containerRegistryName: containerRegistry.outputs.containerRegistryName
    searchServicePrincipalId: search.outputs.searchPrincipalId
  }
}

// =============================================================================
// Step 10 - Policy
//
// Guardrails applied once the estate is complete, so a policy does not block the
// very deployment that creates it.
// =============================================================================

module policy 'modules/policy.bicep' = {
  scope: resourceGroup
  name: 'policy'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    approvedRegions: approvedRegions
  }
  dependsOn: [
    rbac
  ]
}

// -----------------------------------------------------------------------------
// Outputs
//
// Consumed by the post-deploy assertions that gate a release (TAD 18.5) and by
// the release manifest (TAD 19.3).
// -----------------------------------------------------------------------------

@description('Resource group holding this environment.')
output resourceGroupName string = resourceGroup.name

@description('Public hostname. The single public surface of the estate (TAD 16.2).')
output publicHostname string = frontDoor.outputs.frontDoorEndpointHostname

@description('API Management gateway URL. Private in internal mode.')
output apiGatewayUrl string = apiManagement.outputs.gatewayUrl

@description('Internal API hostname. Reachable only from snet-edge (TAD 16.3).')
output apiInternalFqdn string = containerApp.outputs.apiInternalFqdn

@description('Web bundle hostname, used as the Front Door origin.')
output webHostname string = staticWebApp.outputs.defaultHostname

@description('SQL server fully qualified domain name. Resolves privately when private endpoints are enabled.')
output sqlServerFqdn string = sql.outputs.sqlServerFqdn

@description('SQL database name. The migration bundle targets this database.')
output sqlDatabaseName string = sql.outputs.databaseName

@description('Container registry login server.')
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer

@description('Image digest this environment was deployed with. Rollback re-points to the previous digest (TAD 18.5).')
output deployedApiImageDigest string = apiImageDigest

@description('Key Vault URI. Secrets are referenced from here by URI, never by value (TAD 14.6.4).')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Workload identity client identifiers, for the contained database principals created by the migration bundle (TAD 14.6.3).')
output workloadIdentityClientIds object = identity.outputs.clientIds

@description('Workload identity names, matching the contained database principals.')
output workloadIdentityNames object = identity.outputs.identityNames

@description('Access-control summary for the deployment evidence pack (TAD 19.3).')
output accessSummary object = rbac.outputs.accessSummary

@description('Policy summary for the deployment evidence pack.')
output policySummary object = policy.outputs.policySummary

@description('Environment posture actually applied, for the post-deploy assertion (TAD 18.6).')
output appliedPosture object = posture
