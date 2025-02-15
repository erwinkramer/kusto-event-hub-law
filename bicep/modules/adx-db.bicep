param adxClusterName string
param eventHubResourceId string

resource adxCluster 'Microsoft.Kusto/clusters@2024-04-13' existing = {
  name: adxClusterName
}

resource adxDatabase 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  parent: adxCluster
  name: 'dedb-main'
  location: resourceGroup().location
  kind: 'ReadWrite'
  properties: {
    hotCachePeriod: 'P1D'
  }

  resource dbScript_RawEvents 'scripts' = {
    name: 'RawEvents'
    properties: {
      scriptContent: loadTextContent('../../kusto/RawEvents.kql')
      continueOnErrors: false
    }
  }

  resource dbScript_LAW_LAQueryLogs 'scripts' = {
    name: 'LAW_LAQueryLogs'
    properties: {
      scriptContent: loadTextContent('../../kusto/LAW_LAQueryLogs.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_RawEvents
    ]
  }

  resource dbScript_LAW_SucceededIngestion 'scripts' = {
    name: 'LAW_SucceededIngestion'
    properties: {
      scriptContent: loadTextContent('../../kusto/LAW_SucceededIngestion.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_RawEvents
    ]
  }

  resource adxDataConnection 'dataConnections' = {
    name: 'EventHub'
    kind: 'EventHub'
    location: resourceGroup().location
    properties: {
      eventHubResourceId: eventHubResourceId
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
      dbScript_RawEvents
    ]
  }
}
