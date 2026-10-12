// =============================================================================
// prod.bicepparam
//
// Production environment. TAD 18.6 - Environment Matrix:
//   Zone-redundant with geo-redundant backup, private endpoints ENFORCED BY
//   POLICY, live residency-pinned data, break-glass and operator access via PIM
//   only, telemetry retention per client policy, and Ask (AI answering)
//   feature-flagged on the POC outcome.
//
// Non-secret values only (TAD 18.2). Every required DOCAYA_* environment value
// must be set before the first deployment, and the what-if output must be
// reviewed by a named approver who is a separate person from the requester
// (TAD 19.2).
// =============================================================================

using '../main.bicep'

param environmentName = 'prod'
param location = 'uaenorth'

param approvedRegions = [
  'uaenorth'
  'uaecentral'
]

param releaseVersion = '1.3.0'
param owner = 'docaya-operations'
param costCentre = readEnvironmentVariable('DOCAYA_COST_CENTRE')

// TAD 18.6 - live, residency-pinned data.
param dataClassification = 'official-internal'

// -----------------------------------------------------------------------------
// Release
//
// Build once, promote unchanged: the binary that passed test is the binary that
// reaches production. Supplied by the release pipeline; a floating tag is
// prohibited (TAD 19.3).
// -----------------------------------------------------------------------------
param apiImageDigest = readEnvironmentVariable('DOCAYA_API_IMAGE_DIGEST')

// -----------------------------------------------------------------------------
// Identity and access
//
// The SQL administrator group should be PIM-eligible rather than permanently
// assigned, so administrative access is time-boxed and session-logged
// (TAD 14.8, 16.3 boundary 5).
// -----------------------------------------------------------------------------
param sqlAdminGroupObjectId = readEnvironmentVariable('DOCAYA_SQL_ADMIN_GROUP_OBJECT_ID')
param sqlAdminGroupName = 'sg-docaya-sql-admins-prod'

param apiAudience = 'api://docaya-api'

// -----------------------------------------------------------------------------
// Network
// -----------------------------------------------------------------------------
param vnetAddressPrefix = '10.42.0.0/16'

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

// Routed to the on-call rota, never to an individual (TAD 28.3).
param alertEmailAddress = readEnvironmentVariable('DOCAYA_ALERT_EMAIL_ADDRESS')
param apiManagementPublisherEmail = readEnvironmentVariable('DOCAYA_APIM_PUBLISHER_EMAIL')

// TAD 16.3 - administrative paths are IP allow-listed in production. Leaving this
// empty disables the restriction, which is NOT acceptable for a live environment.
param administrativeIpAllowList = json(readEnvironmentVariable('DOCAYA_ADMINISTRATIVE_IP_ALLOW_LIST'))

// Production notifications come from a client-owned domain, so they are
// recognisable as originating from the organisation.
param notificationSenderDomain = readEnvironmentVariable('DOCAYA_NOTIFICATION_SENDER_DOMAIN')
param communicationDataLocation = 'UAE'

// Dedicated capacity in production so reporting load cannot contend with a
// shared tenant workspace.
param powerBiDedicatedCapacityEnabled = true
param powerBiCapacityAdministrators = json(readEnvironmentVariable('DOCAYA_POWERBI_CAPACITY_ADMINISTRATORS'))
