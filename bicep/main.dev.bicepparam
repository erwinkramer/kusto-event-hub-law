using './main.bicep'

param environment = 'dev'
param projectName = 'github'
param iteration = '004'

param environmentTags = {
  pipeline: readEnvironmentVariable('Build.DefinitionName')
}
