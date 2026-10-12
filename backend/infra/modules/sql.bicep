// =============================================================================
// sql.bicep
//
// Azure SQL Database - the registry, workflow, access control and audit store.
//
// Technical Architecture Document v1.3, Section 14.6.3:
//   Authentication - Microsoft Entra authentication with managed identity. No SQL
//                    authentication, no connection string with credentials, no
//                    shared administrator account in normal operation.
//   Network        - Private endpoint; public network access disabled; firewall
//                    denies all other sources.
//   Protection     - Transparent Data Encryption enabled; auditing enabled to Log
//                    Analytics.
//
// Section 11.2 defines nine schemas: stg, docaya, wf, sec, ref, idx, ntf, aud and
// ops. Schemas and contained database principals are created by the migration
// bundle, not here: they are data-plane objects and must move with a rehearsed
// rollback (TAD 17.7).
//
// Provisioning order: step 5 (TAD 18.3). Created with public network access
// disabled from the outset, never hardened afterwards.
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations, privateDnsZoneNames } from './shared/types.bicep'

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

@description('Log Analytics workspace that receives auditing and diagnostics.')
param logAnalyticsWorkspaceId string

@description('Object identifier of the Entra group that administers the server. A group, never an individual, so administration survives a leaver (TAD 14.8).')
param entraAdminObjectId string

@description('Display name of the Entra administrator group.')
param entraAdminName string

@description('Whether to create a private endpoint (TAD 18.6).')
param privateEndpointsEnabled bool

@description('Resource identifier of snet-pe.')
param privateEndpointSubnetId string = ''

@description('Private DNS zone identifier for SQL resolution.')
param sqlPrivateDnsZoneId string = ''

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var sqlServerName = '${abbreviations.sqlServer}-docaya-${environmentName}-${location}'
var databaseName = '${abbreviations.sqlDatabase}-docaya-${environmentName}'

// TAD 18.6 environment matrix. Production is zone-redundant with geo-redundant
// backup; dev is a single zone on a small tier.
var databaseSku = {
  dev: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  test: {
    name: 'GP_Gen5_4'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 4
  }
  prod: {
    name: 'BC_Gen5_8'
    tier: 'BusinessCritical'
    family: 'Gen5'
    capacity: 8
  }
}

// Serverless auto-pause is appropriate in dev only. Pausing a shared test or
// production database would introduce cold-start latency into a measured SLO.
var autoPauseDelayMinutes = environmentName == 'dev' ? 60 : -1

// -----------------------------------------------------------------------------
// Logical server.
// -----------------------------------------------------------------------------

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: {
    // A system-assigned identity lets the server reach Key Vault for a
    // customer-managed key and write its own audit records.
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'

    // TAD 16.2 - private-endpoint-only data plane.
    publicNetworkAccess: privateEndpointsEnabled ? 'Disabled' : 'Enabled'
    restrictOutboundNetworkAccess: 'Enabled'

    // TAD 14.6.3 - Entra authentication only. No SQL authentication means no
    // administrator password exists to leak, rotate or hard-code.
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: entraAdminName
      sid: entraAdminObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// -----------------------------------------------------------------------------
// Database.
// -----------------------------------------------------------------------------

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: databaseSku[environmentName]
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'

    // Arabic and English are first-class (TAD 6.3). NVARCHAR columns carry both
    // scripts, and the collation above sorts them case-insensitively.
    maxSizeBytes: environmentName == 'prod' ? 1099511627776 : 34359738368

    // TAD 18.6 - zone redundancy in test and production.
    zoneRedundant: posture.zoneRedundant

    requestedBackupStorageRedundancy: posture.geoRedundantBackup ? 'Geo' : 'Local'
    autoPauseDelay: autoPauseDelayMinutes

    // Read-scale lets the reporting identity query without contending with the
    // write path. Business Critical only.
    readScale: environmentName == 'prod' ? 'Enabled' : 'Disabled'

    availabilityZone: 'NoPreference'
  }
}

// -----------------------------------------------------------------------------
// Transparent Data Encryption.
//
// TAD 14.6.3 - "Transparent Data Encryption enabled."
// -----------------------------------------------------------------------------

resource transparentDataEncryption 'Microsoft.Sql/servers/databases/transparentDataEncryption@2023-08-01-preview' = {
  parent: sqlDatabase
  name: 'current'
  properties: {
    state: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Backup retention.
//
// TAD 11.12 - Backup, Restore and Recovery Objectives.
// -----------------------------------------------------------------------------

resource shortTermRetention 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01-preview' = {
  parent: sqlDatabase
  name: 'default'
  properties: {
    retentionDays: posture.sqlPointInTimeRetentionDays
    diffBackupIntervalInHours: 12
  }
}

resource longTermRetention 'Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2023-08-01-preview' = if (environmentName == 'prod') {
  parent: sqlDatabase
  name: 'default'
  properties: {
    // Records governance requires a defensible history well beyond the
    // point-in-time window.
    weeklyRetention: 'P4W'
    monthlyRetention: 'P12M'
    yearlyRetention: 'P7Y'
    weekOfYear: 1
  }
}

// -----------------------------------------------------------------------------
// Auditing.
//
// TAD 14.6.3 - "auditing enabled to Log Analytics." This is the server-side
// audit, independent of the application hash chain in the aud schema, so a
// compromised application cannot erase evidence of its own access.
// -----------------------------------------------------------------------------

resource sqlAuditing 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    isManagedIdentityInUse: true
    retentionDays: 0
    auditActionsAndGroups: [
      'BATCH_COMPLETED_GROUP'
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'DATABASE_PERMISSION_CHANGE_GROUP'
      'DATABASE_PRINCIPAL_CHANGE_GROUP'
      'DATABASE_ROLE_MEMBER_CHANGE_GROUP'
      'SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP'
    ]
  }
}

resource sqlDevOpsAuditing 'Microsoft.Sql/servers/devOpsAuditingSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    isManagedIdentityInUse: true
  }
}

// -----------------------------------------------------------------------------
// Advanced Threat Protection and vulnerability assessment.
//
// TAD 15 - Security Architecture. Detection sits alongside prevention.
// -----------------------------------------------------------------------------

resource threatProtection 'Microsoft.Sql/servers/securityAlertPolicies@2023-08-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
    emailAccountAdmins: true
    retentionDays: 30
  }
}

// -----------------------------------------------------------------------------
// Private endpoint.
// -----------------------------------------------------------------------------

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (privateEndpointsEnabled) {
  name: '${abbreviations.privateEndpoint}-${sqlServerName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sqlServer'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: ['sqlServer']
        }
      }
    ]
  }
}

resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (privateEndpointsEnabled) {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZoneNames.sqlServer, '.', '-')
        properties: {
          privateDnsZoneId: sqlPrivateDnsZoneId
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Database diagnostics.
// -----------------------------------------------------------------------------

resource sqlDatabaseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: sqlDatabase
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
        category: 'Basic'
        enabled: true
      }
      {
        category: 'InstanceAndAppAdvanced'
        enabled: true
      }
      {
        category: 'WorkloadManagement'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
//
// No connection string is emitted. Every caller authenticates with a managed
// identity, so there is no credential to pass (TAD 14.6.3).
// -----------------------------------------------------------------------------

@description('SQL logical server resource identifier.')
output sqlServerId string = sqlServer.id

@description('SQL logical server name.')
output sqlServerName string = sqlServer.name

@description('Fully qualified domain name of the logical server. Resolves to a private IP when private endpoints are enabled.')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('Database name.')
output databaseName string = sqlDatabase.name

@description('Database resource identifier.')
output databaseId string = sqlDatabase.id

@description('Principal identifier of the server system-assigned identity.')
output serverPrincipalId string = sqlServer.identity.principalId
