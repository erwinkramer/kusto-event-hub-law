param contactEmail string
param tags object

resource actionGroup 'Microsoft.Insights/actionGroups@2024-10-01-preview' = {
  name: 'adxActionGroup'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'adxAG'
    enabled: true
    emailReceivers: [
      {
        name: 'adxEmailReceiver'
        emailAddress: contactEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

output actionGroupId string = actionGroup.id
