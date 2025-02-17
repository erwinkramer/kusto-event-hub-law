using './main.bicep'

param environment = 'dev'
param projectName = 'github'
param iteration = '002'

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
