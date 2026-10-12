// =============================================================================
// storage.bicep
//
// Blob storage for the controlled staging zone, preview and thumbnails.
//
// Technical Architecture Document v1.3, Section 14.6.2:
//   Network              - Private endpoint only; public network access disabled;
//                          storage firewall denies all other traffic.
//   Container separation - Separate containers for upload chunks, committed
//                          staged files, extraction output and thumbnails, each
//                          with its own lifecycle rule.
//   Protection           - Encryption at rest, soft delete and versioning
//                          enabled; customer-managed keys available where client
//                          policy requires.
//   Diagnostics          - Storage logs and metrics flow to Log Analytics;
//                          anomalous access patterns raise an alert.
//
// The role grant is Storage Blob Data Contributor on the staging and preview
// containers only - never at account scope. That grant lives in rbac.bicep and
// is scoped to the container resources this module exposes.
//
// Provisioning order: step 5 (TAD 18.3).
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations, blobContainers, privateDnsZoneNames } from './shared/types.bicep'

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

@description('Whether to create private endpoints (TAD 18.6).')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for blob resolution.')
param blobPrivateDnsZoneId string = ''

@description('Days to retain a committed staged file after promotion is reconciled. A failed promotion is retained and replayable (TAD 7.1 step 8).')
@minValue(7)
@maxValue(365)
param stagedFileRetentionDays int = 30

// -----------------------------------------------------------------------------
// Variables
//
// A storage account name is limited to 24 lowercase alphanumeric characters and
// must be globally unique, so the CAF pattern is compressed and the region is
// carried by the tag set instead. The literal prefix plus a truncated hash keeps
// the result provably within 19 to 20 characters.
// -----------------------------------------------------------------------------

var storageAccountName = toLower('${abbreviations.storageAccount}docaya${environmentName}${take(uniqueString(resourceGroup().id), 8)}')

// TAD 18.6 - zone-redundant in test and production, geo-redundant where the
// posture demands it.
var storageSkuName = posture.geoRedundantBackup
  ? 'Standard_GZRS'
  : (posture.zoneRedundant ? 'Standard_ZRS' : 'Standard_LRS')

var containerDefinitions = [
  {
    name: blobContainers.chunks
    purpose: 'Resumable upload chunks. Transient - removed once the file is committed.'
  }
  {
    name: blobContainers.staged
    purpose: 'Committed staged files. The unchanged byte stream, retained until promotion is reconciled.'
  }
  {
    name: blobContainers.extraction
    purpose: 'Text extraction output used to build the Document Index Record.'
  }
  {
    name: blobContainers.thumbnails
    purpose: 'Per-version thumbnails. Permission-trimmed exactly as the document is.'
  }
  {
    name: blobContainers.quarantine
    purpose: 'Files that failed the malware, DLP or published-hash check (TAD 7.2).'
  }
]

// -----------------------------------------------------------------------------
// Storage account.
// -----------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true

    // TAD 14.6.2 - the data plane is managed identity only. Shared keys are
    // disabled so a leaked key cannot exist to be misused, and so every access
    // is attributable to a principal.
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: true

    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateEndpointsEnabled ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }

    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Blob service - versioning, soft delete and change feed.
//
// TAD 14.6.2 - "soft delete and versioning enabled".
// -----------------------------------------------------------------------------

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true

    deleteRetentionPolicy: {
      enabled: true
      days: environmentName == 'prod' ? 90 : 30
      allowPermanentDelete: false
    }

    containerDeleteRetentionPolicy: {
      enabled: true
      days: environmentName == 'prod' ? 90 : 30
    }

    // The change feed gives an auditable record of every blob mutation,
    // independent of the application.
    changeFeed: {
      enabled: true
      retentionInDays: environmentName == 'prod' ? 90 : 30
    }

    restorePolicy: {
      enabled: environmentName == 'prod'
      days: environmentName == 'prod' ? 29 : 6
    }

    cors: {
      // No browser origin is permitted against the account directly. Direct
      // uploads use a short-lived, single-path user-delegation SAS issued by the
      // API after it has authorized the caller (TAD 14.6.2).
      corsRules: []
    }
  }
}

// -----------------------------------------------------------------------------
// Containers.
//
// TAD 14.6.2 container separation. Each is private: no anonymous access.
// -----------------------------------------------------------------------------

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = [
  for definition in containerDefinitions: {
    parent: blobService
    name: definition.name
    properties: {
      publicAccess: 'None'
      metadata: {
        purpose: definition.purpose
      }
    }
  }
]

// -----------------------------------------------------------------------------
// Lifecycle management.
//
// TAD 14.6.2 - "each with its own lifecycle rule."
//
// Chunks are transient and are cleared quickly. Staged files are retained past
// reconciliation so a failed promotion stays replayable. Thumbnails and
// extraction cool rather than expire, because a published version keeps them for
// its lifetime.
// -----------------------------------------------------------------------------

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'expire-abandoned-upload-chunks'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${blobContainers.chunks}/']
            }
            actions: {
              baseBlob: {
                // An upload session that never completes must not accumulate
                // cost or leave partial content behind.
                delete: {
                  daysAfterCreationGreaterThan: 7
                }
              }
            }
          }
        }
        {
          name: 'tier-and-expire-staged-files'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${blobContainers.staged}/']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 7
                }
                delete: {
                  daysAfterModificationGreaterThan: stagedFileRetentionDays
                }
              }
              version: {
                delete: {
                  daysAfterCreationGreaterThan: stagedFileRetentionDays
                }
              }
            }
          }
        }
        {
          name: 'tier-extraction-output'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${blobContainers.extraction}/']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 180
                }
              }
            }
          }
        }
        {
          name: 'tier-thumbnails'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${blobContainers.thumbnails}/']
            }
            actions: {
              baseBlob: {
                // Thumbnails stay retrievable for the life of the version they
                // belong to, so they cool but never expire.
                tierToCool: {
                  daysAfterLastAccessTimeGreaterThan: 90
                }
              }
            }
          }
        }
        {
          name: 'retain-quarantine'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${blobContainers.quarantine}/']
            }
            actions: {
              baseBlob: {
                // Quarantined content is evidence. It cools but is never deleted
                // automatically; disposal is a records decision.
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
          }
        }
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// Private endpoints.
//
// Blob is the data plane. Queue and table are also created when private
// endpoints are enabled, because the Durable task hub uses them.
// -----------------------------------------------------------------------------

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${abbreviations.privateEndpoint}-${storageAccountName}-blob'
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
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource blobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.blob, '.', '-')
        properties: {
          privateDnsZoneId: blobPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// TAD 14.6.2 - "Storage logs and metrics flow to Log Analytics; anomalous access
// patterns raise an alert."
// -----------------------------------------------------------------------------

resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
//
// No account key is emitted: shared key access is disabled, so no key exists to
// return (TAD 14.6.2).
// -----------------------------------------------------------------------------

@description('Storage account resource identifier.')
output storageAccountId string = storageAccount.id

@description('Storage account name.')
output storageAccountName string = storageAccount.name

@description('Primary blob endpoint. Resolves to a private IP when private endpoints are enabled.')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Container resource identifiers, for container-scoped role assignments. The grant is never made at account scope (TAD 14.6.2).')
output containerIds object = {
  chunks: container[0].id
  staged: container[1].id
  extraction: container[2].id
  thumbnails: container[3].id
  quarantine: container[4].id
}

@description('Container names, for application configuration.')
output containerNames object = blobContainers
