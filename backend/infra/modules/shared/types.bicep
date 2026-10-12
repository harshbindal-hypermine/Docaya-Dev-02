// =============================================================================
// types.bicep
//
// Shared user-defined types, CAF abbreviations and role-definition identifiers
// for the Docaya estate.
//
// Technical Architecture Document v1.3, Section 18.1:
//   Naming  - {type}-docaya-{env}-{region} with a documented abbreviation list,
//             so every resource is identifiable from its name alone.
//   Tagging - workload, environment, owner, costCentre, dataClassification,
//             residency and releaseVersion applied to every resource by the
//             template.
//
// Abbreviations follow the Microsoft Cloud Adoption Framework recommended
// abbreviations for Azure resources.
//
// This file declares no resources. It is consumed with `import`.
// =============================================================================

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

@export()
@description('Deployment environment short name.')
type environmentNameType = 'dev' | 'test' | 'prod'

@export()
@description('Mandatory tag set applied to every resource (TAD 18.1).')
type mandatoryTagsType = {
  @description('Always "docaya". Identifies the workload inside a shared subscription.')
  workload: string

  @description('Environment short name.')
  environment: string

  @description('Accountable team or individual.')
  owner: string

  @description('Chargeback code.')
  costCentre: string

  @description('Highest classification of data the resource may hold.')
  dataClassification: 'synthetic' | 'anonymised' | 'official-internal'

  @description('Data residency commitment, pinned for this workload.')
  residency: string

  @description('Semantic version of the release that last deployed the resource.')
  releaseVersion: string

  @description('Additional free-form tags.')
  *: string
}

@export()
@description('Per-environment posture, derived from the TAD 18.6 environment matrix.')
type environmentPostureType = {
  @description('Zone redundancy for stateful services. Single zone in dev.')
  zoneRedundant: bool

  @description('Whether private endpoints are created. Optional in dev, enabled in test, enforced by policy in production.')
  privateEndpointsEnabled: bool

  @description('Telemetry retention in days. 30 in dev, 90 in test, per client policy in production.')
  telemetryRetentionDays: int

  @description('Azure SQL point-in-time restore retention, in days.')
  sqlPointInTimeRetentionDays: int

  @description('Whether geo-redundant backup is required.')
  geoRedundantBackup: bool

  @description('Whether Ask (AI answering) is enabled. Feature-flagged on the POC outcome in production (TAD 6.3).')
  askAnsweringEnabled: bool

  @description('Minimum replica count for the API container app.')
  apiMinReplicas: int

  @description('Maximum replica count for the API container app.')
  apiMaxReplicas: int
}

@export()
@description('Resolved private DNS zone identifiers, keyed by the service each resolves.')
type privateDnsZoneIdsType = {
  sqlServer: string
  blob: string
  file: string
  queue: string
  table: string
  keyVault: string
  serviceBus: string
  search: string
  openAi: string
  containerRegistry: string
  signalR: string
}

@export()
@description('Principal identifiers of the six workload identities (TAD appendix A).')
type workloadPrincipalsType = {
  @description('Runtime API and backend-for-frontend.')
  api: string

  @description('Upload session and staging processing.')
  capture: string

  @description('Promotion of approved documents into SharePoint.')
  promotion: string

  @description('Index build and reconcile.')
  indexing: string

  @description('Orchestration, SLA and outbox dispatch.')
  workflow: string

  @description('Power BI semantic model refresh.')
  analytics: string
}

// -----------------------------------------------------------------------------
// CAF resource type abbreviations.
// Held in one place so a name can never drift between modules.
// -----------------------------------------------------------------------------

@export()
@description('Cloud Adoption Framework abbreviations for every resource type in the estate.')
var abbreviations = {
  resourceGroup: 'rg'
  virtualNetwork: 'vnet'
  subnet: 'snet'
  networkSecurityGroup: 'nsg'
  privateEndpoint: 'pep'
  natGateway: 'ng'
  publicIpAddress: 'pip'
  userAssignedIdentity: 'id'
  keyVault: 'kv'
  sqlServer: 'sql'
  sqlDatabase: 'sqldb'
  storageAccount: 'st'
  serviceBusNamespace: 'sbns'
  searchService: 'srch'
  openAiService: 'oai'
  containerRegistry: 'cr'
  containerAppsEnvironment: 'cae'
  containerApp: 'ca'
  appServicePlan: 'asp'
  functionApp: 'func'
  staticWebApp: 'stapp'
  apiManagement: 'apim'
  frontDoor: 'afd'
  wafPolicy: 'waf'
  signalR: 'sigr'
  communicationServices: 'acs'
  logAnalyticsWorkspace: 'log'
  applicationInsights: 'appi'
  actionGroup: 'ag'
}

// -----------------------------------------------------------------------------
// Subnet names, from TAD 16.1 - Subnet Design.
//
//   snet-edge  API Management, internal mode.   In: Front Door only.
//   snet-app   Container Apps, API and BFF.     In: snet-edge only.
//   snet-func  Functions workers.               In: Service Bus and timers.
//   snet-pe    Private endpoints.               In: snet-app and snet-func.
//   snet-mgmt  Deployment and break-glass.      Out: control plane only.
// -----------------------------------------------------------------------------

@export()
@description('Subnet names from TAD 16.1 - Subnet Design.')
var subnetNames = {
  edge: 'snet-edge'
  app: 'snet-app'
  func: 'snet-func'
  privateEndpoint: 'snet-pe'
  management: 'snet-mgmt'
}

// -----------------------------------------------------------------------------
// Private DNS zone names.
//
// TAD 16.2: private DNS resolves every service name to a private IP inside the
// virtual network, so no data-plane traffic traverses the public internet.
//
// Composed from environment() where a suffix is available, so the templates stay
// correct in sovereign clouds rather than hard-coding commercial-cloud suffixes.
// -----------------------------------------------------------------------------

@export()
@description('Private DNS zone names, keyed by the service they resolve.')
var privateDnsZoneNames = {
  sqlServer: 'privatelink${environment().suffixes.sqlServerHostname}'
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  file: 'privatelink.file.${environment().suffixes.storage}'
  queue: 'privatelink.queue.${environment().suffixes.storage}'
  table: 'privatelink.table.${environment().suffixes.storage}'
  keyVault: 'privatelink${environment().suffixes.keyvaultDns}'
  serviceBus: 'privatelink.servicebus.windows.net'
  search: 'privatelink.search.windows.net'
  openAi: 'privatelink.openai.azure.com'
  containerRegistry: 'privatelink.azurecr.io'
  signalR: 'privatelink.service.signalr.net'
}

// -----------------------------------------------------------------------------
// Built-in Azure role definition GUIDs.
//
// Referenced by the rbac module so every grant in the TAD 14.6 and 14.7 access
// matrix is expressed by name rather than by an opaque identifier.
//
//   storageBlobDataContributor  Granted at CONTAINER scope only, never account.
//   keyVaultSecretsUser         Get and List on named secrets only.
//   searchIndexDataReader       API identity - query only.
//   searchIndexDataContributor  Indexing identity - write only.
//   serviceBusDataSender        Send on publishing topics.
//   serviceBusDataReceiver      Receive on its own subscriptions only.
//   acrPull                     Image pull by digest.
// -----------------------------------------------------------------------------

@export()
@description('Built-in role definition GUIDs used by the least-privilege grants in TAD 14.6 and 14.7.')
var roleDefinitionIds = {
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  serviceBusDataSender: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
  serviceBusDataReceiver: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  cognitiveServicesOpenAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  monitoringReader: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
  signalRAppServer: '420fcaa2-552c-430f-98ca-3264be4806c7'
}

// -----------------------------------------------------------------------------
// Service Bus entities. The domain event catalogue is TAD 24.3.
//
// Ordering matters for stage transitions on one document, so the topic is
// session-enabled on the document identifier (TAD 24.4). FinalApprovalGranted
// has a single consumer - the promotion worker - with an exactly-once effect
// enforced by ops.PromotionLedger.
// -----------------------------------------------------------------------------

@export()
@description('Service Bus topic and subscription names (TAD 24.3, 24.4).')
var messaging = {
  documentEventsTopic: 'docaya-document-events'
  promotionSubscription: 'promotion'
  indexingSubscription: 'indexing'
  notificationSubscription: 'notification'
  workflowSubscription: 'workflow'
  auditSubscription: 'audit'
}

// -----------------------------------------------------------------------------
// Blob containers.
//
// TAD 14.6.2 container separation: separate containers for upload chunks,
// committed staged files, extraction output and thumbnails, each with its own
// lifecycle rule. Quarantine holds anything that fails malware, DLP or the
// published-hash check (TAD 7.2).
// -----------------------------------------------------------------------------

@export()
@description('Blob container names (TAD 14.6.2 - Container separation).')
var blobContainers = {
  chunks: 'upload-chunks'
  staged: 'staged-files'
  extraction: 'extraction'
  thumbnails: 'thumbnails'
  quarantine: 'quarantine'
}

// -----------------------------------------------------------------------------
// Azure SQL database principals.
//
// TAD 14.6.3 grants one contained database principal per workload identity, so a
// compromised worker cannot read outside the schemas it needs:
//
//   docaya_api      SELECT/INSERT/UPDATE on docaya, wf, ntf; idx read;
//                   INSERT+SELECT only on aud; SELECT on ref and rpt.
//   docaya_capture  SELECT/INSERT/UPDATE on stg only.
//   docaya_worker   SELECT/INSERT/UPDATE on wf, ops; INSERT on aud.
//   docaya_index    SELECT on docaya, ref; SELECT/INSERT/UPDATE on idx.
//   docaya_report   SELECT on rpt views only.
//   docaya_migrate  DDL rights - release pipeline only.
//
// The principals are created by the migration bundle, not by Bicep: a contained
// database user is a data-plane object.
// -----------------------------------------------------------------------------

@export()
@description('Contained database principal names granted to each workload identity (TAD 14.6.3).')
var sqlPrincipals = {
  api: 'docaya_api'
  capture: 'docaya_capture'
  worker: 'docaya_worker'
  index: 'docaya_index'
  report: 'docaya_report'
  migrate: 'docaya_migrate'
}
