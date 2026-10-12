// =============================================================================
// dev.bicepparam
//
// Development environment. TAD 18.6 - Environment Matrix:
//   Single zone, private endpoints optional, synthetic data only, developer
//   access, 30-day telemetry retention, Ask enabled for development.
//
// Non-secret values only (TAD 18.2). The image digest is supplied by the
// pipeline at deploy time and overrides the placeholder below.
// =============================================================================

using '../main.bicep'

param environmentName = 'dev'
param location = 'uaenorth'

// Residency is pinned. The paired region appears here only so a backup or
// recovery resource is not blocked by policy.
param approvedRegions = [
  'uaenorth'
  'uaecentral'
]

param releaseVersion = '1.3.0'
param owner = 'docaya-engineering'
param costCentre = readEnvironmentVariable('DOCAYA_COST_CENTRE')

// Dev carries synthetic documents only (TAD 17.6).
param dataClassification = 'synthetic'

// -----------------------------------------------------------------------------
// Release
//
// Supplied by the release pipeline or the local deployment environment:
//   az deployment sub create ... --parameters apiImageDigest=sha256:<digest>
//
// A floating tag is prohibited: the digest is what makes rollback deterministic
// (TAD 18.4).
// -----------------------------------------------------------------------------
param apiImageDigest = readEnvironmentVariable('DOCAYA_API_IMAGE_DIGEST')

// -----------------------------------------------------------------------------
// Identity and access
//
// DOCAYA_SQL_ADMIN_GROUP_OBJECT_ID must identify an Entra GROUP, never an
// individual, so administration survives a leaver (TAD 14.8).
// -----------------------------------------------------------------------------
param sqlAdminGroupObjectId = readEnvironmentVariable('DOCAYA_SQL_ADMIN_GROUP_OBJECT_ID')
param sqlAdminGroupName = 'sg-docaya-sql-admins-dev'

// Application ID URI of the Docaya API registration, validated as the token
// audience at the gateway and again at the API (TAD 24.1).
param apiAudience = 'api://docaya-api-dev'

// -----------------------------------------------------------------------------
// Network
// -----------------------------------------------------------------------------
param vnetAddressPrefix = '10.40.0.0/16'

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------
param alertEmailAddress = readEnvironmentVariable('DOCAYA_ALERT_EMAIL_ADDRESS')
param apiManagementPublisherEmail = readEnvironmentVariable('DOCAYA_APIM_PUBLISHER_EMAIL')

// Empty disables the administrative allow-list, which is appropriate in dev.
param administrativeIpAllowList = []

// An Azure-managed sender domain needs no DNS verification, which suits dev.
param notificationSenderDomain = ''
param communicationDataLocation = 'UAE'

// Shared capacity is sufficient below production.
param powerBiDedicatedCapacityEnabled = false
param powerBiCapacityAdministrators = []
