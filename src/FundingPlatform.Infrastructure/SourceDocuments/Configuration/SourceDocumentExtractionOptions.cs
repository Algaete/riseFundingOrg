using FundingPlatform.Application.SourceDocuments;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.SourceDocuments.Configuration;

public sealed class SourceDocumentExtractionOptions
{
    public const string SectionName = "DocumentExtraction";

    public long MaximumBytes { get; set; } = 10_485_760;
    public int MaximumPages { get; set; } = 250;
    public int MaximumCharacters { get; set; } = 500_000;
    public int MaximumUtf8Bytes { get; set; } = 2_097_152;
    public int MaximumStackDepth { get; set; } = 64;
    public int TimeoutSeconds { get; set; } = 120;
    public int LeaseSeconds { get; set; } = 300;
    public int WatchdogBatchSize { get; set; } = 25;

    public SourceDocumentExtractionPolicy ToPolicy() => new(
        MaximumBytes,
        MaximumPages,
        MaximumCharacters,
        MaximumUtf8Bytes,
        MaximumStackDepth,
        TimeSpan.FromSeconds(TimeoutSeconds),
        TimeSpan.FromSeconds(LeaseSeconds),
        "fundingplatform-pdf-text",
        "1-pdfpig-0.1.15",
        SourceDocumentExtractionSettings.ComputeHash(
            "fundingplatform-pdf-text", "1-pdfpig-0.1.15", MaximumCharacters,
            MaximumPages, MaximumUtf8Bytes, MaximumStackDepth, MaximumBytes));
}

public sealed class SourceDocumentExtractionOptionsValidator :
    IValidateOptions<SourceDocumentExtractionOptions>
{
    public ValidateOptionsResult Validate(string? name, SourceDocumentExtractionOptions options) =>
        options.MaximumBytes is >= 1_024 and <= 26_214_400 &&
        options.MaximumPages is >= 1 and <= 250 &&
        options.MaximumCharacters is >= 1_000 and <= 500_000 &&
        options.MaximumUtf8Bytes is >= 4_096 and <= 2_097_152 &&
        options.MaximumStackDepth is >= 16 and <= 128 &&
        options.TimeoutSeconds is >= 10 and <= 240 &&
        options.LeaseSeconds is >= 60 and <= 900 &&
        options.LeaseSeconds > options.TimeoutSeconds &&
        options.WatchdogBatchSize is >= 1 and <= 100
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                "DocumentExtraction limits are outside the safe MVP envelope or overlap the five-minute function boundary.");
}
