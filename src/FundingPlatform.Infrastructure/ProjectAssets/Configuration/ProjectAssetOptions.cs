using System.Text.RegularExpressions;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Infrastructure.ProjectAssets.Configuration;

public sealed class ProjectAssetOptions
{
    public const string SectionName = "ProjectAssets";

    public bool Enabled { get; set; }
    public string BlobServiceUri { get; set; } = string.Empty;
    public string IncomingContainer { get; set; } = "fp-project-incoming";
    public string QuarantineContainer { get; set; } = "fp-project-quarantine";
    public string TrustedContainer { get; set; } = "fp-project-trusted";
    public long MaxImageBytes { get; set; } = 10_485_760;
    public long MaxDocumentBytes { get; set; } = 26_214_400;
    public long MaxProjectBytes { get; set; } = 262_144_000;
    public int MaxImagePixels { get; set; } = 25_000_000;
    public int UploadTtlMinutes { get; set; } = 5;
    public int FinalizeLeaseSeconds { get; set; } = 120;
    public int ScanTimeoutSeconds { get; set; } = 300;
    public string ScanMode { get; set; } = "MicrosoftDefender";
    public string DevelopmentFakeResult { get; set; } = "Clean";

    public static bool IsValid(ProjectAssetOptions options, string environmentName)
    {
        if (!IsContainer(options.IncomingContainer) ||
            !IsContainer(options.QuarantineContainer) ||
            !IsContainer(options.TrustedContainer) ||
            options.IncomingContainer == options.QuarantineContainer ||
            options.IncomingContainer == options.TrustedContainer ||
            options.QuarantineContainer == options.TrustedContainer ||
            options.MaxImageBytes is < 1 or > 10_485_760 ||
            options.MaxDocumentBytes is < 1 or > 26_214_400 ||
            options.MaxProjectBytes != 262_144_000 ||
            options.MaxProjectBytes < options.MaxDocumentBytes ||
            options.MaxImagePixels is < 1 or > 25_000_000 ||
            options.UploadTtlMinutes is < 1 or > 5 ||
            options.FinalizeLeaseSeconds is < 30 or > 300 ||
            options.ScanTimeoutSeconds is < 5 or > 3_600)
            return false;

        if (options.Enabled &&
            (!Uri.TryCreate(options.BlobServiceUri, UriKind.Absolute, out var uri) ||
             !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)))
            return false;

        var developmentFake = string.Equals(
            options.ScanMode, "DevelopmentFake", StringComparison.OrdinalIgnoreCase);
        var defender = string.Equals(
            options.ScanMode, "MicrosoftDefender", StringComparison.OrdinalIgnoreCase);
        if (!developmentFake && !defender) return false;
        if (developmentFake &&
            !string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(environmentName, "Testing", StringComparison.OrdinalIgnoreCase))
            return false;

        return Enum.TryParse<ProjectAssetScanStatus>(
                   options.DevelopmentFakeResult, ignoreCase: true, out var fakeStatus) &&
               fakeStatus is ProjectAssetScanStatus.Clean or
                   ProjectAssetScanStatus.Malicious or
                   ProjectAssetScanStatus.Failed or
                   ProjectAssetScanStatus.TimedOut;
    }

    public ProjectAssetPolicy ToPolicy() => new(
        Enabled,
        Uri.TryCreate(BlobServiceUri, UriKind.Absolute, out var uri) ? uri : null,
        IncomingContainer,
        QuarantineContainer,
        TrustedContainer,
        MaxImageBytes,
        MaxDocumentBytes,
        MaxProjectBytes,
        MaxImagePixels,
        TimeSpan.FromMinutes(UploadTtlMinutes),
        TimeSpan.FromSeconds(FinalizeLeaseSeconds),
        TimeSpan.FromSeconds(ScanTimeoutSeconds),
        string.Equals(ScanMode, "DevelopmentFake", StringComparison.OrdinalIgnoreCase)
            ? ProjectAssetScanProvider.DevelopmentFake
            : ProjectAssetScanProvider.MicrosoftDefender);

    private static bool IsContainer(string value) =>
        !string.IsNullOrWhiteSpace(value) &&
        Regex.IsMatch(value, "^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$") &&
        !value.Contains("--", StringComparison.Ordinal);
}
