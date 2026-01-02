param tags object
param projectName string
param environment string
param iteration string

var vnetName = 'vnet-${projectName}-${environment}-${iteration}'
var inboundSubnetName = 'snet-${projectName}-${environment}-inb-${iteration}'
var privateDnsZones = [
  'privatelink.blob.core.windows.net'
  'privatelink.table.core.windows.net'
  'privatelink.queue.core.windows.net'
  'privatelink.servicebus.windows.net'
  'privatelink.${resourceGroup().location}.kusto.windows.net'
]

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: vnetName
  tags: tags
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }

  resource inboundSubnet 'subnets' = {
    name: inboundSubnetName
    properties: {
      addressPrefix: '10.0.0.0/24'
    }
  }
}

module dnsZones 'network-dns-zones.bicep' = [
  for dnsZone in privateDnsZones: {
    name: 'dnsZone-${dnsZone}'
    params: {
      tags: tags
      vnetName: vnet.name
      privateDnsZoneName: dnsZone
      vnetId: vnet.id
    }
  }
]

output inboundSubnetId string = vnet::inboundSubnet.id
