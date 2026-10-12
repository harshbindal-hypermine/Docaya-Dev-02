// =============================================================================
// analytics.bicep
//
// Power BI Embedded prerequisites for M15 reporting.
//
// Technical Architecture Document v1.3, Section 14.6.4:
//   "Power BI Embedded - Service principal generates an embed token carrying the
//    effective identity for the signed-in user. Row-level security mirrors Docaya
//    department and sensitivity scope; direct dataset access is not granted to
//    end users; export controls and scheduled subscriptions are permission-aware."
//
// Section 25.2: analytics reads from the same Azure SQL registry the application
// writes. There is no separate analytics pipeline and no duplicated store.
//
// The Power BI workspace, semantic model and row-level security roles are tenant
// objects, not Azure resources, so they are created by the release pipeline
// against the Power BI REST API. What Bicep owns is the capacity that backs them
// and the Key Vault secret holding the service principal credential.
//
// Provisioning order: step 7 (TAD 18.3).
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

@description('Whether to provision dedicated Power BI Embedded capacity. Shared capacity is sufficient below production.')
param dedicatedCapacityEnabled bool = false

@description('Object identifiers of the Entra principals that administer the capacity. A group, never an individual.')
param capacityAdministrators array = []

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

// A Power BI capacity name must be lowercase alphanumeric.
var capacityName = toLower('pbidocaya${environmentName}${take(uniqueString(resourceGroup().id), 6)}')

// A1 is the smallest embedded capacity. Production sizing follows the load test.
var capacitySku = environmentName == 'prod' ? 'A2' : 'A1'

// -----------------------------------------------------------------------------
// Power BI Embedded capacity.
//
// Created only where the client requires dedicated capacity. A shared workspace
// is sufficient for development and acceptance, and avoids a standing cost.
// -----------------------------------------------------------------------------

resource powerBiCapacity 'Microsoft.PowerBIDedicated/capacities@2021-01-01' = if (dedicatedCapacityEnabled) {
  name: capacityName
  location: location
  tags: tags
  sku: {
    name: capacitySku
    tier: 'PBIE_Azure'
  }
  properties: {
    administration: {
      members: capacityAdministrators
    }
    mode: 'Gen2'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Power BI capacity resource identifier, or empty when dedicated capacity is not provisioned.')
output powerBiCapacityId string = dedicatedCapacityEnabled ? powerBiCapacity.id : ''

@description('Power BI capacity name, or empty when dedicated capacity is not provisioned.')
output powerBiCapacityName string = dedicatedCapacityEnabled ? capacityName : ''

@description('Whether dedicated capacity was provisioned.')
output dedicatedCapacityProvisioned bool = dedicatedCapacityEnabled
