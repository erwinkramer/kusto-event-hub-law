param tags object
param projectName string
param environment string
param iteration string
param logAnalyticsWorkspaceName string
param inboundSubnetId string

var eventHubNamespaceName = 'evhns-${projectName}-${environment}-${iteration}'
var eventHubLogAnalyticsWorkspaceName = 'evh-${projectName}-law-${environment}-${iteration}'
var eventHubDiagnosticsSettingsName = 'evh-${projectName}-diag-${environment}-${iteration}'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: eventHubNamespaceName
  tags: tags
  location: resourceGroup().location
  sku: {
    name: 'Standard' //'Basic' doesn't private endpoints, 'Standard' does
    tier: 'Standard'
  }

  resource sendRuleDiag 'authorizationRules' = {
    name: 'sendRuleDiag'
    properties: {
      rights: [
        'Send'
      ]
    }
  }

  resource eventHubLaw 'eventhubs' = {
    name: eventHubLogAnalyticsWorkspaceName
    properties: {
      messageRetentionInDays: 1
      partitionCount: 1
      userMetadata: 'Used for flow: Log Analytics Workspace --> Event Hub --> Kusto Cluster'
    }
  }

  resource eventHubDiag 'eventhubs' = {
    name: eventHubDiagnosticsSettingsName
    properties: {
      messageRetentionInDays: 1
      partitionCount: 1
      userMetadata: 'Used for flow: Diagnostic settings --> Event Hub --> Kusto Cluster'
    }
  }
}

resource eventHubNamespacePe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${eventHubNamespaceName}'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: inboundSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'namespaceConnection'
        properties: {
          privateLinkServiceId: eventHubNamespace.id
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }

  resource privateEndpointDsnZoneGroupResource 'privateDnsZoneGroups' = {
    name: 'eventhub'
    properties: {
      privateDnsZoneConfigs: [
        for dnsZone in ['privatelink.servicebus.windows.net']: {
          name: dnsZone
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', dnsZone)
          }
        }
      ]
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
        eventHubName: eventHubNamespace::eventHubLaw.name
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
      'ADXCommand'
      'Usage'
    ]
  }
}

output eventHubConsumerGroupName string = '$Default'
output eventHubLawId string = eventHubNamespace::eventHubLaw.id
output eventHubDiagId string = eventHubNamespace::eventHubDiag.id
output eventHubDiagName string = eventHubNamespace::eventHubDiag.name
output eventHubDiagAuthorizationRuleId string = eventHubNamespace::sendRuleDiag.id
