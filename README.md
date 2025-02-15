# kusto-event-hub-law

Log Analytics Workspace export to Event Hub to Kusto Cluster (Azure Data Explorer).

*The code is the documentation :)*

Some bits were from: https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.kusto/kusto-event-hub/main.bicep, but i took the cheapest SKUs and the simplest testable setup, batteries included.

## Kusto extension 

For [the Kusto Language Server](https://marketplace.visualstudio.com/items?itemName=rosshamish.kuskus-kusto-language-server) extension, that installs with the VS Code recommendations, please install specific version `3.4.1` and not `3.4.2`, because of issue [Language Server v3.4.2 not working #218](https://github.com/rosshamish/kuskus/issues/218).

## Routing options

Either:

1. remove the `eventHubName` element from the `Microsoft.OperationalInsights/workspaces/dataExport` to [dynamically route to an event hub with the table name](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export?tabs=portal#event-hubs), then create a `Microsoft.Kusto/clusters/databases/dataConnections` for each event hub.
1. make the Kusto query smarter and use the `Type` column to place the records in the right table. Something [like this](https://learn.microsoft.com/en-us/kusto/management/update-policy-tutorial?view=microsoft-fabric#1---create-tables-and-update-policies).