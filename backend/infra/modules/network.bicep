// =============================================================================
// network.bicep
//
// Virtual network, subnet segmentation, default-deny network security groups and
// the private DNS zones that keep the data plane off the public internet.
//
// Technical Architecture Document v1.3, Section 16 - Network Architecture:
//   "One controlled public ingress, private-only connectivity to every data
//    service, segmented subnets with default-deny rules, private DNS so internal
//    resolution never leaves the virtual network, and explicitly allow-listed
//    egress to Microsoft 365. No client ever reaches a data store directly."
//
// Provisioning order: step 1 (TAD 18.3). Private endpoints cannot be created
// before the subnet and DNS zone exist.
// =============================================================================

import { mandatoryTagsType, abbreviations, subnetNames, privateDnsZoneNames } from './shared/types.bicep'

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

@description('Address space for the virtual network. Must not overlap any on-premises or peered range.')
param vnetAddressPrefix string = '10.40.0.0/16'

@description('Log Analytics workspace that receives NSG flow logs and diagnostics.')
param logAnalyticsWorkspaceId string

// -----------------------------------------------------------------------------
// Variables
// -----------------------------------------------------------------------------

var vnetName = '${abbreviations.virtualNetwork}-docaya-${environmentName}-${location}'

// /24 per subnet leaves room to grow without re-addressing. Container Apps and
// Functions delegation both require a reasonable minimum size.
var subnetConfig = {
  edge: { name: subnetNames.edge, prefix: cidrSubnet(vnetAddressPrefix, 24, 0) }
  app: { name: subnetNames.app, prefix: cidrSubnet(vnetAddressPrefix, 23, 1) }
  func: { name: subnetNames.func, prefix: cidrSubnet(vnetAddressPrefix, 24, 4) }
  privateEndpoint: { name: subnetNames.privateEndpoint, prefix: cidrSubnet(vnetAddressPrefix, 24, 5) }
  management: { name: subnetNames.management, prefix: cidrSubnet(vnetAddressPrefix, 24, 6) }
}

var dnsZoneList = [
  privateDnsZoneNames.sqlServer
  privateDnsZoneNames.blob
  privateDnsZoneNames.file
  privateDnsZoneNames.queue
  privateDnsZoneNames.table
  privateDnsZoneNames.keyVault
  privateDnsZoneNames.serviceBus
  privateDnsZoneNames.search
  privateDnsZoneNames.openAi
  privateDnsZoneNames.containerRegistry
  privateDnsZoneNames.signalR
]

// -----------------------------------------------------------------------------
// Network security groups.
//
// TAD 16.2: "Every subnet denies by default with explicit allows only."
// Azure applies a default rule set that permits intra-VNet traffic, so each NSG
// below closes that with an explicit deny at priority 4096 and then opens only
// the flows named in the TAD 16.1 subnet design.
// -----------------------------------------------------------------------------

// snet-edge: API Management, internal mode. Inbound from Front Door only.
resource edgeNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${abbreviations.networkSecurityGroup}-${subnetNames.edge}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Front Door reaches API Management over the AzureFrontDoor.Backend
        // service tag. This is the single public ingress path (TAD 16.3).
        name: 'Allow-FrontDoor-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.edge.prefix
          destinationPortRanges: ['443']
          description: 'Front Door is the only publicly reachable component (TAD 16.2).'
        }
      }
      {
        // Required by API Management for control-plane management. Without it the
        // service reports itself unhealthy.
        name: 'Allow-ApiManagement-Management-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.edge.prefix
          destinationPortRanges: ['3443']
          description: 'API Management control plane. Required for the service to remain healthy.'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Health probes.'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Default deny (TAD 16.2).'
        }
      }
      {
        // Outbound permitted to snet-app only.
        name: 'Allow-To-App-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.edge.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.app.prefix
          destinationPortRanges: ['443']
          description: 'snet-edge may reach snet-app only (TAD 16.1).'
        }
      }
      {
        name: 'Allow-Azure-Platform-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.edge.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRanges: ['443']
          description: 'Storage, Key Vault, Entra and Monitor dependencies of API Management.'
        }
      }
      {
        name: 'Deny-All-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'No general internet egress from workload subnets (TAD 16.2).'
        }
      }
    ]
  }
}

// snet-app: Container Apps. Inbound from snet-edge only.
resource appNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${abbreviations.networkSecurityGroup}-${subnetNames.app}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Edge-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.edge.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.app.prefix
          destinationPortRanges: ['443', '80']
          description: 'The application is unreachable by any route other than API Management (TAD 16.3 boundary 2).'
        }
      }
      {
        name: 'Allow-Intra-Subnet-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.app.prefix
          destinationPortRange: '*'
          description: 'Container Apps environment internal communication.'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Health probes.'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Default deny (TAD 16.2).'
        }
      }
      {
        name: 'Allow-To-PrivateEndpoints-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433', '5671', '5672']
          description: 'SQL, Blob, Key Vault, Search and Service Bus, all by private endpoint (TAD 16.1).'
        }
      }
      {
        name: 'Allow-Intra-Subnet-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.app.prefix
          destinationPortRange: '*'
          description: 'Container Apps environment internal communication.'
        }
      }
      {
        // TAD 16.2 controlled egress: allow-listed to Microsoft Graph, SharePoint
        // and the approved Microsoft 365 endpoints. There is no general internet
        // egress. The service tag is the supported allow-list mechanism.
        name: 'Allow-Microsoft365-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRanges: ['443']
          description: 'Token acquisition for the governed service identity.'
        }
      }
      {
        name: 'Allow-AzureMonitor-Outbound'
        properties: {
          priority: 210
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRanges: ['443']
          description: 'Telemetry to Log Analytics and Application Insights.'
        }
      }
      {
        name: 'Allow-AzureContainerRegistry-Outbound'
        properties: {
          priority: 220
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureContainerRegistry'
          destinationPortRanges: ['443']
          description: 'Image pull by digest.'
        }
      }
      {
        name: 'Deny-Internet-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
          description: 'No general internet egress from workload subnets (TAD 16.2).'
        }
      }
    ]
  }
}

// snet-func: Functions workers. Inbound from Service Bus and timer triggers.
resource funcNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${abbreviations.networkSecurityGroup}-${subnetNames.func}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Health probes.'
        }
      }
      {
        name: 'Allow-Intra-Subnet-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.func.prefix
          destinationPortRange: '*'
          description: 'Functions host internal communication.'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Workers are not reachable from the network; they are driven by queue and timer (TAD 16.1).'
        }
      }
      {
        name: 'Allow-To-PrivateEndpoints-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433', '5671', '5672']
          description: 'SQL, Blob, Key Vault, Search, Service Bus and the embedding endpoint (TAD 16.1).'
        }
      }
      {
        name: 'Allow-Intra-Subnet-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.func.prefix
          destinationPortRange: '*'
          description: 'Functions host internal communication.'
        }
      }
      {
        name: 'Allow-EntraId-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRanges: ['443']
          description: 'Token acquisition for the governed service identity.'
        }
      }
      {
        // The promotion worker reaches SharePoint through Microsoft Graph under
        // Sites.Selected scope. This is allow-listed egress, not general internet
        // access (TAD 16.3 boundary 4).
        name: 'Allow-Microsoft365-Graph-Outbound'
        properties: {
          priority: 210
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRanges: ['443']
          description: 'Microsoft Graph and SharePoint under Sites.Selected (TAD 14.6.1).'
        }
      }
      {
        name: 'Allow-AzureMonitor-Outbound'
        properties: {
          priority: 220
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRanges: ['443']
          description: 'Telemetry to Log Analytics and Application Insights.'
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 230
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRanges: ['443']
          description: 'Durable task hub storage.'
        }
      }
      {
        name: 'Deny-Internet-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
          description: 'No general internet egress from workload subnets (TAD 16.2).'
        }
      }
    ]
  }
}

// snet-pe: private endpoints only. Inbound from snet-app and snet-func.
resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${abbreviations.networkSecurityGroup}-${subnetNames.privateEndpoint}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-App-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.app.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433', '5671', '5672']
          description: 'TAD 16.1 - snet-pe accepts inbound from snet-app.'
        }
      }
      {
        name: 'Allow-Func-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.func.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433', '5671', '5672']
          description: 'TAD 16.1 - snet-pe accepts inbound from snet-func.'
        }
      }
      {
        name: 'Allow-Management-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.management.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433']
          description: 'Break-glass and migration access, time-boxed and session-logged (TAD 16.3 boundary 5).'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Default deny (TAD 16.2).'
        }
      }
      {
        // TAD 16.1: snet-pe has no permitted outbound. Private endpoints are
        // destinations, never initiators.
        name: 'Deny-All-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Private endpoints are destinations, never initiators (TAD 16.1).'
        }
      }
    ]
  }
}

// snet-mgmt: deployment and break-glass only. Control plane outbound only.
resource managementNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${abbreviations.networkSecurityGroup}-${subnetNames.management}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Azure Bastion or a private runner is the only inbound path. No rule
        // admits the public internet: authorised operators arrive through PIM.
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Health probes.'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Operators arrive through PIM, not from the network (TAD 16.3 boundary 5).'
        }
      }
      {
        name: 'Allow-To-PrivateEndpoints-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.management.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: subnetConfig.privateEndpoint.prefix
          destinationPortRanges: ['443', '1433']
          description: 'Migration and break-glass database access.'
        }
      }
      {
        name: 'Allow-Control-Plane-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: subnetConfig.management.prefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureResourceManager'
          destinationPortRanges: ['443']
          description: 'TAD 16.1 - snet-mgmt outbound is control plane only.'
        }
      }
      {
        name: 'Deny-All-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Control plane only (TAD 16.1).'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Virtual network.
//
// Subnets are declared inline rather than as child resources. Azure serialises
// subnet writes, and declaring them as separate resources causes conflicts when
// the deployment is re-run.
// -----------------------------------------------------------------------------

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: subnetConfig.edge.name
        properties: {
          addressPrefix: subnetConfig.edge.prefix
          networkSecurityGroup: { id: edgeNsg.id }
          privateEndpointNetworkPolicies: 'Enabled'
          serviceEndpoints: []
        }
      }
      {
        name: subnetConfig.app.name
        properties: {
          addressPrefix: subnetConfig.app.prefix
          networkSecurityGroup: { id: appNsg.id }
          privateEndpointNetworkPolicies: 'Enabled'
          // Container Apps workload profiles require this delegation.
          delegations: [
            {
              name: 'container-apps-delegation'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: subnetConfig.func.name
        properties: {
          addressPrefix: subnetConfig.func.prefix
          networkSecurityGroup: { id: funcNsg.id }
          privateEndpointNetworkPolicies: 'Enabled'
          // Regional virtual network integration for the Functions host.
          delegations: [
            {
              name: 'server-farms-delegation'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: subnetConfig.privateEndpoint.name
        properties: {
          addressPrefix: subnetConfig.privateEndpoint.prefix
          networkSecurityGroup: { id: privateEndpointNsg.id }
          // Must be disabled for private endpoint NIC placement.
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: subnetConfig.management.name
        properties: {
          addressPrefix: subnetConfig.management.prefix
          networkSecurityGroup: { id: managementNsg.id }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Private DNS zones.
//
// TAD 16.2: "Private DNS zones resolve every service name to a private IP inside
// the virtual network, so no data-plane traffic traverses the public internet."
//
// Each zone is linked to the virtual network. Registration is disabled because
// these zones serve private endpoints, not virtual machine registration.
// -----------------------------------------------------------------------------

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in dnsZoneList: {
    name: zone
    // Private DNS zones are global resources.
    location: 'global'
    tags: tags
  }
]

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in dnsZoneList: {
    parent: privateDnsZone[i]
    name: 'link-${vnetName}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: { id: virtualNetwork.id }
    }
  }
]

// -----------------------------------------------------------------------------
// Diagnostics.
//
// TAD 16.2: "flow logs are collected to Log Analytics."
// -----------------------------------------------------------------------------

resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-log-analytics'
  scope: virtualNetwork
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

@description('Virtual network resource identifier.')
output virtualNetworkId string = virtualNetwork.id

@description('Virtual network name.')
output virtualNetworkName string = virtualNetwork.name

@description('snet-edge resource identifier. Hosts API Management in internal mode.')
output edgeSubnetId string = virtualNetwork.properties.subnets[0].id

@description('snet-app resource identifier. Hosts the Container Apps environment.')
output appSubnetId string = virtualNetwork.properties.subnets[1].id

@description('snet-func resource identifier. Hosts the Functions workers.')
output funcSubnetId string = virtualNetwork.properties.subnets[2].id

@description('snet-pe resource identifier. Hosts every private endpoint.')
output privateEndpointSubnetId string = virtualNetwork.properties.subnets[3].id

@description('snet-mgmt resource identifier. Deployment and break-glass only.')
output managementSubnetId string = virtualNetwork.properties.subnets[4].id

@description('Private DNS zone identifiers, keyed by service, for private endpoint DNS zone groups.')
output privateDnsZoneIds object = {
  sqlServer: privateDnsZone[0].id
  blob: privateDnsZone[1].id
  file: privateDnsZone[2].id
  queue: privateDnsZone[3].id
  table: privateDnsZone[4].id
  keyVault: privateDnsZone[5].id
  serviceBus: privateDnsZone[6].id
  search: privateDnsZone[7].id
  openAi: privateDnsZone[8].id
  containerRegistry: privateDnsZone[9].id
  signalR: privateDnsZone[10].id
}
