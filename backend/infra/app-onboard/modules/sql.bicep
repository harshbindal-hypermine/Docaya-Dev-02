param location string
param tags object
param sqlServerName string
param sqlDatabaseName string
param tenantId string
param entraAdminObjectId string
param entraAdminName string
@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminType string = 'User'

resource server 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminName
      principalType: entraAdminType
      sid: entraAdminObjectId
      tenantId: tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

resource database 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: server
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

resource azureAdOnlyAuth 'Microsoft.Sql/servers/azureADOnlyAuthentications@2024-05-01-preview' = {
  parent: server
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

output sqlServerId string = server.id
output sqlServerName string = server.name
output sqlDatabaseId string = database.id
output sqlDatabaseName string = database.name
