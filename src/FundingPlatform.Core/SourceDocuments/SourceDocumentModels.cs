namespace FundingPlatform.Core.SourceDocuments;

public enum SourceDocumentUploadIntentStatus : byte
{
    Pending = 0,
    Finalizing = 1,
    Completed = 2,
    Expired = 3,
    Rejected = 4
}

public enum SourceDocumentStorageStatus : byte
{
    AwaitingQuarantine = 0,
    Quarantined = 1,
    Trusted = 2,
    Failed = 3
}

public enum SourceDocumentScanStatus : byte
{
    Pending = 0,
    Clean = 1,
    Malicious = 2,
    Failed = 3,
    TimedOut = 4
}

public enum SourceDocumentScanProvider : byte
{
    DevelopmentFake = 0,
    MicrosoftDefender = 1
}

public enum SourceDocumentExtractionStatus : byte
{
    NotStarted = 0,
    Queued = 1,
    Running = 2,
    Completed = 3,
    CompletedWithErrors = 4,
    Failed = 5,
    Canceled = 6
}

public enum SourceDocumentContentRetentionStatus : byte
{
    Active = 0,
    DeletionInProgress = 1,
    DeletionRequested = 2,
    Failed = 3
}

public sealed record SourceDocumentExtractionSummary(
    Guid JobPublicId,
    SourceDocumentExtractionStatus Status,
    short AttemptCount,
    short MaxAttempts,
    int? PageCount,
    int? CharacterCount,
    string? ResultCode,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record SourceDocumentUploadIntent(
    Guid IntentPublicId,
    int FundingSourceId,
    string FundingSourceName,
    string OriginalFileName,
    string DeclaredMimeType,
    long ExpectedContentLength,
    long MaxContentLength,
    SourceDocumentUploadIntentStatus Status,
    DateTimeOffset ExpiresAtUtc,
    Guid? SourceDocumentPublicId,
    SourceDocumentStorageStatus? StorageStatus,
    SourceDocumentScanStatus? ScanStatus,
    SourceDocumentScanProvider? ScanProvider,
    string? ScanResultCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record SourceDocument(
    Guid SourceDocumentPublicId,
    int FundingSourceId,
    string FundingSourceName,
    string OriginalFileName,
    string MimeType,
    long ContentLength,
    SourceDocumentStorageStatus StorageStatus,
    SourceDocumentScanStatus ScanStatus,
    SourceDocumentScanProvider ScanProvider,
    bool IsProductionScan,
    short ScanAttemptCount,
    string? ScanResultCode,
    DateTimeOffset? ScanStartedAtUtc,
    DateTimeOffset? ScanCompletedAtUtc,
    byte ExtractionStatus,
    Guid UploadedByUserPublicId,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion,
    SourceDocumentExtractionSummary? Extraction = null,
    SourceDocumentContentRetentionStatus ContentRetentionStatus =
        SourceDocumentContentRetentionStatus.Active,
    DateTimeOffset? RetentionUntilUtc = null,
    DateTimeOffset? ContentDeletionRequestedAtUtc = null,
    string? ContentRetentionLastErrorCode = null);
