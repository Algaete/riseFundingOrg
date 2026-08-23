using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed record SourceDocumentExtractionPolicy(
    long MaximumBytes,
    int MaximumPages,
    int MaximumCharacters,
    int MaximumUtf8Bytes,
    int MaximumStackDepth,
    TimeSpan Timeout,
    TimeSpan LeaseDuration,
    string ParserCode,
    string ParserVersion,
    byte[] ParserSettingsHash);

public static class SourceDocumentExtractionSettings
{
    public static byte[] ComputeHash(
        string parserCode,
        string parserVersion,
        int maximumCharacters,
        int maximumPages,
        int maximumUtf8Bytes,
        int maximumStackDepth,
        long maximumBytes) => SHA256.HashData(Encoding.UTF8.GetBytes(
            $"{parserCode}|{parserVersion}|{maximumCharacters}|{maximumPages}|{maximumUtf8Bytes}|{maximumStackDepth}|{maximumBytes}"));
}

public sealed record SourceDocumentTextExtraction(
    string Text,
    byte[] SourceContentHash,
    byte[] ExtractedTextHash,
    int PageCount,
    int CharacterCount,
    bool WasTruncated)
{
    public bool CompletedWithErrors => WasTruncated || CharacterCount == 0;
}

public sealed record SourceDocumentExtractionAdminView(
    Guid SourceDocumentId,
    Guid? JobId,
    SourceDocumentExtractionStatus Status,
    string? ParserCode,
    string? ParserVersion,
    short AttemptCount,
    short MaxAttempts,
    int? PageCount,
    int? CharacterCount,
    bool? CompletedWithErrors,
    int EvidenceCount,
    int ErrorCount,
    string? TextPreview,
    string? LastErrorCode,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset? UpdatedAtUtc,
    byte[]? JobRowVersion,
    byte[] DocumentRowVersion,
    bool IsContentRedacted = false,
    DateTimeOffset? RedactedAtUtc = null,
    bool IsSecurityRevoked = false);

public sealed record SourceDocumentExtractionEvidence(
    Guid EvidenceId,
    short Ordinal,
    int? PageNumber,
    int StartOffset,
    int CharacterLength,
    string Excerpt,
    DateTimeOffset CreatedAtUtc);

public sealed record SourceDocumentExtractionEvidencePage(
    IReadOnlyList<SourceDocumentExtractionEvidence> Items,
    int Page,
    int PageSize,
    long TotalCount);

public sealed record SourceDocumentExtractionReadResult(
    SourceDocumentExtractionOutcome Outcome,
    string Code,
    SourceDocumentExtractionAdminView? Value = null);

public sealed record SourceDocumentExtractionEvidenceReadResult(
    SourceDocumentExtractionOutcome Outcome,
    string Code,
    SourceDocumentExtractionEvidencePage? Value = null);

public sealed record SourceDocumentExtractionStartMutation(
    bool Succeeded,
    string Code,
    Guid SourceDocumentId,
    Guid? JobId,
    SourceDocumentExtractionStatus? Status,
    short? AttemptCount,
    short? MaxAttempts,
    byte[]? RowVersion,
    bool WasReplay);

public interface ISourceDocumentTextExtractor
{
    Task<SourceDocumentTextExtraction> ExtractPdfAsync(
        SourceBlobRead source,
        SourceDocumentExtractionPolicy policy,
        CancellationToken cancellationToken);
}

/// <summary>
/// Narrow capability exposed to the isolated extraction host. It cannot create
/// upload grants, copy, promote, or delete source-document blobs.
/// </summary>
public interface ISourceDocumentExtractionBlobReader
{
    Task<SourceBlobRead> OpenTrustedReadAsync(
        ProtectedBlobLocation source,
        string expectedETag,
        CancellationToken cancellationToken);
}

public interface ISourceDocumentExtractionRepository
{
    Task<SourceDocumentExtractionStartMutation> StartAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        string correlationId,
        SourceDocumentExtractionPolicy policy,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ScheduledSourceDocumentExtraction>> RequeueStrandedAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken);

    Task<SourceDocumentExtractionClaim?> ClaimAsync(
        Guid jobId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken);

    Task<bool> RenewLeaseAsync(
        Guid jobId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken);

    Task RecordEvidenceAsync(
        Guid jobId,
        Guid leaseId,
        short ordinal,
        int? pageNumber,
        int startOffset,
        string excerpt,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task CompleteAsync(
        Guid jobId,
        Guid leaseId,
        string extractedText,
        byte[] extractedTextHash,
        int pageCount,
        int characterCount,
        bool wasTruncated,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task FailAsync(
        Guid jobId,
        Guid leaseId,
        string errorCode,
        string safeMessage,
        bool retryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentExtractionAdminView?> GetLatestAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        CancellationToken cancellationToken);

    Task<SourceDocumentExtractionEvidencePage> ListEvidenceAsync(
        Guid adminUserId,
        Guid jobId,
        int page,
        int pageSize,
        CancellationToken cancellationToken);
}

public interface ISourceDocumentExtractionQueuePublisher
{
    Task PublishAsync(
        SourceDocumentExtractionQueueMessage message,
        CancellationToken cancellationToken);
}

public sealed class SourceDocumentExtractionDataException(
    string operation,
    int databaseErrorNumber,
    Exception? innerException = null) : Exception(
        $"Source-document extraction data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}

public sealed class SourceDocumentExtractionLeaseLostException(Guid jobId) : Exception(
    $"The source-document extraction lease for job '{jobId:D}' was lost.")
{
    public Guid JobId { get; } = jobId;
}

public enum SourceDocumentExtractionOutcome
{
    Success,
    Accepted,
    Invalid,
    NotFound,
    Forbidden,
    PreconditionFailed,
    Conflict,
    Unavailable
}

public sealed record SourceDocumentExtractionResult(
    SourceDocumentExtractionOutcome Outcome,
    string Code,
    Guid SourceDocumentId,
    Guid? JobId = null,
    SourceDocumentExtractionStatus? Status = null,
    short? AttemptCount = null,
    short? MaxAttempts = null,
    byte[]? RowVersion = null,
    bool WasReplay = false,
    IReadOnlyDictionary<string, string[]>? Errors = null);
