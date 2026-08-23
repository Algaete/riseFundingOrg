using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public enum SourceDocumentOutcome
{
    Success,
    Processing,
    ValidationFailed,
    NotFound,
    Forbidden,
    Expired,
    PreconditionFailed,
    Conflict,
    InvalidTransition,
    RetryLimitReached,
    Unavailable
}

public sealed record SourceDocumentMutation(
    bool Succeeded,
    string Code,
    Guid? IntentPublicId = null,
    SourceDocumentUploadIntentStatus? IntentStatus = null,
    Guid? SourceDocumentPublicId = null,
    SourceDocumentStorageStatus? StorageStatus = null,
    SourceDocumentScanStatus? ScanStatus = null,
    SourceDocumentScanProvider? ScanProvider = null,
    byte[]? RowVersion = null,
    bool WasReplay = false,
    DateTimeOffset? ExpiresAtUtc = null,
    ProtectedBlobLocation? RevokedTrustedLocation = null,
    string? RevokedTrustedETag = null);

public sealed record SourceDocumentRetryMutation(
    bool Succeeded,
    string Code,
    Guid SourceDocumentPublicId,
    SourceDocumentStorageStatus? StorageStatus,
    SourceDocumentScanStatus? ScanStatus,
    SourceDocumentScanProvider? ScanProvider,
    short? ScanAttemptCount,
    byte[]? RowVersion,
    bool WasReplay);

public sealed class SourceDocumentFinalizeWork
{
    public bool Succeeded { get; init; }
    public string Code { get; init; } = string.Empty;
    public Guid? IntentPublicId { get; init; }
    public int? FundingSourceId { get; init; }
    public string? OriginalFileName { get; init; }
    public ProtectedBlobLocation? IncomingLocation { get; init; }
    public ProtectedBlobLocation? QuarantineLocation { get; init; }
    public string? DeclaredMimeType { get; init; }
    public string? VerifiedMimeType { get; init; }
    public long? ExpectedContentLength { get; init; }
    public long? MaxContentLength { get; init; }
    public long? ActualContentLength { get; init; }
    public byte[]? ContentHash { get; init; }
    public string? BlobETag { get; init; }
    public string? BlobVersionId { get; init; }
    public SourceDocumentUploadIntentStatus? IntentStatus { get; init; }
    public DateTimeOffset? ExpiresAtUtc { get; init; }
    public Guid? SourceDocumentPublicId { get; init; }
    public SourceDocumentStorageStatus? StorageStatus { get; init; }
    public SourceDocumentScanStatus? ScanStatus { get; init; }
    public SourceDocumentScanProvider? ScanProvider { get; init; }
    public Guid? FinalizeLeaseId { get; init; }
    public byte[]? RowVersion { get; init; }
    public bool WasReplay { get; init; }

    public override string ToString() => "[protected source-document finalization work]";
}

public sealed class SourceDocumentScanWork
{
    public bool Succeeded { get; init; }
    public string Code { get; init; } = string.Empty;
    public Guid SourceDocumentPublicId { get; init; }
    public ProtectedBlobLocation? QuarantineLocation { get; init; }
    public long? ContentLength { get; init; }
    public byte[]? ContentHash { get; init; }
    public string? BlobETag { get; init; }
    public string? BlobVersionId { get; init; }
    public SourceDocumentScanProvider? ScanProvider { get; init; }
    public short? ScanAttemptCount { get; init; }
    public DateTimeOffset? ScanStartedAtUtc { get; init; }
    public DateTimeOffset? CreatedAtUtc { get; init; }
    public byte[]? RowVersion { get; init; }

    public override string ToString() => "[protected source-document scan work]";
}

public sealed class SourceDocumentCreateResult
{
    public SourceDocumentOutcome Outcome { get; init; }
    public string Code { get; init; } = string.Empty;
    public Guid? IntentPublicId { get; init; }
    public SourceDocumentUploadIntentStatus? Status { get; init; }
    public DateTimeOffset? ExpiresAtUtc { get; init; }
    public long MaxContentLength { get; init; }
    public Uri? UploadUri { get; init; }
    public IReadOnlyDictionary<string, string>? RequiredHeaders { get; init; }
    public string? CompletionToken { get; init; }
    public byte[]? RowVersion { get; init; }
    public IReadOnlyDictionary<string, string[]>? Errors { get; init; }

    public override string ToString() => "[redacted source-document create result]";
}

public sealed record SourceDocumentOperationResult(
    SourceDocumentOutcome Outcome,
    string Code,
    Guid? IntentPublicId = null,
    SourceDocumentUploadIntentStatus? IntentStatus = null,
    Guid? SourceDocumentPublicId = null,
    SourceDocumentStorageStatus? StorageStatus = null,
    SourceDocumentScanStatus? ScanStatus = null,
    SourceDocumentScanProvider? ScanProvider = null,
    short? ScanAttemptCount = null,
    byte[]? RowVersion = null,
    bool WasReplay = false,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record SourceDocumentQueryResult<T>(SourceDocumentOutcome Outcome, T? Value = default);

public sealed class SourceDocumentDataException(
    string operation,
    int databaseErrorNumber) : Exception(
        $"Source-document data operation '{operation}' failed with database error {databaseErrorNumber}.")
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}

public sealed class SourceDocumentStorageException(
    string operation,
    string code,
    int? status = null) : Exception(
        $"Source-document storage operation '{operation}' failed with code '{code}'.")
{
    public string Operation { get; } = operation;
    public string Code { get; } = code;
    public int? Status { get; } = status;
}
