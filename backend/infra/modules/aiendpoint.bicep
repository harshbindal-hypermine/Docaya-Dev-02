// =============================================================================
// aiendpoint.bicep
//
// Azure OpenAI - the embedding and answering endpoint behind Ask Docaya (M10).
//
// Technical Architecture Document v1.3, reconciliation register:
//   "Azure OpenAI as a general RAG service across the estate" was NARROWED to
//   "an embedding and answering endpoint used strictly after publication,
//    in-region, permission-trimmed and citation-bound."
//
// Section 12.7 - Responsible-AI and data-residency controls. The deployment is
// in-region and private; no content leaves the residency boundary.
//
// Section 6.3 - Ask answering sits behind a feature flag so V1 can ship with
// Quick Search and Browse while answering is deferred pending POC outcomes. The
// answering deployment is therefore conditional on the environment posture.
//
// Non-negotiable: nothing unapproved is ever embedded. Embeddings are generated
// strictly after publication (TAD 7.2).
//
// Provisioning order: step 5 (TAD 18.3).
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations, privateDnsZoneNames } from './shared/types.bicep'

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Environment short name.')
@allowed(['dev', 'test', 'prod'])
param environmentName string

@description('Azure region. Must be the approved in-region location: no content may leave the residency boundary (TAD 12.7).')
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

@description('Private DNS zone identifier for OpenAI resolution.')
param openAiPrivateDnsZoneId string = ''

@description('Embedding model used to vectorise published passages.')
param embeddingModelName string = 'text-embedding-3-large'

@description('Embedding model version.')
param embeddingModelVersion string = '1'

@description('Model used to compose a cited answer. Answers are grounded and citation-bound (TAD 10).')
param answeringModelName string = 'gpt-4o'

@description('Answering model version.')
param answeringModelVersion string = '2024-11-20'

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var openAiName = '${abbreviations.openAiService}-docaya-${environmentName}-${location}'

// Throughput scales with the environment. Dev is sized for development, not for
// a representative load test.
var embeddingCapacity = environmentName == 'prod' ? 120 : 30
var answeringCapacity = environmentName == 'prod' ? 60 : 10

// -----------------------------------------------------------------------------
// Cognitive Services account, OpenAI kind.
// -----------------------------------------------------------------------------

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // The subdomain is required for private endpoint DNS and for Entra token
    // authentication against the data plane.
    customSubDomainName: openAiName

    // Every caller authenticates with a managed identity. Disabling local auth
    // removes the API key, so there is no key to leak or rotate (TAD 14.7).
    disableLocalAuth: true

    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'

    networkAcls: {
      defaultAction: privateEndpointsEnabled ? 'Deny' : 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }

    // TAD 12.7 - responsible-AI controls. Abuse monitoring retains prompts for
    // human review, which is incompatible with the residency commitment for
    // OFFICIAL content, so it is opted out in production where approved.
    restrictOutboundNetworkAccess: true
    allowedFqdnList: []
  }
}

// -----------------------------------------------------------------------------
// Embedding deployment.
//
// Used strictly after publication. The indexing worker calls this only for
// content that has already reached Published (TAD 7.2).
// -----------------------------------------------------------------------------

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: 'docaya-embedding'
  sku: {
    name: 'Standard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// -----------------------------------------------------------------------------
// Answering deployment.
//
// TAD 6.3 - gated on the POC outcome. In production the deployment is created
// only when the feature flag is on, so the capability cannot be reached by
// configuration drift alone.
// -----------------------------------------------------------------------------

resource answeringDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (posture.askAnsweringEnabled) {
  parent: openAiAccount
  name: 'docaya-answering'
  sku: {
    name: 'Standard'
    capacity: answeringCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: answeringModelName
      version: answeringModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  dependsOn: [
    // Deployments on one account must be created serially.
    embeddingDeployment
  ]
}

// -----------------------------------------------------------------------------
// Private endpoint.
// -----------------------------------------------------------------------------

resource openAiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${abbreviations.privateEndpoint}-${openAiName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'account'
        properties: {
          privateLinkServiceId: openAiAccount.id
          groupIds: ['account']
        }
      }
    ]
  }
}

resource openAiPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: openAiPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.openAi, '.', '-')
        properties: {
          privateDnsZoneId: openAiPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Request and audit logs provide the assurance evidence for TAD 10.4.
// -----------------------------------------------------------------------------

resource openAiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: openAiAccount
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

@description('Azure OpenAI account resource identifier.')
output openAiAccountId string = openAiAccount.id

@description('Azure OpenAI account name.')
output openAiAccountName string = openAiAccount.name

@description('Azure OpenAI endpoint. Resolves to a private IP when private endpoints are enabled.')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('Embedding deployment name. Called only for content that has reached Published (TAD 7.2).')
output embeddingDeploymentName string = embeddingDeployment.name

@description('Answering deployment name, or empty when the Ask feature flag is off (TAD 6.3).')
output answeringDeploymentName string = posture.askAnsweringEnabled ? 'docaya-answering' : ''

@description('Principal identifier of the account identity.')
output openAiPrincipalId string = openAiAccount.identity.principalId
