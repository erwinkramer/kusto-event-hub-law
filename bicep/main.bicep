/*

Connect-AzAccount
New-AzDeployment -Location "westeurope" -TemplateFile "./bicep/main.bicep"

*/

targetScope = 'subscription'

@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@maxLength(8)
@description('short name of the project, adx cluster has a max length of 22 characters, so keep this project name short')
param projectName string = 'github'

@maxLength(3)
@description('iteration of the project, used for most resource names')
param iteration string = '002'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: 'rg-${projectName}-${environment}-${iteration}'
  location: 'westeurope'
}

module law 'law.bicep' = {
  name: 'law'
  scope: resourceGroup
  params: {
    environment: environment
    projectName: projectName
    iteration: iteration
  }
}

module adx 'adx.bicep' = {
  name: 'adx'
  scope: resourceGroup
  params: {
    environment: environment
    projectName: projectName
    iteration: iteration
    logAnalyticsWorkspaceName: law.outputs.logAnalyticsWorkspaceName
  }
}

module adxDb './adx-db.bicep' = {
  name: 'adxDb'
  scope: resourceGroup
  params: {
    adxClusterName: adx.outputs.adxClusterName
    eventHubResourceId: adx.outputs.eventHubId
  }
}
