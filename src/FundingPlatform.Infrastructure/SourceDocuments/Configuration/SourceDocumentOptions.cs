using System.Text.RegularExpressions;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Infrastructure.SourceDocuments.Configuration;

public sealed class SourceDocumentOptions
{
    public const string SectionName = "SourceDocuments";

    public string BlobServiceUri { get; set; } = string.Empty;
    public string IncomingContainer { get; set; } = "fp-source-incoming";
    public string QuarantineContainer { get; set; } = "fp-source-quarantine";
    public string TrustedContainer { get; set; } = "fp-source-trusted";
    public long MaxBytes { get; set; } = 26_214_400;
    public int UploadTtlMinutes { get; set; } = 5;
    public int FinalizeLeaseSeconds { get; set; } = 120;
    public int ScanTimeoutSeconds { get; set; } = 300;
    public string ScanMode { get; set; } = "MicrosoftDefender";
    public string DevelopmentFakeResult { get; set; } = "Clean";

    public static bool IsValid(SourceDocumentOptions options, string environmentName)
    {
        if (!Uri.TryCreate(options.BlobServiceUri, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !IsContainer(options.IncomingContainer) ||
            !IsContainer(options.QuarantineContainer) ||
            !IsContainer(options.TrustedContainer) ||
            options.IncomingContainer == options.QuarantineContainer ||
            options.IncomingContainer == options.TrustedContainer ||
            options.QuarantineContainer == options.TrustedContainer ||
            options.MaxBytes is < 1 or > 26_214_400 ||
            options.UploadTtlMinutes is < 1 or > 15 ||
            options.FinalizeLeaseSeconds is < 30 or > 300 ||
            options.ScanTimeoutSeconds is < 5 or > 3_600)
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
        return Enum.TryParse<SourceDocumentScanStatus>(
                   options.DevelopmentFakeResult, ignoreCase: true, out var fakeStatus) &&
               fakeStatus is SourceDocumentScanStatus.Clean or
                   SourceDocumentScanStatus.Malicious or
                   SourceDocumentScanStatus.Failed or
                   SourceDocumentScanStatus.TimedOut;
    }

    public SourceDocumentPolicy ToPolicy() => new(
        new Uri(BlobServiceUri, UriKind.Absolute),
        IncomingContainer,
        QuarantineContainer,
        TrustedContainer,
        MaxBytes,
        TimeSpan.FromMinutes(UploadTtlMinutes),
        TimeSpan.FromSeconds(FinalizeLeaseSeconds),
        TimeSpan.FromSeconds(ScanTimeoutSeconds),
        string.Equals(ScanMode, "DevelopmentFake", StringComparison.OrdinalIgnoreCase)
            ? SourceDocumentScanProvider.DevelopmentFake
            : SourceDocumentScanProvider.MicrosoftDefender);

    private static bool IsContainer(string value) =>
        !string.IsNullOrWhiteSpace(value) &&
        Regex.IsMatch(value, "^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$") &&
        !value.Contains("--", StringComparison.Ordinal);
}
