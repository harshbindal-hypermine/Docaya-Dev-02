param location string
param tags object
param environmentName string
param containerAppName string
param containerImage string
param registryLoginServer string
param logAnalyticsName string
param appInsightsConnectionString string
param sqlServerName string
param sqlDatabaseName string
param storageAccountName string
param serviceBusNamespaceName string
param searchServiceName string
param allowedOrigin string
@secure()
param apiInternalSecret string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: registryLoginServer
          identity: 'system'
        }
      ]
      secrets: [
        {
          name: 'api-internal-secret'
          value: apiInternalSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          env: [
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Production'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
            {
              name: 'ConnectionStrings__DocayaSql'
              value: 'Server=tcp:${sqlServerName}.${az.environment().suffixes.sqlServerHostname},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
            }
            {
              name: 'Docaya__Entra__Authority'
              value: '${az.environment().authentication.loginEndpoint}common/v2.0'
            }
            {
              name: 'Docaya__Entra__Audience'
              value: 'api://docaya-dev-09e7'
            }
            {
              name: 'Docaya__Storage__AccountName'
              value: storageAccountName
            }
            {
              name: 'Docaya__Messaging__ServiceBusNamespace'
              value: '${serviceBusNamespaceName}.servicebus.windows.net'
            }
            {
              name: 'Docaya__Search__Endpoint'
              value: 'https://${searchServiceName}.search.windows.net'
            }
            {
              name: 'Docaya__Cors__AllowedOrigins__0'
              value: allowedOrigin
            }
            {
              name: 'Docaya__ApiInternalSecret'
              secretRef: 'api-internal-secret'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 30
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

output containerAppId string = api.id
output principalId string = api.identity.principalId
output fqdn string = api.properties.configuration.ingress.fqdn
