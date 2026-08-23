using System.Text.RegularExpressions;
using FundingPlatform.Application.SourceDocuments;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Configuration;

public sealed class ContentRetentionOptions
{
    public const string SectionName = "ContentRetention";
    public int BatchSize { get; set; } = 100;
    public int SourceDocumentBatchSize { get; set; } = 25;
    public int SourceDocumentLeaseSeconds { get; set; } = 900;
}

public sealed class ContentRetentionOptionsValidator : IValidateOptions<ContentRetentionOptions>
{
    public ValidateOptionsResult Validate(string? name, ContentRetentionOptions options) =>
        options.BatchSize is >= 1 and <= 500 &&
        options.SourceDocumentBatchSize is >= 1 and <= 100 &&
        options.SourceDocumentLeaseSeconds is >= 30 and <= 3_600
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                "ContentRetention batch/lease settings are outside their supported ranges.");
}

public sealed class DefenderEventGridOptions
{
    public const string SectionName = "DefenderEventGrid";

    public bool Enabled { get; set; }
    public string TenantId { get; set; } = string.Empty;
    public string Audience { get; set; } = string.Empty;
    public string AllowedCallerApplicationId { get; set; } = string.Empty;
    public string AllowedCallerObjectId { get; set; } = string.Empty;
    public string ExpectedTopicResourceId { get; set; } = string.Empty;
    public string ExpectedSubscriptionName { get; set; } = string.Empty;
    public string StorageAccountResourceId { get; set; } = string.Empty;
    public int PendingScanTimeoutMinutes { get; set; } = 240;
    public int WatchdogBatchSize { get; set; } = 25;

    public static bool IsValid(
        DefenderEventGridOptions options,
        string environmentName,
        string? blobServiceUri = null)
    {
        if (!options.Enabled)
        {
            return string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(environmentName, "Testing", StringComparison.OrdinalIgnoreCase);
        }

        return Guid.TryParse(options.TenantId, out var tenant) && tenant != Guid.Empty &&
               Guid.TryParse(options.AllowedCallerApplicationId, out var app) && app != Guid.Empty &&
               Guid.TryParse(options.AllowedCallerObjectId, out var principal) && principal != Guid.Empty &&
               Uri.TryCreate(options.Audience, UriKind.Absolute, out var audience) &&
               (audience.Scheme == "api" || audience.Scheme == Uri.UriSchemeHttps) &&
               options.Audience.Length <= 500 && SafeValue(options.Audience) &&
               string.IsNullOrEmpty(audience.Query) && string.IsNullOrEmpty(audience.Fragment) &&
               string.IsNullOrEmpty(audience.UserInfo) &&
               options.ExpectedTopicResourceId.Length <= 500 &&
               SafeValue(options.ExpectedTopicResourceId) &&
               Regex.IsMatch(
                   options.ExpectedTopicResourceId,
                   "^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/?#]+/providers/Microsoft\\.EventGrid/(?:topics|systemtopics)/[^/?#]+$",
                   RegexOptions.CultureInvariant | RegexOptions.IgnoreCase) &&
               options.StorageAccountResourceId.Length <= 500 &&
               SafeValue(options.StorageAccountResourceId) &&
               Regex.IsMatch(
                   options.StorageAccountResourceId,
                   "^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[a-z0-9]{3,24}$",
                   RegexOptions.CultureInvariant | RegexOptions.IgnoreCase) &&
               options.ExpectedSubscriptionName.Length is >= 1 and <= 64 &&
               !options.ExpectedSubscriptionName.Contains('/') &&
               !options.ExpectedSubscriptionName.Contains('\r') &&
               !options.ExpectedSubscriptionName.Contains('\n') &&
               !options.ExpectedSubscriptionName.Contains('\0') &&
               options.PendingScanTimeoutMinutes is >= 180 and <= 1_440 &&
               options.WatchdogBatchSize is >= 1 and <= 100 &&
               MatchesStorageAccount(options.StorageAccountResourceId, blobServiceUri);
    }

    private static bool SafeValue(string value) =>
        !value.Any(char.IsControl) &&
        !value.Contains('?') && !value.Contains('#');

    public DefenderEventGridPolicy ToPolicy(
        Uri blobServiceUri,
        string quarantineContainer,
        string trustedContainer,
        long maximumBlobBytes)
    {
        if (!MatchesStorageAccount(StorageAccountResourceId, blobServiceUri.AbsoluteUri))
        {
            throw new InvalidOperationException(
                "Defender Event Grid storage resource and Blob service URI must name the same account.");
        }

        return new DefenderEventGridPolicy(
            ExpectedTopicResourceId,
            ExpectedSubscriptionName,
            StorageAccountResourceId,
            blobServiceUri,
            quarantineContainer,
            trustedContainer,
            maximumBlobBytes,
            TimeSpan.FromMinutes(5));
    }

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
        var hostAccount = blobUri.Host[..blobUri.Host.IndexOf('.', StringComparison.Ordinal)];
        return account.Length is >= 3 and <= 24 &&
               string.Equals(account, hostAccount, StringComparison.OrdinalIgnoreCase);
    }
}
