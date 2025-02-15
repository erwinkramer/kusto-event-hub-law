/*

Connect-AzAccount
New-AzDeployment -Location "westeurope" -TemplateFile "./bicep/main.bicep"

*/

targetScope = 'subscription'

@allowed([
  'staging'
  'prod'
])
param environment string = 'staging'
param projectName string = '7h45hwsert3v23'

param workspaceName string = 'la-${projectName}'
param eventHubNamespaceName string = 'evhns-${projectName}'
param eventHubName string = 'evh-${projectName}'
param adxClusterName string = 'adx-${projectName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: 'rg-${projectName}'
  location: 'westeurope'
}

module adx 'adx.bicep' = {
  name: 'adxDeployment'
  scope: resourceGroup
  params: {
    environment: environment
    adxClusterName: adxClusterName
    workspaceName: workspaceName
    eventHubNamespaceName: eventHubNamespaceName
    eventHubName: eventHubName
  }
}
