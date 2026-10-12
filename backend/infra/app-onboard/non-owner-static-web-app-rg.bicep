targetScope = 'resourceGroup'

@minLength(1)
param environmentName string

@minLength(1)
param location string

@minLength(1)
param sessionId string

@minLength(1)
param deployedBy string

@minLength(1)
param createdAt string

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
  'deployment-scope': 'non-owner-rg'
}

var staticWebAppName = 'swa-docaya-dev-09e7'

module staticWebApp './modules/static-web-app.bicep' = {
  name: 'staticwebapp-${sessionId}'
  params: {
    location: location
    tags: tags
    staticWebAppName: staticWebAppName
  }
}

output staticWebAppId string = staticWebApp.outputs.staticWebAppId
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname
