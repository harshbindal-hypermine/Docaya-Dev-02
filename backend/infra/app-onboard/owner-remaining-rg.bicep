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

@minLength(1)
param existingStorageAccountName string = 'stdocayadev09e7'

@minLength(1)
param existingStaticWebAppDefaultHostname string = 'yellow-island-0fec9a10f.6.azurestaticapps.net'

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
  'deployment-scope': 'owner-remaining-rg'
}

var names = {
  containerApp: 'ca-docaya-dev-09e7'
  containerAppsEnvironment: 'cae-docaya-dev-09e7'
  functionApp: 'func-docaya-dev-09e7'
  functionPlan: 'plan-func-docaya-dev-09e7'
  containerRegistry: 'crdocayadev09e7'
  sqlServer: 'sql-docaya-dev-09e7'
  sqlDatabase: 'sqldb-docaya-dev-09e7'
  serviceBusNamespace: 'sb-docaya-dev-09e7'
  searchService: 'srch-docaya-dev-09e7'
  logAnalytics: 'log-docaya-dev-09e7'
  applicationInsights: 'appi-docaya-dev-09e7'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: existingStorageAccountName
}

module observability './modules/observability.bicep' = {
  name: 'observability-${sessionId}'
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    applicationInsightsName: names.applicationInsights
  }
}

module serviceBus './modules/service-bus.bicep' = {
  name: 'servicebus-${sessionId}'
  params: {
    location: location
    tags: tags
    serviceBusNamespaceName: names.serviceBusNamespace
  }
}

module search './modules/search.bicep' = {
  name: 'search-${sessionId}'
  params: {
    location: location
    tags: tags
    searchServiceName: names.searchService
  }
}

module sql './modules/sql.bicep' = {
  name: 'sql-${sessionId}'
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
  params: {
    location: location
    tags: tags
    registryName: names.containerRegistry
  }
}

module api './modules/container-api.bicep' = {
  name: 'api-${sessionId}'
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
    storageAccountName: storage.name
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    searchServiceName: search.outputs.searchServiceName
    allowedOrigin: 'https://${existingStaticWebAppDefaultHostname}'
    apiInternalSecret: apiInternalSecret
  }
}

module functions './modules/functions-flex.bicep' = {
  name: 'functions-${sessionId}'
  params: {
    location: location
    tags: tags
    functionAppName: names.functionApp
    functionPlanName: names.functionPlan
    storageAccountName: storage.name
    appInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    allowedOrigin: 'https://${existingStaticWebAppDefaultHostname}'
  }
}

module roles './modules/role-assignments.bicep' = {
  name: 'roles-${sessionId}'
  params: {
    acrName: names.containerRegistry
    acrResourceId: registry.outputs.registryId
    apiPrincipalId: api.outputs.principalId
    functionPrincipalId: functions.outputs.principalId
    storageAccountName: storage.name
    storageAccountResourceId: storage.id
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    serviceBusNamespaceResourceId: serviceBus.outputs.serviceBusNamespaceId
    searchServiceName: search.outputs.searchServiceName
    searchServiceResourceId: search.outputs.searchServiceId
  }
}

output containerAppName string = names.containerApp
output apiFqdn string = api.outputs.fqdn
output functionAppName string = functions.outputs.functionAppName
output registryLoginServer string = registry.outputs.loginServer
output sqlServerName string = sql.outputs.sqlServerName
output sqlDatabaseName string = sql.outputs.sqlDatabaseName
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output searchServiceName string = search.outputs.searchServiceName
output applicationInsightsName string = names.applicationInsights
output staticWebAppUrl string = 'https://${existingStaticWebAppDefaultHostname}'
