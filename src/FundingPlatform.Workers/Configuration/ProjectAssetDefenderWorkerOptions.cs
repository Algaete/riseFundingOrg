using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;

namespace FundingPlatform.Workers.Configuration;

public sealed class ProjectAssetDefenderWorkerOptions
{
    public const string SectionName = "ProjectAssetDefenderEventGrid";
    public const string EventGridFunctionDisabledSetting =
        "AzureWebJobs.ProjectAssetDefenderEventGridFunction.Disabled";
    public const string ScanWatchdogFunctionDisabledSetting =
        "AzureWebJobs.ProjectAssetDefenderScanWatchdogFunction.Disabled";

    public bool Enabled { get; set; }
    public string ExpectedSubscriptionName { get; set; } = string.Empty;
    public int PendingScanTimeoutMinutes { get; set; } = 240;
    public int WatchdogBatchSize { get; set; } = 25;

    public static bool IsValid(
        ProjectAssetDefenderWorkerOptions options,
        string environmentName,
        DefenderEventGridOptions sharedDefender,
        ProjectAssetOptions projectAssets,
        string? eventGridFunctionDisabled = null,
        string? scanWatchdogFunctionDisabled = null,
        bool imageSanitizationAvailable = false)
    {
        if (!options.Enabled)
        {
            return IsLocal(environmentName) ||
                   (IsExplicitlyDisabled(eventGridFunctionDisabled) &&
                    IsExplicitlyDisabled(scanWatchdogFunctionDisabled));
        }

        return imageSanitizationAvailable &&
               IsExplicitlyEnabled(eventGridFunctionDisabled) &&
               IsExplicitlyEnabled(scanWatchdogFunctionDisabled) &&
               sharedDefender.Enabled &&
               projectAssets.Enabled &&
               string.Equals(projectAssets.ScanMode, "MicrosoftDefender",
                   StringComparison.OrdinalIgnoreCase) &&
               IsSafeSubscriptionName(options.ExpectedSubscriptionName) &&
               !string.Equals(options.ExpectedSubscriptionName,
                   sharedDefender.ExpectedSubscriptionName, StringComparison.OrdinalIgnoreCase) &&
               options.PendingScanTimeoutMinutes is >= 180 and <= 1_440 &&
               options.WatchdogBatchSize is >= 1 and <= 100 &&
               MatchesStorageAccount(
                   sharedDefender.StorageAccountResourceId,
                   projectAssets.BlobServiceUri);
    }

    public ProjectAssetDefenderEventGridPolicy ToPolicy(
        DefenderEventGridOptions sharedDefender,
        ProjectAssetOptions projectAssets)
    {
        if (!MatchesStorageAccount(
                sharedDefender.StorageAccountResourceId, projectAssets.BlobServiceUri))
        {
            throw new InvalidOperationException(
                "Project-asset Defender storage and Blob service URI must name the same account.");
        }

        return new ProjectAssetDefenderEventGridPolicy(
            sharedDefender.ExpectedTopicResourceId,
            ExpectedSubscriptionName,
            sharedDefender.StorageAccountResourceId,
            new Uri(projectAssets.BlobServiceUri, UriKind.Absolute),
            projectAssets.QuarantineContainer,
            projectAssets.TrustedContainer,
            projectAssets.MaxImageBytes,
            projectAssets.MaxDocumentBytes,
            projectAssets.MaxImagePixels,
            TimeSpan.FromMinutes(5));
    }

    private static bool IsLocal(string environmentName) =>
        string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(environmentName, "Testing", StringComparison.OrdinalIgnoreCase);

    private static bool IsExplicitlyDisabled(string? value) =>
        string.Equals(value, "true", StringComparison.Ordinal);

    private static bool IsExplicitlyEnabled(string? value) =>
        string.Equals(value, "false", StringComparison.Ordinal);

    private static bool IsSafeSubscriptionName(string value) =>
        value.Length is >= 1 and <= 64 &&
        !value.Any(character => char.IsControl(character) || character == '/');

    private static bool MatchesStorageAccount(string resourceId, string? blobServiceUri)
    {
        if (!Uri.TryCreate(blobServiceUri, UriKind.Absolute, out var blobUri) ||
            blobUri.Scheme != Uri.UriSchemeHttps || blobUri.Port != 443 ||
            !blobUri.Host.EndsWith(".blob.core.windows.net", StringComparison.OrdinalIgnoreCase))
            return false;
        const string segment = "/storageAccounts/";
        var index = resourceId.LastIndexOf(segment, StringComparison.OrdinalIgnoreCase);
        if (index < 0) return false;
        var account = resourceId[(index + segment.Length)..];
        var separator = blobUri.Host.IndexOf('.', StringComparison.Ordinal);
        return separator > 0 && account.Length is >= 3 and <= 24 &&
               string.Equals(account, blobUri.Host[..separator], StringComparison.OrdinalIgnoreCase);
    }
}
