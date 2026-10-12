// =============================================================================
// staticwebapp.bicep
//
// Static Web App hosting the versioned web bundle.
//
// Technical Architecture Document v1.3, Section 17.1:
//   "src/web - React 18, TypeScript, Fluent UI; feature folders aligned to
//    M1-M16; i18n and RTL; generated API client. Produced artifact: versioned
//    static bundle."
//
// Appendix A: "Static Web App - Web bundle hosting. Public content, authenticated
// API calls."
//
// The bundle is served through Front Door, which terminates TLS and applies the
// WAF. The application calls the API through API Management, never directly, and
// never calls a data service (TAD 17.2).
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

@description('Azure region. Static Web Apps are available in a limited set of regions.')
param location string

@description('Mandatory tag set (TAD 18.1).')
param tags mandatoryTagsType

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var staticWebAppName = '${abbreviations.staticWebApp}-docaya-${environmentName}-${location}'

// Standard is required for a custom domain with a managed certificate and for
// private endpoint support.
var skuName = environmentName == 'dev' ? 'Free' : 'Standard'

// -----------------------------------------------------------------------------
// Static Web App.
// -----------------------------------------------------------------------------

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    // The bundle is built once by the release pipeline and deployed by version.
    // No repository is linked, because nothing is built per environment
    // (TAD 19.3 - build once, promote unchanged).
    allowConfigFileUpdates: false

    // The API is reached through API Management, not through a linked backend,
    // so that the token is validated at the gateway and again at the API.
    stagingEnvironmentPolicy: environmentName == 'prod' ? 'Disabled' : 'Enabled'

    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Static Web App resource identifier.')
output staticWebAppId string = staticWebApp.id

@description('Static Web App name.')
output staticWebAppName string = staticWebApp.name

@description('Default hostname. Used as the Front Door origin.')
output defaultHostname string = staticWebApp.properties.defaultHostname
