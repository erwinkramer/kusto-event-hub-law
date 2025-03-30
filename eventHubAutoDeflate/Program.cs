/*

Auto-deflate Event Hubs namespace capacity based on a minimum capacity threshold and throttling detection.

*/

using Azure.Identity;

var eventHubNamespaceConfigs = new List<EventHubNamespaceConfig>
{
    new EventHubNamespaceConfig
    {
        ResourceId = "/subscriptions/beb880cc-af9a-4e4d-8e8e-54739967674f/resourceGroups/rg-events/providers/Microsoft.EventHub/namespaces/g5465jtrfdgdfg3443g34",
        MinimumCapacity = 1
    },
    new EventHubNamespaceConfig
    {
        ResourceId = "/subscriptions/beb880cc-af9a-4e4d-8e8e-54739967674f/resourceGroups/rg-ade-sandbox/providers/Microsoft.EventHub/namespaces/asdads2d2d21d",
        MinimumCapacity = 1 
    }
};

var credential = new DefaultAzureCredential();

var exceptions = new List<Exception>();

foreach (var eventHubNamespaceConfig in eventHubNamespaceConfigs)
{
    try
    {
        var eventHubNamespaceCapacityManager = new EventHubNamespaceCapacityManager(eventHubNamespaceConfig.ResourceId, eventHubNamespaceConfig.MinimumCapacity, credential);
        await eventHubNamespaceCapacityManager.DeflateNamespaceIfNeeded();
    }
    catch (Exception ex)
    {
        exceptions.Add(new Exception($"Error processing namespace {eventHubNamespaceConfig.ResourceId}: {ex.Message}", ex));
    }
}

if (exceptions.Any())
{
    throw new AggregateException("One or more namespaces failed to deflate.", exceptions);
}
