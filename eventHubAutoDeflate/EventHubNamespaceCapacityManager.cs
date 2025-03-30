using Azure.Core;
using Azure.Monitor.Query;
using Azure.ResourceManager;
using Azure.ResourceManager.EventHubs;
using Azure.ResourceManager.EventHubs.Models;

public class EventHubNamespaceCapacityManager
{
    private readonly EventHubNamespaceConfig _eventHubNamespaceConfig;
    private readonly ArmClient _armClient;
    private readonly MetricsQueryClient _metricsQueryClient;

    public EventHubNamespaceCapacityManager(EventHubNamespaceConfig eventHubNamespaceConfig, TokenCredential credential)
    {
        _eventHubNamespaceConfig = eventHubNamespaceConfig;
        _armClient = new ArmClient(credential);
        _metricsQueryClient = new MetricsQueryClient(credential);
    }

    public async Task DeflateNamespaceIfNeeded()
    {
        var namespaceIdentifier = new ResourceIdentifier(_eventHubNamespaceConfig.ResourceId);
        var eventHubsNamespace = _armClient.GetEventHubsNamespaceResource(namespaceIdentifier);
        EventHubsNamespaceData namespaceData;

        try
        {
            namespaceData = (await eventHubsNamespace.GetAsync()).Value.Data;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Could not get namespace data, with message: {ex.Message}");
            throw;
        }

        if (!IsAutoInflateEnabled(namespaceData))
        {
            Console.WriteLine("Namespace is not set to auto inflate, skip deflate process");
            return;
        }

        if (await IsNamespaceThrottled(namespaceIdentifier!))
        {
            Console.WriteLine("Namespace is throttled, skip deflate process");
            return;
        }

        if (!await TryDeflateNamespace(eventHubsNamespace, namespaceData))
        {
            Console.WriteLine($"Namespace capacity ({namespaceData.Sku.Capacity}) is already at minimum, or same as current capacity, skip deflate process");
            return;
        }
    }

    private async Task<bool> IsNamespaceThrottled(string namespaceIdentifier)
    {
        var metricResult = (await _metricsQueryClient.QueryResourceAsync(
            namespaceIdentifier,
            new[] { "ThrottledRequests" },
            new MetricsQueryOptions
            {
                Granularity = TimeSpan.FromHours(1),
                TimeRange = new QueryTimeRange(DateTime.UtcNow.AddHours(-1), DateTime.UtcNow)
            }
        )).Value.Metrics.FirstOrDefault();

        if (metricResult == null)
        {
            throw new InvalidOperationException("ThrottledRequests metric not found");
        }

        var throttledRequestTotal = metricResult.TimeSeries.FirstOrDefault()?.Values.FirstOrDefault()?.Total ?? 0;
        Console.WriteLine($"Namespace has {throttledRequestTotal} throttled requests in the last hour.");

        return throttledRequestTotal > 0;
    }

    private bool IsAutoInflateEnabled(EventHubsNamespaceData namespaceData)
    {
        return namespaceData.IsAutoInflateEnabled.HasValue && namespaceData.IsAutoInflateEnabled.Value;
    }

    private async Task<bool> TryDeflateNamespace(EventHubsNamespaceResource eventHubsNamespace, EventHubsNamespaceData namespaceData)
    {
        var newCapacity = namespaceData.Sku.Capacity - 1;

        if (newCapacity < _eventHubNamespaceConfig.MinimumCapacity || newCapacity == namespaceData.Sku.Capacity)
        {
            return false;
        }

        var namespaceDataRequest = new EventHubsNamespaceData(namespaceData.Location)
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
}
