param projectName string
param environment string
param iteration string
param logAnalyticsWorkspaceName string

var eventHubNamespaceName = 'evhns-${projectName}-${environment}-${iteration}'
var eventHubName = 'evh-${projectName}-${environment}-${iteration}'
var adxClusterName = 'adx-${projectName}-${environment}-${iteration}' //max length of 22 characters

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: eventHubNamespaceName
  location: resourceGroup().location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }

  resource eventHub 'eventhubs' = {
    name: eventHubName
    properties: {
      messageRetentionInDays: 1
      partitionCount: 1
    }

    // only possible on higher SKU, so do not use on dev
    resource eventHubConsumerGroup 'consumergroups' = if (environment != 'dev' ) {
      name: 'cg-${adxClusterName}'
    }
  }
}

// generates 'AzureDiagnostics' logs
resource eventHubNamespaceDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (environment == 'dev') {
  name: '${eventHubNamespaceName}-diagnostic'
  scope: eventHubNamespace
  properties: {
    workspaceId: law.id
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

resource dataExport 'Microsoft.OperationalInsights/workspaces/dataExports@2023-09-01' = {
  parent: law
  name: 'export-adx'
  properties: {
    destination: {
      metaData: {
        eventHubName: eventHubNamespace::eventHub.name
      }
      resourceId: eventHubNamespace.id
    }
    // supported tables: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export?tabs=portal#supported-tables
    tableNames: [
      'LAQueryLogs'
      'LASummaryLogs'
      'AzureMetricsV2'
      'Operation' //Partial support. Some of the data is ingested through internal services that aren't supported in export. Currently, this portion is missing in export.
      'SucceededIngestion'
      'Usage'
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
  name: guid(eventHubNamespace::eventHub.id, adxCluster.name, 'Azure Event Hubs Data Receiver') // pattern: destination, identity, role
  scope: eventHubNamespace::eventHub
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
output eventHubId string = eventHubNamespace::eventHub.id
output eventHubConsumerGroupName string = environment == 'dev' ? '$Default' : eventHubNamespace::eventHub::eventHubConsumerGroup.name
