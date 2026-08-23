namespace FundingPlatform.Core.SourceDocuments;

public sealed record SourceDocumentExtractionQueueMessage(
    Guid JobId,
    int Version = 1);

public sealed record ScheduledSourceDocumentExtraction(
    Guid JobId,
    Guid SourceDocumentId);

public sealed record SourceDocumentExtractionClaim(
    Guid JobId,
    Guid SourceDocumentId,
    Guid LeaseId,
    ProtectedSourceDocumentLocation TrustedLocation,
    string TrustedETag,
    byte[] ContentHash,
    long ContentLength,
    short AttemptCount,
    short MaxAttempts,
    string ParserCode,
    string ParserVersion,
    byte[] ParserSettingsHash,
    int MaximumCharacters,
    int MaximumPages,
    int MaximumUtf8Bytes,
    int MaximumStackDepth,
    long MaximumBytes);

/// <summary>
/// The location deliberately redacts its value from diagnostics.
/// Infrastructure maps it to the storage-specific protected location type.
/// </summary>
public sealed record ProtectedSourceDocumentLocation(string Container, string ObjectName)
{
    public override string ToString() => "[protected source-document location]";
}
