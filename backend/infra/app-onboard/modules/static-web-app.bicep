param location string
param tags object
param staticWebAppName string

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
    provider: 'Custom'
    publicNetworkAccess: 'Enabled'
    stagingEnvironmentPolicy: 'Enabled'
  }
}

output staticWebAppId string = staticWebApp.id
output defaultHostname string = staticWebApp.properties.defaultHostname
