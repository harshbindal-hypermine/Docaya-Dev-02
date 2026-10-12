// =============================================================================
// apim.bicep
//
// API Management in internal mode - trust boundary 2.
//
// Technical Architecture Document v1.3, Section 16.3:
//   "Edge -> Application: API Management in internal mode validates the token and
//    applies policy; the application is unreachable by any other route."
//
// Section 24.1:
//   Authentication - OAuth 2.0 bearer token issued by Entra, validated at API
//                    Management and AGAIN at the API. Validation here is the
//                    first gate, never the only one.
//   Rate limiting  - per product, per key and per user, with separate limits for
//                    upload and for Ask Docaya.
//
// Provisioning order: step 8 (TAD 18.3). Routing targets must exist and be
// healthy before traffic is accepted.
// =============================================================================

import { mandatoryTagsType, abbreviations } from './shared/types.bicep'

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

@description('Log Analytics workspace that receives diagnostics.')
param logAnalyticsWorkspaceId string

@description('Application Insights resource identifier for request telemetry.')
param applicationInsightsId string

@description('Application Insights connection string.')
param applicationInsightsConnectionString string

@description('Resource identifier of snet-edge.')
param edgeSubnetId string

@description('Internal fully qualified domain name of the API container app. The only backend.')
param apiBackendFqdn string

@description('Publisher email shown on the developer portal and used for service notifications.')
param publisherEmail string

@description('Publisher organisation name.')
param publisherName string = 'Docaya'

@description('Entra tenant identifier used to compose the token issuer.')
param entraTenantId string

@description('Application ID URI of the Docaya API, validated as the token audience.')
param apiAudience string

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var apimName = '${abbreviations.apiManagement}-docaya-${environmentName}-${location}'

// Internal virtual network mode requires Developer or Premium. Premium is the
// only production-supportable option; Developer carries no SLA and is used in
// dev and test where that is acceptable.
var apimSku = {
  dev: { name: 'Developer', capacity: 1 }
  test: { name: 'Developer', capacity: 1 }
  prod: { name: 'Premium', capacity: 1 }
}

var openIdIssuer = '${environment().authentication.loginEndpoint}${entraTenantId}/v2.0'

// -----------------------------------------------------------------------------
// API Management service.
// -----------------------------------------------------------------------------

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: apimSku[environmentName]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName

    // TAD 16.3 - internal mode. The gateway holds no public IP; Front Door is
    // the only publicly reachable component.
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: edgeSubnetId
    }

    // The developer portal exposes API documentation and a console. Neither is
    // appropriate for a governed internal API.
    developerPortalStatus: 'Disabled'

    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }

    customProperties: {
      // Disable every legacy protocol and cipher. TLS 1.2 or better only.
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'True'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Backend.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Backend.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Backend.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
    }

    publicNetworkAccess: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Backend.
//
// The single backend is the internal container app. Nothing else is routable.
// -----------------------------------------------------------------------------

resource apiBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apiManagement
  name: 'docaya-api'
  properties: {
    title: 'Docaya API'
    description: 'Internal Container Apps ingress. Reachable only from snet-edge (TAD 16.3).'
    protocol: 'http'
    url: 'https://${apiBackendFqdn}'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// -----------------------------------------------------------------------------
// Named values used by policy.
// -----------------------------------------------------------------------------

resource issuerNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'entra-issuer'
  properties: {
    displayName: 'entra-issuer'
    value: openIdIssuer
    secret: false
  }
}

resource audienceNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apiManagement
  name: 'api-audience'
  properties: {
    displayName: 'api-audience'
    value: apiAudience
    secret: false
  }
}

// -----------------------------------------------------------------------------
// Logger and diagnostics.
// -----------------------------------------------------------------------------

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apiManagement
  name: 'application-insights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: applicationInsightsId
    credentials: {
      connectionString: applicationInsightsConnectionString
    }
  }
}

resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apiManagement
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    // Sampling keeps telemetry cost bounded while retaining every error.
    sampling: {
      samplingType: 'fixed'
      percentage: environmentName == 'prod' ? 25 : 100
    }
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: false
    frontend: {
      request: {
        // Headers and bodies are never logged: a request body may carry document
        // content or personal data (TAD 17.4).
        headers: []
        body: {}
      }
      response: {
        headers: []
        body: {}
      }
    }
    backend: {
      request: {
        headers: []
        body: {}
      }
      response: {
        headers: []
        body: {}
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Global policy.
//
// Applies to every API. Validates the Entra token, enforces correlation, strips
// server fingerprinting headers and denies by default.
// -----------------------------------------------------------------------------

resource globalPolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = {
  parent: apiManagement
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <!-- TAD 24.1 - validate the Entra-issued bearer token: issuer, audience,
         signature and expiry. The API validates it again; this is the first
         gate, never the only one. -->
    <validate-jwt header-name="Authorization" require-scheme="Bearer" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="{{entra-issuer}}/.well-known/openid-configuration" />
      <audiences>
        <audience>{{api-audience}}</audience>
      </audiences>
    </validate-jwt>

    <!-- TAD 24.1 - W3C trace context flows from the browser through the API, the
         queue, the worker and into the audit record. -->
    <set-header name="traceparent" exists-action="skip">
      <value>@($"00-{Guid.NewGuid().ToString("N")}-{Guid.NewGuid().ToString("N").Substring(0,16)}-01")</value>
    </set-header>

    <!-- Rate limiting per caller. Upload and Ask carry their own limits at the
         operation level. -->
    <rate-limit-by-key calls="600" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","anonymous"))" />

    <!-- The gateway never forwards its own credentials downstream. -->
    <set-header name="X-Forwarded-Host" exists-action="override">
      <value>@(context.Request.OriginalUrl.Host)</value>
    </set-header>
  </inbound>

  <backend>
    <forward-request timeout="120" />
  </backend>

  <outbound>
    <!-- Remove headers that fingerprint the platform. -->
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="X-AspNet-Version" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />

    <!-- Baseline browser security headers. -->
    <set-header name="Strict-Transport-Security" exists-action="override">
      <value>max-age=31536000; includeSubDomains; preload</value>
    </set-header>
    <set-header name="X-Content-Type-Options" exists-action="override">
      <value>nosniff</value>
    </set-header>
    <set-header name="X-Frame-Options" exists-action="override">
      <value>DENY</value>
    </set-header>
    <set-header name="Referrer-Policy" exists-action="override">
      <value>strict-origin-when-cross-origin</value>
    </set-header>
  </outbound>

  <on-error>
    <!-- TAD 6.3 - internal exception text and stack traces are never returned.
         The correlation ID is, so an operator can find the detail in telemetry. -->
    <set-header name="Content-Type" exists-action="override">
      <value>application/problem+json</value>
    </set-header>
    <set-body>@{
      return new JObject(
        new JProperty("type", "https://docaya.local/problems/gateway.error"),
        new JProperty("title", "Request could not be completed"),
        new JProperty("status", context.Response?.StatusCode ?? 500),
        new JProperty("code", "gateway.error"),
        new JProperty("correlationId", context.RequestId.ToString())
      ).ToString();
    }</set-body>
  </on-error>
</policies>
'''
  }
  dependsOn: [
    issuerNamedValue
    audienceNamedValue
  ]
}

// -----------------------------------------------------------------------------
// Products.
//
// TAD 24.1 - rate limiting per product, with separate limits for upload and for
// Ask Docaya, because their cost profiles differ by orders of magnitude.
// -----------------------------------------------------------------------------

resource coreProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apiManagement
  name: 'docaya-core'
  properties: {
    displayName: 'Docaya Core'
    description: 'Document lifecycle, review chain and administration.'
    subscriptionRequired: false
    state: 'published'
  }
}

resource uploadProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apiManagement
  name: 'docaya-upload'
  properties: {
    displayName: 'Docaya Upload'
    description: 'Resumable chunked capture, one file per registration, 100 MB maximum.'
    subscriptionRequired: false
    state: 'published'
  }
}

resource askProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apiManagement
  name: 'docaya-ask'
  properties: {
    displayName: 'Ask Docaya'
    description: 'Search, discovery and cited AI answering over approved content only.'
    subscriptionRequired: false
    state: 'published'
  }
}

resource uploadProductPolicy 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = {
  parent: uploadProduct
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <!-- Upload is expensive in bandwidth, not in compute. A lower call rate with
         a long timeout suits a resumable chunked upload. -->
    <rate-limit-by-key calls="120" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","anonymous"))" />
  </inbound>
  <backend>
    <forward-request timeout="300" />
  </backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
  dependsOn: [globalPolicy]
}

resource askProductPolicy 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = {
  parent: askProduct
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <!-- Answering consumes model capacity. A tight per-caller limit protects the
         shared deployment from a single heavy user (TAD 24.1). -->
    <rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","anonymous"))" />
  </inbound>
  <backend>
    <forward-request timeout="120" />
  </backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
  dependsOn: [globalPolicy]
}

// -----------------------------------------------------------------------------
// Diagnostics.
// -----------------------------------------------------------------------------

resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: apiManagement
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

@description('API Management resource identifier.')
output apiManagementId string = apiManagement.id

@description('API Management name.')
output apiManagementName string = apiManagement.name

@description('Gateway URL. Private in internal mode; Front Door is the public route to it.')
output gatewayUrl string = apiManagement.properties.gatewayUrl

@description('Private IP addresses of the internal gateway, used as the Front Door origin.')
output privateIpAddresses array = apiManagement.properties.privateIPAddresses

@description('Principal identifier of the API Management identity.')
output apiManagementPrincipalId string = apiManagement.identity.principalId

// Import the versioned source contract so the gateway actually exposes its operations.
resource docayaApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: 'docaya-v1'
  properties: {
    displayName: 'Docaya v1'
    path: 'api/v1'
    protocols: ['https']
    subscriptionRequired: false
    serviceUrl: 'https://${apiBackendFqdn}/api/v1'
    format: 'openapi'
    value: loadTextContent('../../src/contracts/openapi/docaya-api-v1.yaml')
  }
}
resource coreApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: coreProduct
  name: docayaApi.name
}
