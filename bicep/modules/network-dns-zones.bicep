param tags object
param privateDnsZoneName string
param vnetId string
param vnetName string

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags

  resource vnetLink 'virtualNetworkLinks' = {
    name: '${vnetName}-link'
    location: 'global'
    properties: {
      virtualNetwork: {
        id: vnetId
      }
      registrationEnabled: false
    }
  }
}

output dnsZoneId string = privateDnsZone.id
output dnsZoneName string = privateDnsZone.name
