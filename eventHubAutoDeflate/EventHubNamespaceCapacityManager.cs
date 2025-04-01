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

        if (await IsNamespaceUnitsRealistic(namespaceIdentifier!, (int)namespaceData.Sku.Capacity!))
        {
             Console.WriteLine("Namespace units is realistic, skip deflate process");
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

    /// <summary>
    /// Throughput units are the measure of capacity for Event Hubs. Each unit is capable of:
    /// Ingress (IncomingBytes metric): Up to 1 MB per second or 1,000 events per second (whichever comes first).
    /// Egress (OutgoingBytes metric): Up to 2 MB per second or 4,096 events per second.
    /// 
    /// This method checks if the namespace TUs are realistic based on the IncomingBytes and OutgoingBytes metrics.
    /// </summary>
    private async Task<bool> IsNamespaceUnitsRealistic(string namespaceIdentifier, int currentCapacity)
    {
        var metricResults = (await _metricsQueryClient.QueryResourceAsync(
            namespaceIdentifier,
            new[] { "IncomingBytes", "OutgoingBytes" },
            new MetricsQueryOptions
            {
                Granularity = TimeSpan.FromMinutes(1), //supported ones are: PT1M,PT5M,PT15M,PT30M,PT1H,PT6H,PT12H,P1D
                TimeRange = new QueryTimeRange(DateTime.UtcNow.AddHours(-1), DateTime.UtcNow)
            }
        )).Value.Metrics;

        if (metricResults.Count != 2)
        {
            Console.WriteLine($"Namespace has {metricResults.Count} metrics, expected 2 (IncomingBytes and OutgoingBytes).");
            throw new InvalidOperationException("IncomingBytes and OutgoingBytes metric not found");
        }

        foreach (var metricResult in metricResults)
        {
            var metricName = metricResult.Name;
            var currentBytesPerMinuteUpperBound = metricResult.TimeSeries
                .SelectMany(ts => ts.Values)
                .Max(value => value.Total ?? 0);

            if (metricName == "IncomingBytes")
            {
                var realisticIncomingBytesPerMinute = Math.Max(currentCapacity - 1, 1) * 1_000_000 * 60; // Ensure at least 1 TU margin and convert to per minute
                if (currentBytesPerMinuteUpperBound < realisticIncomingBytesPerMinute)
                {
                    Console.WriteLine($"Namespace has {currentBytesPerMinuteUpperBound} incoming bytes, which is lower than the realistic value of {realisticIncomingBytesPerMinute}.");
                    return false;
                }
            }
            else if (metricName == "OutgoingBytes")
            {
                var realisticOutgoingBytesPerSecond = Math.Max(currentCapacity - 1, 1) * 2_000_000 * 60; // Ensure at least 1 TU margin and convert to per minute
                if (currentBytesPerMinuteUpperBound < realisticOutgoingBytesPerSecond)
                {
                    Console.WriteLine($"Namespace has {currentBytesPerMinuteUpperBound} outgoing bytes, which is lower than the realistic value of {realisticOutgoingBytesPerSecond}.");
                    return false;
                }
            }
        }

        return true;
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
