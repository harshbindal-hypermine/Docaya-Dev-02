// =============================================================================
// observability.bicep
//
// Log Analytics workspace, Application Insights, the action group and the alert
// rules that carry the operational contract.
//
// Technical Architecture Document v1.3:
//   28.1 Telemetry and correlation - the correlation ID flows from the browser
//        through the API, the queue, the worker and into the audit record.
//   28.2 Alert definitions.
//   18.6 Telemetry retention: 30 days dev, 90 days test, per client policy in
//        production.
//
// Provisioning order: step 3 (TAD 18.3). Diagnostic settings on every later
// resource target this workspace, so it must exist before them.
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations } from './shared/types.bicep'

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

@description('Email address that receives operational alerts. Routed to the on-call rota, never to an individual.')
param alertEmailAddress string

@description('Whether to create alert rules. Disabled in dev to avoid noise from a non-representative environment.')
param alertsEnabled bool = true

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var workspaceName = '${abbreviations.logAnalyticsWorkspace}-docaya-${environmentName}-${location}'
var appInsightsName = '${abbreviations.applicationInsights}-docaya-${environmentName}-${location}'
var actionGroupName = '${abbreviations.actionGroup}-docaya-${environmentName}'

// -----------------------------------------------------------------------------
// Log Analytics workspace.
//
// The single telemetry sink. Every resource in the estate sends its diagnostics
// here, which is what makes a correlation ID traceable end to end.
// -----------------------------------------------------------------------------

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: posture.telemetryRetentionDays
    features: {
      // Required so Application Insights data lands in this workspace.
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    workspaceCapping: {
      // Uncapped in production; a cap in lower environments prevents a runaway
      // loop turning into an unbounded bill.
      dailyQuotaGb: environmentName == 'prod' ? -1 : 5
    }
  }
}

// -----------------------------------------------------------------------------
// Application Insights, workspace-based.
// -----------------------------------------------------------------------------

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    // Ingestion is by managed identity from the workload; local auth is not
    // needed and is disabled so an instrumentation key cannot be reused.
    DisableLocalAuth: true
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: posture.telemetryRetentionDays
  }
}

// -----------------------------------------------------------------------------
// Action group.
//
// Alerts route to the on-call rota. TAD 28.3 defines the support model.
// -----------------------------------------------------------------------------

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  // Action groups are global.
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'docaya${environmentName}'
    enabled: true
    emailReceivers: [
      {
        name: 'oncall'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Alert rules - TAD 28.2.
//
// Each alert below exists because a specific architectural guarantee can fail
// silently without it.
// -----------------------------------------------------------------------------

// A dead-lettered message means an event was not processed. TAD 24.4 requires
// dead-letter queue age and depth to be monitored: "nothing is silently dropped".
resource deadLetterAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: 'alert-docaya-${environmentName}-deadletter'
  location: location
  tags: tags
  properties: {
    displayName: 'Docaya - dead-lettered messages present'
    description: 'A message reached the dead-letter queue. Replay is an audited operator action, never automatic (TAD 24.4).'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalyticsWorkspace.id]
    criteria: {
      allOf: [
        {
          query: '''
            AzureMetrics
            | where ResourceProvider == "MICROSOFT.SERVICEBUS"
            | where MetricName == "DeadletteredMessages"
            | summarize DeadLettered = max(Maximum) by bin(TimeGenerated, 5m)
            | where DeadLettered > 0
          '''
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'DeadLettered'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
    autoMitigate: false
  }
}

// A promotion that fails leaves an approved document unpublished. TAD 7.1 step 8
// requires a failed promotion to be retained and replayable, which only helps if
// somebody is told it happened.
resource promotionFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: 'alert-docaya-${environmentName}-promotion-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'Docaya - document promotion failed'
    description: 'A promotion to SharePoint failed or was quarantined on a hash mismatch (TAD 7.2).'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [applicationInsights.id]
    criteria: {
      allOf: [
        {
          query: '''
            exceptions
            | where cloud_RoleName has "docaya"
            | where operation_Name has_any ("PromoteDocument", "VerifyPublishedHash")
            | summarize Failures = count() by bin(timestamp, 5m)
          '''
          timeAggregation: 'Total'
          metricMeasureColumn: 'Failures'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
    autoMitigate: false
  }
}

// TAD 6.2: "Audit failure is an incident; the response is still safe." An audit
// write that does not land breaks the hash chain, so it is severity 0.
resource auditFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: 'alert-docaya-${environmentName}-audit-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'Docaya - audit write failed'
    description: 'An audit append failed. The hash chain may be broken; treat as an incident (TAD 6.2, 11.9.1).'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [applicationInsights.id]
    criteria: {
      allOf: [
        {
          query: '''
            traces
            | where cloud_RoleName has "docaya"
            | where message has "audit" and severityLevel >= 3
            | summarize Failures = count() by bin(timestamp, 5m)
          '''
          timeAggregation: 'Total'
          metricMeasureColumn: 'Failures'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
    autoMitigate: false
  }
}

// A sustained rise in 5xx breaches the availability target in TAD 28.4.
resource apiFailureRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: 'alert-docaya-${environmentName}-api-failure-rate'
  location: location
  tags: tags
  properties: {
    displayName: 'Docaya - API server error rate elevated'
    description: 'Server-side failures are above threshold, breaching the availability target (TAD 28.4).'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [applicationInsights.id]
    criteria: {
      allOf: [
        {
          query: '''
            requests
            | where cloud_RoleName has "docaya"
            | summarize Total = count(), Failed = countif(toint(resultCode) >= 500) by bin(timestamp, 5m)
            | extend FailureRate = todouble(Failed) * 100.0 / todouble(Total)
            | project timestamp, FailureRate
          '''
          timeAggregation: 'Average'
          metricMeasureColumn: 'FailureRate'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
    autoMitigate: true
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Log Analytics workspace resource identifier. Every later module targets this for diagnostics.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name.')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics customer identifier, for agent configuration.')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Application Insights resource identifier.')
output applicationInsightsId string = applicationInsights.id

@description('Application Insights connection string. Not a secret: it is an endpoint plus an application identifier, and local auth is disabled.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Action group resource identifier.')
output actionGroupId string = actionGroup.id
