// =============================================================================
// keyvault.bicep
//
// Key Vault with an RBAC data plane and a private endpoint.
//
// Technical Architecture Document v1.3, Section 14.6.4:
//   "Each workload holds Get and List on only the specific secrets it needs.
//    RBAC data plane; private endpoint; soft delete and purge protection
//    enabled; secrets referenced by URI and never emitted to logs or template
//    outputs."
//
// This module therefore emits the vault URI but never a secret value. The
// outputs-should-not-contain-secrets linter rule is on, and would fail the build
// if that rule were broken.
//
// Provisioning order: step 4 (TAD 18.3). Later modules reference secrets by URI
// rather than by value.
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

@description('Whether to create a private endpoint. Optional in dev, enabled in test, enforced by policy in production (TAD 18.6).')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for vault resolution.')
param keyVaultPrivateDnsZoneId string = ''

// -----------------------------------------------------------------------------
// Variables
//
// A vault name is limited to 24 characters, so the region is dropped from the
// name and carried by the tag set instead.
// -----------------------------------------------------------------------------

var keyVaultName = 'kv-docaya-${environmentName}-${take(uniqueString(resourceGroup().id), 6)}'

// -----------------------------------------------------------------------------
// Key Vault
// -----------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId

    // TAD 14.6.4 - RBAC data plane. Access policies are not used: they cannot
    // express least privilege per secret in the way the access matrix requires.
    enableRbacAuthorization: true

    // TAD 14.6.4 - soft delete and purge protection enabled. Purge protection is
    // irreversible once set, which is the point: it prevents an operator or an
    // attacker destroying key material.
    enableSoftDelete: true
    softDeleteRetentionInDays: environmentName == 'prod' ? 90 : 30
    enablePurgeProtection: true

    // The vault is not a deployment parameter source. Templates receive URIs.
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false

    // TAD 16.2 - private-endpoint-only data plane.
    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateEndpointsEnabled ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// -----------------------------------------------------------------------------
// Private endpoint.
//
// TAD 16.2: private DNS resolves the vault name to a private IP inside the
// virtual network, so no data-plane traffic traverses the public internet.
// -----------------------------------------------------------------------------

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${abbreviations.privateEndpoint}-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.keyVault, '.', '-')
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Audit events record every secret read. TAD 15.1 treats key access as a
// monitored control, not an implementation detail.
// -----------------------------------------------------------------------------

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
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
// The vault URI is a locator, not a credential. No secret value is emitted here,
// and the outputs-should-not-contain-secrets rule enforces that.
// -----------------------------------------------------------------------------

@description('Key Vault resource identifier.')
output keyVaultId string = keyVault.id

@description('Key Vault name.')
output keyVaultName string = keyVault.name

@description('Key Vault URI. Secrets are referenced from here by URI and never by value (TAD 14.6.4).')
output keyVaultUri string = keyVault.properties.vaultUri
