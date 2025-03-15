# Streaming logs to a Kusto Cluster 🤽🏻‍♂️ #

[![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]
![GitHub commit activity](https://img.shields.io/github/commit-activity/m/erwinkramer/kusto-event-hub-law)

Stream various logs to a Kusto Cluster (Azure Data Explorer Cluster), such as:
- Log Analytics logs, via export functionality and Event Hub
- Diagnostics logs, via Event Hub
- External logs, via plugins

Some bits were from the [azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.kusto/kusto-event-hub/main.bicep), but i took the cheapest SKUs and the simplest testable setup, batteries included.

## Configuration ##

1. `privateDnsZoneGroups` for the Kusto private endpoint can be deployed via the [policy_definition_configure_private_dns_zone_adx](/policy/policy_definition_configure_private_dns_zone_adx.json) policy, or via Bicep by setting `deployZoneGroupsViaPolicy` to `false`.

2. Create an Entra ID group for read permissions on the database, and provide the object id to the `entraIdGroupDataViewersObjectId` var in Bicep.

## Kusto extension ##

For [the Kusto Language Server](https://marketplace.visualstudio.com/items?itemName=rosshamish.kuskus-kusto-language-server) extension, that installs with the VS Code recommendations, please install specific version `3.4.1` and not `3.4.2`, because of issue [Language Server v3.4.2 not working #218](https://github.com/rosshamish/kuskus/issues/218).

## Multi-region design ##

Because Event Hubs can only connect to resources from the same region, consider the following simplified design for connecting multiple regions and sources:

```mermaid
flowchart LR

ext[External Sources]
ext -- plugins --> misctable

msdef[Microsoft Defender]
msdef --> evhdeweu --> defetable

subgraph Azure - West Europe
    reslaweu[Log Analytics Resources]
    resweu[Azure Resources]

    subgraph Event Hub Namespace
        evhlaweu[Event Hub - Log Analytics]
        evhdiweu[Event Hub - Diagnostics]
        evhdeweu[Event Hub - Defender]
    end

    
    subgraph Azure Data Explorer Db
        lawtable[Azure Monitor Table]
        diagtable[Diagnostics Table]
        defetable[Defender Table]
        misctable[Miscellaneous Tables]
    end

    reslaweu--Export functionality-->evhlaweu-->lawtable

    resweu--Diagnostic settings-->evhdiweu-->diagtable
end
    
subgraph Azure - North Europe
    resneu[Azure Resources]

    subgraph Event Hub Namespace
        evhdineu[Event Hub - Diagnostics]
    end

    resneu--Diagnostic settings-->evhdineu-->diagtable
end
```

## Generic table design ##

Generic handling of events is possible because of the standardization in logs:

- The `Azure Monitor Table` follows the [Standard columns in Azure Monitor Logs](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-standard-columns). With use of  [bag_pack_columns](https://learn.microsoft.com/en-us/kusto/query/bag-pack-columns-function?view=azure-data-explorer) (to pack all non-standard columns inside a property column) and [project-away](https://learn.microsoft.com/en-us/kusto/query/project-away-operator?view=azure-data-explorer) (to exclude standard columns in the property column) you can make a generic kusto table.

- The `Diagnostics Table` follows the [Azure resource log common schema](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs-schema#top-level-common-schema).

- The `Defender Table` follows the [schema of the events in Azure Event Hubs](https://learn.microsoft.com/en-us/defender-endpoint/api/raw-data-export-event-hub#the-schema-of-the-events-in-azure-event-hubs)

- The `Defender for Cloud Table` follows the [Workflow automation and export data types schemas](https://github.com/Azure/Microsoft-Defender-for-Cloud/tree/main/Powershell%20scripts/Workflow%20automation%20and%20export%20data%20types%20schemas)

## Routing options ##

### Event Hub routing ###

> Note: Specific for exports from Log Analytics workspace.

Remove the `eventHubName` element from the `Microsoft.OperationalInsights/workspaces/dataExport` to [dynamically route to an event hub with the table name](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export?tabs=portal#event-hubs), then create a `Microsoft.Kusto/clusters/databases/dataConnections` for each event hub.

### ADX routing ###

Make the Kusto query smarter and use the `Type` column to place the records in specific tables, using something [like this](https://learn.microsoft.com/en-us/kusto/management/update-policy-tutorial?view=azure-data-explorer#1---create-tables-and-update-policies) to directly place data in a specific table. You can also use generic tables, as mentioned at [Generic table design](#generic-table-design).

To end up in specific tables in a performant way, you can first put them in a generic table, and then set policies to push the records into specific tables, this scales a bit better, since you would only do `mv-expand` once for each record when putting the records in the generic table. See [DIAG_generic](./kusto/DIAG_Generic.kql) and [DIAG_ADXCommand](./kusto/DIAG_ADXCommand.kql) for a sample. Visually it will look like this:

```mermaid
flowchart TD
  
rawlogs[Raw Log table, with softdelete = 0d]
gendiag[Generic Diagnostics table, with softdelete = 0d]
ts[Table storage logs]
bs[Blob storage logs]
qs[Queue storage logs]

rawlogs -- policy: mv-expand--> gendiag
gendiag -- policy: category==table --> ts
gendiag -- policy: category==queue --> qs
gendiag -- policy: category==blob --> bs
```

This model is similar to a [Medallion architecture](https://learn.microsoft.com/en-us/kusto/management/update-policy-common-scenarios?view=azure-data-explorer#medallion-architecture-data-enrichment). To monitor performance impact, please use [.show queries](https://learn.microsoft.com/en-us/kusto/management/update-policy?view=azure-data-explorer#performance-impact).

### Stream Analytics routing ### 

Stream Analytics can be placed between Event Hub and Azure Data Explorer, with the [no-code editor](https://learn.microsoft.com/en-us/azure/stream-analytics/no-code-stream-processing) it might look like this in a Stream Analytics job:

![Stream Analytics](.images/stream-analytics-nocode.png)

Considerations:

1. Because events get batched at Event Hub, you still have to expand to the actual events from the `records` array inside a job. 
1. Every adx table is 1 output, there's a hard limit of [60 outputs per Stream Analytics job](https://github.com/MicrosoftDocs/azure-docs/blob/main/includes/stream-analytics-limits-table.md), you could work around this by making multiple Event Hub [Consumer Groups](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-features#consumer-groups) and process the same events in multiple jobs.
1. The designer is nice, but not possible to switch from no-code to code and back, you will be presented with the following message, maybe this is a preview limitation:
   > Once confirmed to edit the query, no-code editor will no longer be available.
2. Without designer, you have to work with the [Stream Analytics Query Language](https://learn.microsoft.com/en-us/stream-analytics-query/stream-analytics-query-language-reference?toc=https%3A%2F%2Flearn.microsoft.com%2Fen-us%2Fazure%2Fstream-analytics%2Ftoc.json&bc=https%3A%2F%2Flearn.microsoft.com%2Fen-us%2Fazure%2Fbread%2Ftoc.json), where Stream Analytics [User Defined Functions (UDF), either in JavaScript or C#](https://learn.microsoft.com/en-us/azure/stream-analytics/functions-overview) can provide reusable snippets. UDF's are limited to 60 per job.
3. With a [Multi-region design](#multi-region-design), you end up with an event hub input for each region. In a single job, within the designer, this not practical to work with, since you cannot connect more than 1 input to an operation (such as `filter` or `expand`).

## License ##

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg
