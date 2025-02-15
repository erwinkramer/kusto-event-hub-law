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

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: 'rg-${projectName}'
  location: 'westeurope'
}

module adx 'adx.bicep' = {
  name: 'adxDeployment'
  scope: resourceGroup
  params: {
    environment: environment
    projectName: projectName
  }
}
