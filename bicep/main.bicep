/*

Connect-AzAccount -TenantId b81eb003-1c5c-45fd-848f-90d9d3f8d016
New-AzSubscriptionDeploymentStack -Name Stack-Adx -Location "westeurope" -ActionOnUnmanage DeleteAll -DenySettingsMode None -TemplateFile "./bicep/main.bicep" -TemplateParameterFile "./bicep/main.dev.bicepparam" -Force

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

@description('The budget of the project, in euros')
param budgetInEuros int

param adxSkuName string

@minValue(1)
@maxValue(40)
@description('''
Doesn't automatically scale down, please see https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-auto-inflate?WT.mc_id=Portal-Microsoft_Azure_EventHub#how-auto-inflate-works-in-standard-tier
''')
param eventHubMaxThroughputUnits int

var contactEmail = 'info@guanchen.nl'
var entraIdGroupDataViewersObjectId = '7bd75f2d-e855-4a3d-82bd-e6be0b71bbb9' //adx-readers

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

resource costBudget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: 'budget-${projectName}-${environment}-${iteration}'
  properties: {
    category: 'Cost'
    amount: budgetInEuros
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2025-02-01T00:00:00Z'
      endDate: '2026-12-01T00:00:00Z'
    }
    notifications: {
      actual: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: [
          contactEmail
        ]
      }
    }
    filter: {
      dimensions: {
        name: 'ResourceGroup'
        operator: 'In'
        values: [
          resourceGroup.id
        ]
      }
    }
  }
}

module ag 'modules/ag.bicep' = {
  name: 'ag'
  scope: resourceGroup
  params: {
    tags: tags
    contactEmail: contactEmail
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: resourceGroup
  params: {
    tags: tags
    environment: environment
    projectName: projectName
    iteration: iteration
  }
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

module evh 'modules/evh.bicep' = {
  name: 'evh'
  scope: resourceGroup
  params: {
    tags: tags
    inboundSubnetId: network.outputs.inboundSubnetId
    logAnalyticsWorkspaceName: law.outputs.logAnalyticsWorkspaceName
    environment: environment
    projectName: projectName
    iteration: iteration
    eventHubMaxThroughputUnits: eventHubMaxThroughputUnits
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
    adxSkuName: adxSkuName
    logAnalyticsWorkspaceName: law.outputs.logAnalyticsWorkspaceName
    inboundSubnetId: network.outputs.inboundSubnetId
    eventHubDiagnosticsName: evh.outputs.eventHubDiagName
    eventHubDiagnosticsAuthorizationRuleId: evh.outputs.eventHubDiagAuthorizationRuleId
    entraIdGroupDataViewersObjectId: entraIdGroupDataViewersObjectId
    actionGroupId: ag.outputs.actionGroupId
  }
}

module adxDb 'modules/adx-db.bicep' = {
  name: 'adxDb'
  scope: resourceGroup
  params: {
    adxClusterName: adx.outputs.adxClusterName
    eventHubLawResourceId: evh.outputs.eventHubLawId
    eventHubDiagResourceId: evh.outputs.eventHubDiagId
    eventHubConsumerGroupName: evh.outputs.eventHubConsumerGroupName
  }
}
