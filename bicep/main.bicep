/*

Connect-AzAccount
New-AzDeployment -Location "westeurope" -TemplateFile "./bicep/main.bicep" -TemplateParameterFile "./bicep/main.dev.bicepparam"      

*/

targetScope = 'subscription'

@allowed([
  'dev'
  'prd'
])
param environment string

@maxLength(8)
@description('short name of the project, adx cluster has a max length of 22 characters, so keep this project name short')
param projectName string

@maxLength(3)
@description('iteration of the project, used for most resource names')
param iteration string

param environmentTags object

var tags = union(environmentTags, {
  environment: environment
  projectName: projectName
  iteration: iteration
})

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: 'rg-${projectName}-${environment}-${iteration}'
  tags: tags
  location: 'westeurope'
}

module law 'modules/law.bicep' = {
  name: 'law'
  scope: resourceGroup
  params: {
    tags: tags
    environment: environment
    projectName: projectName
    iteration: iteration
  }
}

module adx 'modules/adx.bicep' = {
  name: 'adx'
  scope: resourceGroup
  params: {
    tags: tags
    environment: environment
    projectName: projectName
    iteration: iteration
    logAnalyticsWorkspaceName: law.outputs.logAnalyticsWorkspaceName
  }
}

module adxDb 'modules/adx-db.bicep' = {
  name: 'adxDb'
  scope: resourceGroup
  params: {
    adxClusterName: adx.outputs.adxClusterName
    eventHubResourceId: adx.outputs.eventHubId
    eventHubConsumerGroupName: adx.outputs.eventHubConsumerGroupName
  }
}
