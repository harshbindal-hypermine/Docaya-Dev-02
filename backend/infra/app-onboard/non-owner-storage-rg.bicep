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

var storageAccountName = 'stdocayadev09e7'

module storage './modules/storage.bicep' = {
  name: 'storage-${sessionId}'
  params: {
    location: location
    tags: tags
    storageAccountName: storageAccountName
  }
}

output storageAccountId string = storage.outputs.storageAccountId
output storageAccountName string = storage.outputs.storageAccountName
output functionDeploymentContainerName string = storage.outputs.functionDeploymentContainerName
