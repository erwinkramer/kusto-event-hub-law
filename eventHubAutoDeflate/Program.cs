/*

Auto-deflate Event Hubs namespace capacity based on a minimum capacity threshold and throttling detection.

*/

using Azure.Identity;

// comma separated resource ids of the Event Hubs namespace
var namespaceResourceIds = "/subscriptions/beb880cc-af9a-4e4d-8e8e-54739967674f/resourceGroups/rg-events/providers/Microsoft.EventHub/namespaces/g5465jtrfdgdfg3443g34,/subscriptions/beb880cc-af9a-4e4d-8e8e-54739967674f/resourceGroups/rg-ade-sandbox/providers/Microsoft.EventHub/namespaces/asdads2d2d21d";
var namespaceInstanceMinimumCapacity = 1; // should be set to a realistic value depending on your lower bound workload

var credential = new DefaultAzureCredential();

var exceptions = new List<Exception>();

foreach (var namespaceResourceId in namespaceResourceIds.Split(','))
{
    try
    {
        var eventHubNamespaceCapacityManager = new EventHubNamespaceCapacityManager(namespaceResourceId, namespaceInstanceMinimumCapacity, credential);
        await eventHubNamespaceCapacityManager.DeflateNamespaceIfNeeded();
    }
    catch (Exception ex)
    {
        exceptions.Add(new Exception($"Error processing namespace {namespaceResourceId}: {ex.Message}", ex));
    }
}

if (exceptions.Any())
{
    throw new AggregateException("One or more namespaces failed to deflate.", exceptions);
}
