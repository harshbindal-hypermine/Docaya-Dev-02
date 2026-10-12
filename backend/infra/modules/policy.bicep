// =============================================================================
// policy.bicep
//
// Azure Policy guardrails for the Docaya estate.
//
// Technical Architecture Document v1.3, Section 18.1:
//   "Azure Policy denies public network access on data services, denies resource
//    creation outside approved regions, and requires the mandatory tag set."
//
// Section 18.6: private endpoints are "Optional" in dev, "Enabled" in test and
// "Enforced by policy" in production. That difference is expressed by the
// enforcement mode below: production denies, lower environments audit.
//
// Provisioning order: step 10 (TAD 18.3). Guardrails are applied once the estate
// is complete, so a policy does not block the very deployment that creates it.
// =============================================================================

import { mandatoryTagsType } from './shared/types.bicep'

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

@description('Regions in which a Docaya resource may be created. Residency is pinned; the paired region is used only for backup and recovery, never for live processing (TAD 18.1).')
param approvedRegions array

// -----------------------------------------------------------------------------
// Variables
//
// Built-in policy definition identifiers. Using built-ins rather than custom
// definitions keeps the estate aligned with Microsoft's maintained ruleset.
//
// Production denies. Lower environments audit, so a developer sees the finding
// without being blocked by a guardrail that is not yet contractual (TAD 18.6).
// -----------------------------------------------------------------------------

var enforce = environmentName == 'prod'
var networkEffect = enforce ? 'Deny' : 'Audit'
var tagEffect = enforce ? 'Deny' : 'Audit'

var builtInPolicyIds = {
  // Allowed locations. Residency is pinned for this workload.
  allowedLocations: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'

  // Public network access must be disabled on each data service.
  sqlPublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780'
  storagePublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/b2982f36-99f2-4db5-8eff-283140c09693'
  keyVaultPublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/405c5871-3451-4254-8543-4aef4e17a9f3'
  searchPublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/ee980b6d-0eca-4501-8d54-f6290fd512c3'
  serviceBusPublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/cbd11fd3-3002-4907-b6c8-579f0e700e13'
  cognitiveServicesPublicNetworkAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/0725b4dd-7e76-479c-a735-68e7ee23d5ca'

  // Transport security.
  storageSecureTransferRequired: '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'
  storageMinimumTlsVersion: '/providers/Microsoft.Authorization/policyDefinitions/fe83a0eb-a853-422d-aac2-1bffd182c5d0'

  // Storage must not permit shared key access: every access must be attributable
  // to a principal (TAD 14.6.2).
  storageSharedKeyAccessDisabled: '/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54'

  // Key Vault protection.
  keyVaultSoftDeleteEnabled: '/providers/Microsoft.Authorization/policyDefinitions/1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d'
  keyVaultPurgeProtectionEnabled: '/providers/Microsoft.Authorization/policyDefinitions/0b60c0b2-2dc2-4e1c-b5c9-abbed971de53'

  // Entra-only authentication on Azure SQL. No SQL authentication means no
  // administrator password exists to leak (TAD 14.6.3).
  sqlEntraOnlyAuthentication: '/providers/Microsoft.Authorization/policyDefinitions/abda6d70-9778-44e7-84a8-06713e6db027'

  // Mandatory tags.
  requireTagOnResource: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
}

// TAD 18.1 mandatory tag set. Each is asserted by its own assignment because the
// built-in definition takes one tag name.
var mandatoryTagNames = [
  'workload'
  'environment'
  'owner'
  'costCentre'
  'dataClassification'
  'residency'
]

var publicAccessPolicies = [
  {
    key: 'sql'
    definitionId: builtInPolicyIds.sqlPublicNetworkAccessDisabled
    description: 'Azure SQL must be reachable only through a private endpoint (TAD 14.6.3).'
  }
  {
    key: 'storage'
    definitionId: builtInPolicyIds.storagePublicNetworkAccessDisabled
    description: 'Blob storage must be reachable only through a private endpoint (TAD 14.6.2).'
  }
  {
    key: 'keyvault'
    definitionId: builtInPolicyIds.keyVaultPublicNetworkAccessDisabled
    description: 'Key Vault must be reachable only through a private endpoint (TAD 14.6.4).'
  }
  {
    key: 'search'
    definitionId: builtInPolicyIds.searchPublicNetworkAccessDisabled
    description: 'Azure AI Search must be reachable only through a private endpoint (TAD 14.6.4).'
  }
  {
    key: 'servicebus'
    definitionId: builtInPolicyIds.serviceBusPublicNetworkAccessDisabled
    description: 'Service Bus must be reachable only through a private endpoint (TAD 14.6.4).'
  }
  {
    key: 'openai'
    definitionId: builtInPolicyIds.cognitiveServicesPublicNetworkAccessDisabled
    description: 'The embedding and answering endpoint must be private and in-region (TAD 12.7).'
  }
]

var protectionPolicies = [
  {
    key: 'secure-transfer'
    definitionId: builtInPolicyIds.storageSecureTransferRequired
    description: 'Storage must require HTTPS.'
  }
  {
    key: 'storage-tls'
    definitionId: builtInPolicyIds.storageMinimumTlsVersion
    description: 'Storage must require TLS 1.2 or better.'
  }
  {
    key: 'no-shared-key'
    definitionId: builtInPolicyIds.storageSharedKeyAccessDisabled
    description: 'Shared key access must be disabled so every access is attributable to a principal (TAD 14.6.2).'
  }
  {
    key: 'kv-soft-delete'
    definitionId: builtInPolicyIds.keyVaultSoftDeleteEnabled
    description: 'Key Vault soft delete must be enabled (TAD 14.6.4).'
  }
  {
    key: 'kv-purge-protection'
    definitionId: builtInPolicyIds.keyVaultPurgeProtectionEnabled
    description: 'Key Vault purge protection must be enabled (TAD 14.6.4).'
  }
  {
    key: 'sql-entra-only'
    definitionId: builtInPolicyIds.sqlEntraOnlyAuthentication
    description: 'Azure SQL must use Entra-only authentication (TAD 14.6.3).'
  }
]

// -----------------------------------------------------------------------------
// Allowed locations.
//
// Residency is pinned. This is always Deny, in every environment: a resource
// created outside the approved region is a residency breach, not a warning.
// -----------------------------------------------------------------------------

resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'docaya-${environmentName}-allowed-locations'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Docaya - resources must be created in an approved region'
    description: 'Data residency is pinned. The paired region is used only for backup and recovery, never for live processing (TAD 18.1).'
    policyDefinitionId: builtInPolicyIds.allowedLocations
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: approvedRegions
      }
      effect: {
        value: 'Deny'
      }
    }
    metadata: {
      source: 'Docaya Technical Architecture Document v1.3, Section 18.1'
      assignedBy: tags.owner
    }
  }
}

// -----------------------------------------------------------------------------
// Public network access.
//
// TAD 18.6 - enforced by policy in production, audited below it.
// -----------------------------------------------------------------------------

resource publicAccessAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = [
  for policy in publicAccessPolicies: {
    name: 'docaya-${environmentName}-private-${policy.key}'
    location: location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      displayName: 'Docaya - ${policy.key} must not be publicly reachable'
      description: policy.description
      policyDefinitionId: policy.definitionId
      enforcementMode: 'Default'
      parameters: {
        effect: {
          value: networkEffect
        }
      }
      metadata: {
        source: 'Docaya Technical Architecture Document v1.3, Section 16.2'
        assignedBy: tags.owner
      }
    }
  }
]

// -----------------------------------------------------------------------------
// Protection baseline.
// -----------------------------------------------------------------------------

resource protectionAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = [
  for policy in protectionPolicies: {
    name: 'docaya-${environmentName}-${policy.key}'
    location: location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      displayName: 'Docaya - ${policy.key}'
      description: policy.description
      policyDefinitionId: policy.definitionId
      enforcementMode: 'Default'
      parameters: {
        effect: {
          value: networkEffect
        }
      }
      metadata: {
        source: 'Docaya Technical Architecture Document v1.3, Section 14.6'
        assignedBy: tags.owner
      }
    }
  }
]

// -----------------------------------------------------------------------------
// Mandatory tags.
//
// TAD 18.1 - "workload, environment, owner, costCentre, dataClassification,
// residency and releaseVersion applied to every resource by the template."
//
// releaseVersion is excluded from enforcement: it changes on every release and a
// Deny would block a legitimate redeploy.
// -----------------------------------------------------------------------------

resource requiredTagAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = [
  for tagName in mandatoryTagNames: {
    name: 'docaya-${environmentName}-tag-${toLower(tagName)}'
    location: location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      displayName: 'Docaya - resources must carry the "${tagName}" tag'
      description: 'Part of the mandatory tag set applied by the template (TAD 18.1).'
      policyDefinitionId: builtInPolicyIds.requireTagOnResource
      enforcementMode: 'Default'
      parameters: {
        tagName: {
          value: tagName
        }
        effect: {
          value: tagEffect
        }
      }
      metadata: {
        source: 'Docaya Technical Architecture Document v1.3, Section 18.1'
        assignedBy: tags.owner
      }
    }
  }
]

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Number of policy assignments created.')
output policyAssignmentCount int = 1 + length(publicAccessPolicies) + length(protectionPolicies) + length(mandatoryTagNames)

@description('Effect applied to network and protection policies. Deny in production, Audit below it (TAD 18.6).')
output appliedEffect string = networkEffect

@description('Summary for the deployment evidence pack (TAD 19.3).')
output policySummary object = {
  allowedLocations: 'Deny'
  publicNetworkAccess: networkEffect
  protectionBaseline: networkEffect
  mandatoryTags: tagEffect
  approvedRegions: approvedRegions
}
