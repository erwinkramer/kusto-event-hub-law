/*

Connect-AzAccount
New-AzDeployment -Location "westeurope" -TemplateFile "./bicep/main.bicep"

*/

targetScope = 'subscription'

param projectName string = 'f32fv23v23'

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
    adxClusterName: adxClusterName
    workspaceName: workspaceName
    eventHubNamespaceName: eventHubNamespaceName
    eventHubName: eventHubName
  }
}
