param workspaceName string
param eventHubNamespaceName string
param eventHubName string
param adxClusterName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: resourceGroup().location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

// do this diagnostics to just generate some test logs to stream to adx
// go to the insights blade of the LAW to generate some logs for type 'LAQueryLogs' 
resource logAnalyticsDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${workspaceName}-diagnostic'
  scope: logAnalyticsWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'AllLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        categoryGroup: 'Audit'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: eventHubNamespaceName
  location: resourceGroup().location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 1
  }
}

// only possible on higher SKU
//resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-05-01-preview' = {
//  parent: eventHub
//  name: 'myConsumerGroup'
//}

resource dataExport 'Microsoft.OperationalInsights/workspaces/dataExports@2023-09-01' = {
  parent: logAnalyticsWorkspace
  name: 'export-adx'
  properties: {
    destination: {
      metaData: {
        eventHubName: eventHub.name
      }
      resourceId: eventHubNamespace.id
    }
    tableNames: [
      'LAQueryLogs'
    ]
  }
}

resource adxCluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: adxClusterName
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
}

resource adxRoleAssignmentEventHubReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHub.id, adxCluster.name , 'Azure Event Hubs Data Receiver') // pattern: destination, identity, role
  scope: eventHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver role ID
    principalId: adxCluster.identity.principalId
  }
}

resource adxRoleAssignmentContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(adxCluster.id, adxCluster.name, 'Contributor') // pattern: destination, identity, role
  scope: adxCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role ID
    principalId: adxCluster.identity.principalId
  }
}

resource adxDatabase 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  parent: adxCluster
  name: 'dedb-main'
  location: resourceGroup().location
  kind: 'ReadWrite'
  properties: {
    hotCachePeriod: 'P1D'
  }

  resource kustoScript 'scripts' = {
    name: 'db-script'
    properties: {
      scriptContent: loadTextContent('script.kql')
      continueOnErrors: false
    }
  }
}

resource adxDataConnection 'Microsoft.Kusto/clusters/databases/dataConnections@2024-04-13' = {
  parent: adxDatabase
  name: 'EventHub'
  kind: 'EventHub'
  location: resourceGroup().location
  properties: {
    eventHubResourceId: eventHub.id
    consumerGroup: '$Default' //eventHubConsumerGroup.name
    managedIdentityResourceId: adxCluster.id
    dataFormat: 'MULTIJSON'
    mappingRuleName: 'DirectJson' //from script.kql
    eventSystemProperties: [
      'x-opt-enqueued-time'
    ]
    retrievalStartDate: '2022-01-01T00:00:00Z' // if you don't specify this, it will start from the current time, but it will set it as UTC, so you have to wait an hour (or 2 depending on summertime)
    tableName: 'RawEvents'
  }
  dependsOn: [
    adxRoleAssignmentEventHubReceiver
    adxDatabase::kustoScript
  ]
}
