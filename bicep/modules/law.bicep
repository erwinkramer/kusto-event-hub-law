param tags object
param projectName string
param environment string
param iteration string

var workspaceName = 'la-${projectName}-${environment}-${iteration}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  tags: tags
  location: resourceGroup().location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

// do some queries in the insights blade of the LAW (just opening the blade is enough)
// generates 'LAQueryLogs' logs
resource logAnalyticsDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (environment == 'dev') {
  name: '${workspaceName}-diagnostic'
  scope: logAnalyticsWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
