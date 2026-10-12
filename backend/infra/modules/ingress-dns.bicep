targetScope = 'resourceGroup'
param defaultDomain string
param staticIp string
param virtualNetworkId string
param tags object

resource ingressDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: defaultDomain
  location: 'global'
  tags: tags
}
resource ingressDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: ingressDns
  name: 'workload-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: virtualNetworkId }
  }
}
resource ingressDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: ingressDns
  name: '*'
  properties: {
    ttl: 300
    aRecords: [{ ipv4Address: staticIp }]
  }
}

