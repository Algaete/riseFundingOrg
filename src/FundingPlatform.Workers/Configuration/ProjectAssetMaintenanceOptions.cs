namespace FundingPlatform.Workers.Configuration;

/// <summary>
/// Independent cost interlock: enabling uploads must not silently opt into SQL timers.
/// An event-driven maintenance replacement is required before on-demand activation.
/// </summary>
public sealed class ProjectAssetMaintenanceOptions
{
    public const string SectionName = "ProjectAssetMaintenance";

    public bool AllowSqlPolling { get; set; }
}
