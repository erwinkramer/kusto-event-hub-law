using './main.bicep'

param environment = 'prd'
param projectName = 'github'
param iteration = '003'
param adxMaxInstanceCount = 20
param eventHubMaxThroughputUnits = 5

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
