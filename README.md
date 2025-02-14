# kusto-event-hub-law

Log Analytics Workspace export to Event Hub to Kusto Cluster (Azure Data Explorer).

*The code is the documentation :)*

Some bits were from: https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.kusto/kusto-event-hub/main.bicep, but i took the cheapest SKUs and the simplest testable setup, batteries included.

Please see last comment on [script.kql](/bicep/script.kql) for the real work.

## Routing options

Either:

1. remove the `eventHubName` element from the `Microsoft.OperationalInsights/workspaces/dataExport` to [dynamically route to an event hub with the table name](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export?tabs=portal#event-hubs), then create a `Microsoft.Kusto/clusters/databases/dataConnections` for each event hub.
1. make the Kusto query smarter and use the `Type` column to place the records in the right table.