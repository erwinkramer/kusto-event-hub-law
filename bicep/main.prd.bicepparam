using './main.bicep'

param environment = 'prd'
param projectName = 'github'
param iteration = '002'

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
