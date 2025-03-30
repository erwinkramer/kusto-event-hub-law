public class EventHubNamespaceConfig
{
    /// <summary>
    /// Valid resource ID of the Event Hubs namespace
    /// </summary>
    public required string ResourceId { get; set; }

    /// <summary>
    /// Should be set to a realistic value depending on your lower bound workload
    /// </summary>
    public required int MinimumCapacity { get; set; }
}