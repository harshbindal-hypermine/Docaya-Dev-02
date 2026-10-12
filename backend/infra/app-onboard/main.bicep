targetScope = 'subscription'

@minLength(1)
param environmentName string

@minLength(1)
param location string

@minLength(1)
param resourceGroupName string

@minLength(1)
param sessionId string

@minLength(1)
param deployedBy string

@minLength(1)
param createdAt string

@minLength(1)
param tenantId string

@minLength(1)
param entraAdminObjectId string

@minLength(1)
param entraAdminName string

@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminType string = 'User'

@secure()
param apiInternalSecret string

param apiContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
}

var names = {
  staticWebApp: 'swa-docaya-dev-09e7'
  containerApp: 'ca-docaya-dev-09e7'
  containerAppsEnvironment: 'cae-docaya-dev-09e7'
  functionApp: 'func-docaya-dev-09e7'
  functionPlan: 'plan-func-docaya-dev-09e7'
  containerRegistry: 'crdocayadev09e7'
  sqlServer: 'sql-docaya-dev-09e7'
  sqlDatabase: 'sqldb-docaya-dev-09e7'
  storageAccount: 'stdocayadev09e7'
  serviceBusNamespace: 'sb-docaya-dev-09e7'
  searchService: 'srch-docaya-dev-09e7'
  logAnalytics: 'log-docaya-dev-09e7'
  applicationInsights: 'appi-docaya-dev-09e7'
}

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module observability './modules/observability.bicep' = {
  name: 'observability-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    applicationInsightsName: names.applicationInsights
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    storageAccountName: names.storageAccount
  }
}

module serviceBus './modules/service-bus.bicep' = {
  name: 'servicebus-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    serviceBusNamespaceName: names.serviceBusNamespace
  }
}

module search './modules/search.bicep' = {
  name: 'search-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    searchServiceName: names.searchService
  }
}

module sql './modules/sql.bicep' = {
  name: 'sql-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    sqlServerName: names.sqlServer
    sqlDatabaseName: names.sqlDatabase
    tenantId: tenantId
    entraAdminObjectId: entraAdminObjectId
    entraAdminName: entraAdminName
    entraAdminType: entraAdminType
  }
}

module registry './modules/container-registry.bicep' = {
  name: 'registry-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    registryName: names.containerRegistry
  }
}

module staticWebApp './modules/static-web-app.bicep' = {
  name: 'static-web-app-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    staticWebAppName: names.staticWebApp
  }
}

module api './modules/container-api.bicep' = {
  name: 'api-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    environmentName: names.containerAppsEnvironment
    containerAppName: names.containerApp
    containerImage: apiContainerImage
    registryLoginServer: registry.outputs.loginServer
    logAnalyticsName: names.logAnalytics
    appInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    sqlServerName: sql.outputs.sqlServerName
    sqlDatabaseName: sql.outputs.sqlDatabaseName
    storageAccountName: storage.outputs.storageAccountName
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    searchServiceName: search.outputs.searchServiceName
    allowedOrigin: 'https://${staticWebApp.outputs.defaultHostname}'
    apiInternalSecret: apiInternalSecret
  }
}

module functions './modules/functions-flex.bicep' = {
  name: 'functions-${sessionId}'
  scope: rg
  params: {
    location: location
    tags: tags
    functionAppName: names.functionApp
    functionPlanName: names.functionPlan
    storageAccountName: storage.outputs.storageAccountName
    appInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    allowedOrigin: 'https://${staticWebApp.outputs.defaultHostname}'
  }
}

module roles './modules/role-assignments.bicep' = {
  name: 'roles-${sessionId}'
  scope: rg
  params: {
    acrName: names.containerRegistry
    acrResourceId: registry.outputs.registryId
    apiPrincipalId: api.outputs.principalId
    functionPrincipalId: functions.outputs.principalId
    storageAccountName: storage.outputs.storageAccountName
    storageAccountResourceId: storage.outputs.storageAccountId
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    serviceBusNamespaceResourceId: serviceBus.outputs.serviceBusNamespaceId
    searchServiceName: search.outputs.searchServiceName
    searchServiceResourceId: search.outputs.searchServiceId
  }
}

output resourceGroupName string = rg.name
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname
output apiFqdn string = api.outputs.fqdn
output functionAppName string = functions.outputs.functionAppName
output registryLoginServer string = registry.outputs.loginServer
