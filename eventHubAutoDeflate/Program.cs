/*

Auto-deflate Event Hubs namespace capacity based on a minimum capacity threshold and throttling detection.

*/

using Azure.Identity;
using Azure.Monitor.Query;
using Azure.ResourceManager;
using Azure.ResourceManager.EventHubs;
using Azure.ResourceManager.EventHubs.Models;

var subscriptionId = "beb880cc-af9a-4e4d-8e8e-54739967674f";
var resourceGroupName = "rg-events";
var namespaceName = "fref23v32v32f32f";
var namespaceInstanceMinimumCapacity = 1; // should be set to a realistic value depending on your lower bound workload

var credential = new DefaultAzureCredential();
var armClient = new ArmClient(credential);
var metricsQueryClient = new MetricsQueryClient(credential);

var namespaceIdentifier = EventHubsNamespaceResource.CreateResourceIdentifier(subscriptionId, resourceGroupName, namespaceName);

var eventHubsNamespace = armClient.GetEventHubsNamespaceResource(namespaceIdentifier);
var namespaceData = (await eventHubsNamespace.GetAsync()).Value.Data;

if (!IsAutoInflateEnabled(namespaceData))
{
    Console.WriteLine("Namespace is not set to auto inflate, skip deflate process");
    return;
}

if (IsNamespaceThrottled(metricsQueryClient, namespaceIdentifier!).Result)
{
    Console.WriteLine("Namespace is throttled, skip deflate process");
    return;
}

if (!TryDeflateNamespace(eventHubsNamespace, namespaceData, namespaceInstanceMinimumCapacity).Result)
{
    Console.WriteLine($"Namespace capacity ({namespaceData.Sku.Capacity}) is already at minimum, or same as current capacity, skip deflate process");
    return;
}

/// <summary>
/// Queries the Event Hub namespace for the ThrottledRequests metric to determine if the namespace is throttled.
/// Uses a time span of an hour to query the metric.
/// </summary>
async Task<bool> IsNamespaceThrottled(MetricsQueryClient metricsQueryClient, string namespaceIdentifier)
{
    var metricResult = (await metricsQueryClient.QueryResourceAsync(
        namespaceIdentifier,
        ["ThrottledRequests"],
        new MetricsQueryOptions()
        {
            Granularity = new TimeSpan(1, 0, 0),
            TimeRange = new QueryTimeRange(DateTime.UtcNow.AddHours(-1), DateTime.UtcNow)
        }
    )).Value.Metrics.FirstOrDefault();

    if (metricResult == null)
    {
        Console.WriteLine("ThrottledRequests metric not found");
        return true;
    }

    var throttledRequestTotal = metricResult.TimeSeries.FirstOrDefault()!.Values.FirstOrDefault()!.Total;
    return throttledRequestTotal > 0;
}

bool IsAutoInflateEnabled(EventHubsNamespaceData namespaceData)
{
    return namespaceData.IsAutoInflateEnabled.HasValue && namespaceData.IsAutoInflateEnabled.Value;
}

async Task<bool> TryDeflateNamespace(EventHubsNamespaceResource eventHubsNamespace, EventHubsNamespaceData namespaceData, int minimumCapacity)
{
    var newCapacity = namespaceData.Sku.Capacity - 1;

    if (newCapacity < minimumCapacity || newCapacity == namespaceData.Sku.Capacity)
    {
        return false;
    }

    EventHubsNamespaceData namespaceDataRequest = new EventHubsNamespaceData(namespaceData.Location)
    {
        Sku = new EventHubsSku(namespaceData.Sku.Name)
        {
            Capacity = newCapacity
        }
    };

    var namespaceDataUpdated = (await eventHubsNamespace.UpdateAsync(namespaceDataRequest)).Value.Data;
    Console.WriteLine($"New capacity set to: {namespaceDataUpdated.Sku.Capacity}, previous capacity was {namespaceData.Sku.Capacity}");
    return true;
}
