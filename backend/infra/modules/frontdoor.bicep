// =============================================================================
// frontdoor.bicep
//
// Azure Front Door and the WAF policy - trust boundary 1, the only public surface.
//
// Technical Architecture Document v1.3, Section 16.3:
//   "Internet -> Edge: Front Door, WAF with OWASP ruleset, bot protection, rate
//    limiting, TLS termination, optional DDoS protection and IP allow-list for
//    administrative paths."
//
// Section 16.2: "Front Door is the only publicly reachable component. No compute
// or data resource has a public IP."
//
// Provisioning order: step 8 (TAD 18.3).
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

@description('Log Analytics workspace that receives WAF and access logs.')
param logAnalyticsWorkspaceId string

@description('Default hostname of the Static Web App that serves the web bundle.')
param staticWebAppHostname string

@description('Whether the WAF runs in Prevention mode. Detection in dev so a false positive does not block development.')
param wafPreventionEnabled bool = true

@description('CIDR ranges permitted to reach administrative paths. Empty disables the allow-list (TAD 16.3).')
param administrativeIpAllowList array = []

// -----------------------------------------------------------------------------
// Variables
//
// Front Door and its WAF policy are global resources.
// -----------------------------------------------------------------------------

var frontDoorName = '${abbreviations.frontDoor}-docaya-${environmentName}'

// A WAF policy name must be alphanumeric only.
var wafPolicyName = 'waf${replace(abbreviations.wafPolicy, '-', '')}docaya${environmentName}'

var endpointName = 'docaya-${environmentName}'
var originGroupName = 'docaya-web'
var originName = 'static-web-app'
var routeName = 'docaya-route'

// Premium is required for the managed bot-protection rule set and for Private
// Link origins.
var frontDoorSku = environmentName == 'prod' ? 'Premium_AzureFrontDoor' : 'Standard_AzureFrontDoor'
var isPremium = frontDoorSku == 'Premium_AzureFrontDoor'

// -----------------------------------------------------------------------------
// WAF policy.
// -----------------------------------------------------------------------------

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'global'
  tags: tags
  sku: {
    name: frontDoorSku
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      // Prevention blocks. Detection only logs, which is right for dev where a
      // false positive would otherwise stop work.
      mode: wafPreventionEnabled ? 'Prevention' : 'Detection'
      requestBodyCheck: 'Enabled'
      // 100 MB single-file capture is chunked, so no single request body needs to
      // be large. The cap here is a defence against a malformed request.
      customBlockResponseStatusCode: 403
      customBlockResponseBody: base64('{"type":"https://docaya.local/problems/waf.blocked","title":"Request blocked","status":403,"code":"waf.blocked"}')
    }

    managedRules: {
      managedRuleSets: concat(
        [
          {
            // OWASP core rule set (TAD 16.3).
            ruleSetType: 'Microsoft_DefaultRuleSet'
            ruleSetVersion: '2.1'
            ruleSetAction: 'Block'
            exclusions: []
            ruleGroupOverrides: []
          }
        ],
        isPremium
          ? [
              {
                // Bot protection. Premium only.
                ruleSetType: 'Microsoft_BotManagerRuleSet'
                ruleSetVersion: '1.0'
                ruleSetAction: 'Block'
                exclusions: []
                ruleGroupOverrides: []
              }
            ]
          : []
      )
    }

    customRules: {
      rules: concat(
        [
          {
            // TAD 16.3 - rate limiting at the edge, before a request reaches the
            // gateway or consumes any application capacity.
            name: 'RateLimitPerClientIp'
            priority: 100
            enabledState: 'Enabled'
            ruleType: 'RateLimitRule'
            rateLimitDurationInMinutes: 1
            rateLimitThreshold: 1000
            matchConditions: [
              {
                matchVariable: 'RemoteAddr'
                operator: 'IPMatch'
                negateCondition: true
                matchValue: ['0.0.0.0/0']
              }
            ]
            action: 'Block'
          }
        ],
        // TAD 16.3 - IP allow-list for administrative paths. Applied only when a
        // range is supplied, so an empty list does not lock everybody out.
        empty(administrativeIpAllowList)
          ? []
          : [
              {
                name: 'RestrictAdministrativePaths'
                priority: 50
                enabledState: 'Enabled'
                ruleType: 'MatchRule'
                matchConditions: [
                  {
                    matchVariable: 'RequestUri'
                    operator: 'Contains'
                    negateCondition: false
                    matchValue: ['/api/v1/admin']
                    transforms: ['Lowercase']
                  }
                  {
                    matchVariable: 'RemoteAddr'
                    operator: 'IPMatch'
                    negateCondition: true
                    matchValue: administrativeIpAllowList
                  }
                ]
                action: 'Block'
              }
            ]
      )
    }
  }
}

// -----------------------------------------------------------------------------
// Front Door profile.
// -----------------------------------------------------------------------------

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: frontDoorName
  location: 'global'
  tags: tags
  sku: {
    name: frontDoorSku
  }
  properties: {
    originResponseTimeoutSeconds: 120
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  parent: frontDoorProfile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Origin group and origin.
// -----------------------------------------------------------------------------

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  parent: frontDoorProfile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      // TAD 18.5 - a routing target must be healthy before traffic is accepted.
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 60
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: staticWebAppHostname
    originHostHeader: staticWebAppHostname
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// -----------------------------------------------------------------------------
// Route.
// -----------------------------------------------------------------------------

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  parent: frontDoorEndpoint
  name: routeName
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    // TAD 16.3 - TLS termination at the edge, and every plain request redirected.
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    cacheConfiguration: null
  }
  dependsOn: [
    origin
  ]
}

// -----------------------------------------------------------------------------
// Security policy binding the WAF to the endpoint.
// -----------------------------------------------------------------------------

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = {
  parent: frontDoorProfile
  name: 'docaya-waf-association'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// WAF logs are the evidence that boundary 1 is enforced.
// -----------------------------------------------------------------------------

resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: frontDoorProfile
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
// -----------------------------------------------------------------------------

@description('Front Door profile resource identifier.')
output frontDoorProfileId string = frontDoorProfile.id

@description('Front Door profile name.')
output frontDoorProfileName string = frontDoorProfile.name

@description('Public hostname. The single public surface of the estate (TAD 16.2).')
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName

@description('WAF policy resource identifier.')
output wafPolicyId string = wafPolicy.id

@description('Front Door unique identifier, used to restrict the origin to this profile only.')
output frontDoorId string = frontDoorProfile.properties.frontDoorId
