using './main.bicep'

param environment = 'dev'
param projectName = 'github'
param iteration = '004'
param adxMaxInstanceCount = 2
param eventHubMaxThroughputUnits = 1

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
