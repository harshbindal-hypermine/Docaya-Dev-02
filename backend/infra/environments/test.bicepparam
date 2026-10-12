// =============================================================================
// test.bicepparam
//
// Test and UAT environment. TAD 18.6 - Environment Matrix:
//   Zone-redundant, private endpoints enabled, anonymised data, release and QA
//   access, 90-day telemetry retention, Ask enabled for acceptance.
//
// Non-secret values only (TAD 18.2).
// =============================================================================

using '../main.bicep'

param environmentName = 'test'
param location = 'uaenorth'

param approvedRegions = [
  'uaenorth'
  'uaecentral'
]

param releaseVersion = '1.3.0'
param owner = 'docaya-engineering'
param costCentre = readEnvironmentVariable('DOCAYA_COST_CENTRE')

// TAD 18.6 - test carries anonymised data, never live records.
param dataClassification = 'anonymised'

// -----------------------------------------------------------------------------
// Release
//
// Build once, promote unchanged. The digest that passed dev is the digest
// deployed here - nothing is rebuilt per environment (TAD 19.3).
// -----------------------------------------------------------------------------
param apiImageDigest = readEnvironmentVariable('DOCAYA_API_IMAGE_DIGEST')

// -----------------------------------------------------------------------------
// Identity and access
// -----------------------------------------------------------------------------
param sqlAdminGroupObjectId = readEnvironmentVariable('DOCAYA_SQL_ADMIN_GROUP_OBJECT_ID')
param sqlAdminGroupName = 'sg-docaya-sql-admins-test'

param apiAudience = 'api://docaya-api-test'

// -----------------------------------------------------------------------------
// Network
//
// A distinct range from dev and production, so the environments can never be
// peered by accident into an overlapping space.
// -----------------------------------------------------------------------------
param vnetAddressPrefix = '10.41.0.0/16'

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------
param alertEmailAddress = readEnvironmentVariable('DOCAYA_ALERT_EMAIL_ADDRESS')
param apiManagementPublisherEmail = readEnvironmentVariable('DOCAYA_APIM_PUBLISHER_EMAIL')

// Administrative paths are restricted to the corporate egress ranges. Populate
// before the first deployment (TAD 16.3).
param administrativeIpAllowList = json(readEnvironmentVariable('DOCAYA_ADMINISTRATIVE_IP_ALLOW_LIST'))

param notificationSenderDomain = ''
param communicationDataLocation = 'UAE'

param powerBiDedicatedCapacityEnabled = false
param powerBiCapacityAdministrators = []
