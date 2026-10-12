param location string
param tags object
param registryName string

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    encryption: {
      status: 'disabled'
    }
    publicNetworkAccess: 'Enabled'
  }
}

output registryId string = registry.id
output loginServer string = registry.properties.loginServer
