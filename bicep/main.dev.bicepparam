using './main.bicep'

param environment = 'dev'
param projectName = 'github'
param iteration = '004'
param budgetInEuros = 150
param adxSkuName = 'Dev(No SLA)_Standard_E2a_v4' // Dev tier (No SLA) - $0.152/h
param eventHubMaxThroughputUnits = 1

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
