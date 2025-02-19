using './main.bicep'

param environment = 'prd'
param projectName = 'github'
param iteration = '003'
param budgetInEuros = 1600
param adxSkuName = 'Standard_E8as_v5+1TB_PS' // modern, storage optimized SkU - $1.631/h
param eventHubMaxThroughputUnits = 5

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
