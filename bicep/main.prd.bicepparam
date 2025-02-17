using './main.bicep'

param environment = 'prd'
param projectName = 'github'
param iteration = '003'

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
