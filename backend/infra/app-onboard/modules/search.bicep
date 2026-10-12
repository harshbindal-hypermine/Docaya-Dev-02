param location string
param tags object
param searchServiceName string

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: 'free'
  }
  properties: {
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disableLocalAuth: true
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    replicaCount: 1
    partitionCount: 1
    semanticSearch: 'free'
  }
}

output searchServiceId string = search.id
output searchServiceName string = search.name
