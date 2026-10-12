// =============================================================================
// identity.bicep
//
// The six user-assigned managed identities that carry every workload operation.
//
// Technical Architecture Document v1.3, appendix A:
//   "Managed identities (6) - API, capture, promotion, indexing, workflow,
//    analytics."
//
// TAD 14.1 - the two-plane model. The user token stops at the Docaya API and is
// never forwarded. A governed service identity performs all content operations,
// recording the real user as actor and itself as executor.
//
// User-assigned rather than system-assigned, deliberately: role assignments in
// the rbac module need the principal identifier to exist before the compute that
// uses it, and a user-assigned identity survives replacement of its host.
//
// Provisioning order: step 2 (TAD 18.3). Role assignments in step 9 reference
// these principal identifiers.
// =============================================================================

import { mandatoryTagsType, abbreviations } from './shared/types.bicep'

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

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var namePrefix = '${abbreviations.userAssignedIdentity}-docaya'
var nameSuffix = '${environmentName}-${location}'

// One identity per function, so a grant can be revoked from one workload without
// affecting another, and so the access matrix in TAD 14.7 maps one-to-one onto
// real principals.
var identityDefinitions = [
  {
    key: 'api'
    name: '${namePrefix}-api-${nameSuffix}'
    purpose: 'Runtime API and backend-for-frontend. Reads and writes the registry, sends domain events, queries the search index.'
  }
  {
    key: 'capture'
    name: '${namePrefix}-capture-${nameSuffix}'
    purpose: 'Upload session and staging processing. Writes chunks and committed staged files only.'
  }
  {
    key: 'promotion'
    name: '${namePrefix}-promotion-${nameSuffix}'
    purpose: 'Promotes approved documents into SharePoint through Microsoft Graph under Sites.Selected.'
  }
  {
    key: 'indexing'
    name: '${namePrefix}-indexing-${nameSuffix}'
    purpose: 'Builds and reconciles the Document Index Record. Write-only against the search index.'
  }
  {
    key: 'workflow'
    name: '${namePrefix}-workflow-${nameSuffix}'
    purpose: 'Orchestration, SLA evaluation and transactional outbox dispatch.'
  }
  {
    key: 'analytics'
    name: '${namePrefix}-analytics-${nameSuffix}'
    purpose: 'Power BI semantic model refresh. Reads reporting views only.'
  }
]

// -----------------------------------------------------------------------------
// Identities
// -----------------------------------------------------------------------------

resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [
  for definition in identityDefinitions: {
    name: definition.name
    location: location
    tags: union(tags, {
      purpose: definition.purpose
    })
  }
]

// -----------------------------------------------------------------------------
// Outputs
//
// Both the principal identifier - needed for role assignments - and the resource
// identifier - needed to attach the identity to compute - are returned.
// -----------------------------------------------------------------------------

@description('Principal identifiers of the six workload identities, for role assignment.')
output principalIds object = {
  api: workloadIdentity[0].properties.principalId
  capture: workloadIdentity[1].properties.principalId
  promotion: workloadIdentity[2].properties.principalId
  indexing: workloadIdentity[3].properties.principalId
  workflow: workloadIdentity[4].properties.principalId
  analytics: workloadIdentity[5].properties.principalId
}

@description('Resource identifiers of the six workload identities, for attachment to compute.')
output resourceIds object = {
  api: workloadIdentity[0].id
  capture: workloadIdentity[1].id
  promotion: workloadIdentity[2].id
  indexing: workloadIdentity[3].id
  workflow: workloadIdentity[4].id
  analytics: workloadIdentity[5].id
}

@description('Client identifiers of the six workload identities, for application configuration.')
output clientIds object = {
  api: workloadIdentity[0].properties.clientId
  capture: workloadIdentity[1].properties.clientId
  promotion: workloadIdentity[2].properties.clientId
  indexing: workloadIdentity[3].properties.clientId
  workflow: workloadIdentity[4].properties.clientId
  analytics: workloadIdentity[5].properties.clientId
}

@description('Identity names, for the contained database principals created by the migration bundle.')
output identityNames object = {
  api: workloadIdentity[0].name
  capture: workloadIdentity[1].name
  promotion: workloadIdentity[2].name
  indexing: workloadIdentity[3].name
  workflow: workloadIdentity[4].name
  analytics: workloadIdentity[5].name
}
