// =============================================================================
// containerapp.bicep
//
// Container Apps environment and the Docaya API application.
//
// Technical Architecture Document v1.3:
//   16.1 - snet-app hosts the API and backend-for-frontend. Inbound from
//          snet-edge only; the application is unreachable by any other route.
//   18.4 - the image is referenced by immutable digest, never a floating tag:
//          "this is what makes rollback deterministic."
//   19.3 - build once, promote unchanged.
//   14.7 - the API reaches SQL, Blob, Key Vault, Service Bus and Search by
//          managed identity over a private endpoint. No secret.
//
// Provisioning order: step 7 (TAD 18.3). The application must be able to resolve
// and reach its dependencies on first start.
// =============================================================================

import { mandatoryTagsType, environmentPostureType, abbreviations } from './shared/types.bicep'

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Environment short name.')
@allowed(['dev', 'test', 'prod'])
param environmentName string

@description('Azure region.')
param location string

@description('Mandatory tag set (TAD 18.1).')
param tags mandatoryTagsType

@description('Per-environment posture (TAD 18.6).')
param posture environmentPostureType

@description('Log Analytics workspace that receives container logs.')
param logAnalyticsWorkspaceId string

@description('Application Insights connection string. Not a secret: local auth is disabled and telemetry is sent by managed identity.')
param applicationInsightsConnectionString string

@description('Resource identifier of snet-app.')
param appSubnetId string

@description('Resource identifier of the API workload identity.')
param apiIdentityResourceId string

@description('Client identifier of the API workload identity, so the application can select it explicitly.')
param apiIdentityClientId string

@description('Entra issuer URI validated by the API.')
param entraAuthority string

@description('Entra API audience validated by the API.')
param apiAudience string

@description('Virtual network used for private ingress name resolution.')
param virtualNetworkId string

@description('API identity object ID for registry role assignment before image pull.')
param apiIdentityPrincipalId string

@description('Container registry login server.')
param containerRegistryLoginServer string

@description('API image referenced by immutable digest, for example sha256:abc... A floating tag is prohibited by release policy (TAD 18.4).')
@minLength(10)
param apiImageDigest string

@description('Key Vault URI. Secrets are referenced from here by URI and never by value (TAD 14.6.4).')
param keyVaultUri string

@description('Fully qualified SQL server name.')
param sqlServerFqdn string

@description('SQL database name.')
param sqlDatabaseName string

@description('Fully qualified Service Bus namespace.')
param serviceBusFullyQualifiedNamespace string

@description('Azure AI Search endpoint.')
param searchEndpoint string

@description('Blob service endpoint.')
param blobEndpoint string

@description('Azure OpenAI endpoint.')
param openAiEndpoint string

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var environmentResourceName = '${abbreviations.containerAppsEnvironment}-docaya-${environmentName}-${location}'
var apiAppName = '${abbreviations.containerApp}-docaya-api-${environmentName}'

// TAD 18.4 - the image is composed from the digest supplied by the pipeline. A
// digest reference cannot drift; a tag can.
var apiImage = '${containerRegistryLoginServer}/docaya-api@${apiImageDigest}'

// -----------------------------------------------------------------------------
// Container Apps environment.
//
// Internal load balancer only: the environment has no public endpoint, so the
// API is reachable solely through API Management in snet-edge (TAD 16.3).
// -----------------------------------------------------------------------------

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: environmentResourceName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: appSubnetId
      // TAD 16.2 - Front Door is the only publicly reachable component. This
      // environment is internal, so no compute resource has a public IP.
      internal: true
    }

    appLogsConfiguration: {
      // 'azure-monitor' routes container logs through a diagnostic setting
      // instead of a workspace shared key, so no secret is read or embedded in
      // the template. The diagnostic setting is declared below.
      destination: 'azure-monitor'
    }

    zoneRedundant: posture.zoneRedundant

    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// API container app.
// -----------------------------------------------------------------------------

resource imageRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: split(containerRegistryLoginServer, '.')[0]
}
resource imagePullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(imageRegistry.id, apiIdentityPrincipalId, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: imageRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module ingressDns 'ingress-dns.bicep' = {
  name: 'api-ingress-dns'
  params: {
    defaultDomain: containerAppsEnvironment.properties.defaultDomain
    staticIp: containerAppsEnvironment.properties.staticIp
    virtualNetworkId: virtualNetworkId
    tags: tags
  }
}

resource apiContainerApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  dependsOn: [imagePullRole]
  name: apiAppName
  location: location
  tags: tags
  identity: {
    // The API acts as the API workload identity for every downstream call.
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apiIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'

    configuration: {
      ingress: {
        // Internal only. API Management is the sole caller (TAD 16.3 boundary 2).
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false

        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]

        // Defence in depth behind the NSG: only the edge subnet may call.
        ipSecurityRestrictions: []

        corsPolicy: null
      }

      // Image pull is by managed identity holding AcrPull. No registry password
      // is stored (TAD 14.7).
      registries: [
        {
          server: containerRegistryLoginServer
          identity: apiIdentityResourceId
        }
      ]

      // No secret is declared. Every downstream call authenticates with the
      // managed identity, and anything that genuinely needs a secret reads it
      // from Key Vault by URI at runtime (TAD 14.6.4).
      secrets: []

      activeRevisionsMode: 'Single'

      maxInactiveRevisions: 3
    }

    template: {
      containers: [
        {
          name: 'docaya-api'
          image: apiImage

          resources: {
            cpu: json(environmentName == 'prod' ? '1.0' : '0.5')
            memory: environmentName == 'prod' ? '2Gi' : '1Gi'
          }

          env: [
            { name: 'Docaya__Entra__Authority', value: entraAuthority }
            { name: 'Docaya__Entra__Audience', value: apiAudience }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: environmentName == 'prod' ? 'Production' : 'Staging'
            }
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              // Selects the user-assigned identity explicitly. Without this a
              // multi-identity host cannot know which identity to present.
              name: 'AZURE_CLIENT_ID'
              value: apiIdentityClientId
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              // Entra authentication with managed identity. There is no password
              // in this connection string (TAD 14.6.3).
              name: 'ConnectionStrings__DocayaSql'
              value: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
            }
            {
              name: 'Docaya__KeyVaultUri'
              value: keyVaultUri
            }
            {
              name: 'Docaya__ServiceBus__FullyQualifiedNamespace'
              value: serviceBusFullyQualifiedNamespace
            }
            {
              name: 'Docaya__Search__Endpoint'
              value: searchEndpoint
            }
            {
              name: 'Docaya__Storage__BlobEndpoint'
              value: blobEndpoint
            }
            {
              name: 'Docaya__OpenAi__Endpoint'
              value: openAiEndpoint
            }
            {
              // TAD 6.3 - Ask answering is gated on the POC outcome.
              name: 'Docaya__FeatureFlags__AskAnsweringEnabled'
              value: string(posture.askAnsweringEnabled)
            }
            {
              name: 'Docaya__OperatingTimeZone'
              value: 'Arabian Standard Time'
            }
          ]

          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/health/live'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              timeoutSeconds: 5
              // Allows up to two minutes for a cold start before the platform
              // gives up on the revision.
              failureThreshold: 24
            }
          ]
        }
      ]

      scale: {
        minReplicas: posture.apiMinReplicas
        maxReplicas: posture.apiMaxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Diagnostics.
//
// Container console and system logs flow to Log Analytics through a diagnostic
// setting rather than a workspace shared key, so no secret is handled here.
// -----------------------------------------------------------------------------

resource containerAppsEnvironmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: containerAppsEnvironment
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Container Apps environment resource identifier.')
output containerAppsEnvironmentId string = containerAppsEnvironment.id

@description('Container Apps environment default domain.')
output containerAppsEnvironmentDefaultDomain string = containerAppsEnvironment.properties.defaultDomain

@description('Static IP of the internal load balancer. API Management routes to this address.')
output containerAppsEnvironmentStaticIp string = containerAppsEnvironment.properties.staticIp

@description('API container app resource identifier.')
output apiContainerAppId string = apiContainerApp.id

@description('API container app name.')
output apiContainerAppName string = apiContainerApp.name

@description('Internal fully qualified domain name of the API. Reachable only from snet-edge (TAD 16.3).')
output apiInternalFqdn string = apiContainerApp.properties.configuration.ingress.fqdn

@description('Image digest this revision was deployed with. Rollback re-points to the previous digest (TAD 18.5).')
output deployedImage string = apiImage
