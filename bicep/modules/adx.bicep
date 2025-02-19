param tags object
param projectName string
param environment string
param iteration string
param logAnalyticsWorkspaceName string
param inboundSubnetId string
param eventHubDiagnosticsName string
param eventHubDiagnosticsAuthorizationRuleId string
param entraIdGroupDataViewersObjectId string

var adxClusterName = 'adx-${projectName}-${environment}-${iteration}' //max length of 22 characters

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource adxCluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: adxClusterName
  tags: tags
  location: resourceGroup().location
  sku: {
    tier: 'Standard'
    name: 'Standard_E2a_v4' //cheapest tier (100$ a month approx.)
    capacity: 2
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableDiskEncryption: true
  }

  resource dataViewers 'principalAssignments' = {
    name: 'dataViewers'
    properties: {
      principalType: 'Group'
      principalId: entraIdGroupDataViewersObjectId
      role: 'AllDatabasesViewer'
    }
  }
}

resource adxClusterPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${adxClusterName}'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: inboundSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'clusterConnection'
        properties: {
          privateLinkServiceId: adxCluster.id
          groupIds: [
            'cluster'
          ]
        }
      }
    ]
  }

  resource privateEndpointDsnZoneGroupResource 'privateDnsZoneGroups' = {
    name: 'adx'
    properties: {
      privateDnsZoneConfigs: [
        for dnsZone in [
          'privatelink.blob.core.windows.net'
          'privatelink.table.core.windows.net'
          'privatelink.queue.core.windows.net'
          'privatelink.${resourceGroup().location}.kusto.windows.net'
        ]: {
          name: dnsZone
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', dnsZone)
          }
        }
      ]
    }
  }
}

// do some queries in adx
// generates 'ADXCommand', 'ADXDataOperation', 'ADXIngestionBatching', 'ADXJournal', 'ADXQuery', 'ADXTableUsageStatistics' logs
//
// ingest some data into adx (via event hub that just works if you deploy this solution)
// generates 'SucceededIngestion' logs
resource adxClusterDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (environment == 'dev') {
  name: '${adxClusterName}-diagnostic'
  scope: adxCluster
  properties: {
    workspaceId: law.id
    eventHubName: eventHubDiagnosticsName
    eventHubAuthorizationRuleId: eventHubDiagnosticsAuthorizationRuleId
    logs: [
      {
        categoryGroup: 'AllLogs'
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

resource adxRoleAssignmentEventHubReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().name, adxCluster.name, 'Azure Event Hubs Data Receiver') // pattern: destination, identity, role
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
    ) // Azure Event Hubs Data Receiver role ID
    principalId: adxCluster.identity.principalId
  }
}

resource adxRoleAssignmentContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(adxCluster.id, adxCluster.name, 'Contributor') // pattern: destination, identity, role
  scope: adxCluster
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    ) // Contributor role ID
    principalId: adxCluster.identity.principalId
  }
}

output adxClusterName string = adxCluster.name
