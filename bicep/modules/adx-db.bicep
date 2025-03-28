param adxClusterName string
param eventHubLawResourceId string
param eventHubDiagResourceId string
param eventHubConsumerGroupName string

@description('''
Leave default (utcNow()) to run the database scripts, pass an empty string to not run the scripts again.
Please see https://learn.microsoft.com/en-us/azure/data-explorer/database-script#omit-update-tag
''')
param runDatabaseScripts string = utcNow()

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
    softDeletePeriod: 'P13M' // 13 months retention
  }

  resource dbScript_DIAG_RawEvents 'scripts' = {
    name: 'DIAG_RawEvents'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/DIAG_RawEvents.kql')
      continueOnErrors: false
    }
  }

  resource dbScript_DIAG_ADXCommand 'scripts' = {
    name: 'DIAG_ADXCommand'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/DIAG_ADXCommand.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_DIAG_RawEvents
    ]
  }

  resource dbScript_LAW_RawEvents 'scripts' = {
    name: 'LAW_RawEvents'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/LAW_RawEvents.kql')
      continueOnErrors: false
    }
  }

  resource dbScript_LAW_LAQueryLogs 'scripts' = {
    name: 'LAW_LAQueryLogs'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/LAW_LAQueryLogs.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_LAW_RawEvents
    ]
  }

  resource dbScript_LAW_SucceededIngestion 'scripts' = {
    name: 'LAW_SucceededIngestion'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/LAW_SucceededIngestion.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_LAW_RawEvents
    ]
  }

  resource dbScript_LAW_ADXCommand 'scripts' = {
    name: 'LAW_ADXCommand'
    properties: {
      forceUpdateTag: runDatabaseScripts
      scriptContent: loadTextContent('../../kusto/LAW_ADXCommand.kql')
      continueOnErrors: false
    }
    dependsOn: [
      dbScript_LAW_RawEvents
    ]
  }

  resource adxLawDataConnection 'dataConnections' = {
    name: 'EventHub_LAW'
    kind: 'EventHub'
    location: resourceGroup().location
    properties: {
      eventHubResourceId: eventHubLawResourceId
      consumerGroup: eventHubConsumerGroupName
      managedIdentityResourceId: adxCluster.id
      dataFormat: 'MULTIJSON'
      mappingRuleName: 'DirectJson' //from LAW_RawEvents.kql
      eventSystemProperties: [
        'x-opt-enqueued-time'
      ]
      retrievalStartDate: '2022-01-01T00:00:00Z' // if you don't specify this, it will start from the current time, but it will set it as UTC, so you have to wait an hour (or 2 depending on summertime)
      tableName: 'LAW_RawEvents'
    }
    dependsOn: [
      dbScript_LAW_RawEvents
    ]
  }

  resource adxDiagDataConnection 'dataConnections' = {
    name: 'EventHub_DIAG'
    kind: 'EventHub'
    location: resourceGroup().location
    properties: {
      eventHubResourceId: eventHubDiagResourceId
      consumerGroup: eventHubConsumerGroupName
      managedIdentityResourceId: adxCluster.id
      dataFormat: 'MULTIJSON'
      mappingRuleName: 'DirectJson' //from DIAG_RawEvents.kql
      eventSystemProperties: [
        'x-opt-enqueued-time'
      ]
      retrievalStartDate: '2022-01-01T00:00:00Z' // if you don't specify this, it will start from the current time, but it will set it as UTC, so you have to wait an hour (or 2 depending on summertime)
      tableName: 'DIAG_RawEvents'
    }
    dependsOn: [
      dbScript_DIAG_RawEvents
    ]
  }
}
