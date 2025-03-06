param tags object
param projectName string
param environment string
param iteration string
param adxSkuName string
param logAnalyticsWorkspaceName string
param inboundSubnetId string
param eventHubDiagnosticsName string
param eventHubDiagnosticsAuthorizationRuleId string
param entraIdGroupDataViewersObjectId string
param actionGroupId string

var adxClusterName = 'adx-${projectName}-${environment}-${iteration}' //max length of 22 characters
var deployZoneGroupsViaPolicy = true

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource adxCluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: adxClusterName
  tags: tags
  location: resourceGroup().location
  zones: ['1', '2', '3'] // fully zone redundant
  sku: {
    tier: environment == 'dev' ? 'Basic' : 'Standard'
    name: adxSkuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    optimizedAutoscale: environment == 'dev'
      ? null
      : {
          isEnabled: true
          minimum: 2
          maximum: 20
          version: 1
        }
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
  tags: tags
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

  resource privateEndpointDsnZoneGroupResource 'privateDnsZoneGroups' = if (deployZoneGroupsViaPolicy) {
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

resource alertIngestionSuccess 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'al-${adxClusterName}-ingestion'
  location: 'global'
  tags: tags
  properties: {
    severity: 3
    enabled: true
    scopes: [
      adxCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Medium'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 4
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Kusto/clusters'
          metricName: 'IngestionResult'
          dimensions: [
            {
              name: 'IngestionResultDetails'
              operator: 'Exclude'
              values: [
                'Success'
              ]
            }
          ]
          operator: 'GreaterOrLessThan'
          timeAggregation: 'Total'
          skipMetricValidation: false
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    targetResourceType: 'Microsoft.Kusto/clusters'
    targetResourceRegion: resourceGroup().location
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}

resource alertCpu 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: 'al-${adxClusterName}-cpu'
  location: 'global'
  tags: tags
  properties: {
    severity: 3
    enabled: true
    scopes: [
      adxCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Low'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 4
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Kusto/clusters'
          metricName: 'CPU'
          operator: 'GreaterOrLessThan'
          timeAggregation: 'Average'
          skipMetricValidation: false
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    targetResourceType: 'Microsoft.Kusto/clusters'
    targetResourceRegion: resourceGroup().location
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}

resource alertLatency 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'al-${adxClusterName}-latency'
  location: 'global'
  tags: tags
  properties: {
    severity: 3
    enabled: true
    scopes: [
      adxCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Low'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 4
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Kusto/clusters'
          metricName: 'IngestionLatencyInSeconds'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          skipMetricValidation: false
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    targetResourceType: 'Microsoft.Kusto/clusters'
    targetResourceRegion: resourceGroup().location
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}

output adxClusterName string = adxCluster.name
