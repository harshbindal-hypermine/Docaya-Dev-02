// =============================================================================
// communication.bicep
//
// Azure Communication Services for email delivery (M7).
//
// Technical Architecture Document v1.3, appendix A:
//   "Communication Services - Email delivery. Microsoft backbone."
//
// Section 14.6.4: "Notification identity sends via Communication Services and
// Graph. Recipients are resolved from entitlement, never from a user-supplied
// list; security notifications cannot be disabled by a user."
//
// Data location is pinned so notification content stays inside the residency
// boundary (TAD 12.7).
//
// Provisioning order: step 7 (TAD 18.3).
// =============================================================================

import { mandatoryTagsType, abbreviations } from './shared/types.bicep'

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Environment short name.')
@allowed(['dev', 'test', 'prod'])
param environmentName string

@description('Mandatory tag set (TAD 18.1).')
param tags mandatoryTagsType

@description('Log Analytics workspace that receives diagnostics.')
param logAnalyticsWorkspaceId string

@description('Data residency for stored notification content. Must match the client residency commitment (TAD 12.7).')
@allowed(['Africa', 'Asia Pacific', 'Australia', 'Brazil', 'Canada', 'Europe', 'France', 'Germany', 'India', 'Japan', 'Korea', 'Norway', 'Switzerland', 'UAE', 'UK', 'United States'])
param dataLocation string = 'UAE'

@description('Custom email sender domain. Leave empty to use an Azure-managed domain, which is appropriate for dev and test only.')
param customSenderDomain string = ''

// -----------------------------------------------------------------------------
// Variables
//
// Communication Services and its email service are global resources.
// -----------------------------------------------------------------------------

var communicationServiceName = '${abbreviations.communicationServices}-docaya-${environmentName}'
var emailServiceName = '${abbreviations.communicationServices}-email-docaya-${environmentName}'
var useCustomDomain = !empty(customSenderDomain)

// -----------------------------------------------------------------------------
// Email service and sender domain.
// -----------------------------------------------------------------------------

resource emailService 'Microsoft.Communication/emailServices@2023-06-01-preview' = {
  name: emailServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: dataLocation
  }
}

// An Azure-managed domain requires no DNS verification, which suits dev and test.
// Production uses a client-owned domain so notifications come from the
// organisation rather than from an Azure subdomain.
resource azureManagedDomain 'Microsoft.Communication/emailServices/domains@2023-06-01-preview' = if (!useCustomDomain) {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  tags: tags
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

resource customDomain 'Microsoft.Communication/emailServices/domains@2023-06-01-preview' = if (useCustomDomain) {
  parent: emailService
  name: customSenderDomain
  location: 'global'
  tags: tags
  properties: {
    domainManagement: 'CustomerManaged'
    // Engagement tracking records whether a recipient opened a notification.
    // That is behavioural data about a named individual and is not required by
    // any Docaya function, so it stays off.
    userEngagementTracking: 'Disabled'
  }
}

// -----------------------------------------------------------------------------
// Communication Services resource.
// -----------------------------------------------------------------------------

resource communicationService 'Microsoft.Communication/communicationServices@2023-06-01-preview' = {
  name: communicationServiceName
  location: 'global'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dataLocation: dataLocation
    linkedDomains: [
      useCustomDomain ? customDomain.id : azureManagedDomain.id
    ]
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
// -----------------------------------------------------------------------------

resource communicationDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: communicationService
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
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
//
// No connection string is emitted. The notification identity authenticates with
// a managed identity (TAD 14.6.4).
// -----------------------------------------------------------------------------

@description('Communication Services resource identifier.')
output communicationServiceId string = communicationService.id

@description('Communication Services name.')
output communicationServiceName string = communicationService.name

@description('Communication Services host, for the managed-identity client.')
output communicationServiceHostName string = communicationService.properties.hostName

@description('Linked sender domain resource identifier.')
output senderDomainId string = useCustomDomain ? customDomain.id : azureManagedDomain.id
