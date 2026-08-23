namespace FundingPlatform.Contracts.SourceDocuments;

public sealed record CreateSourceDocumentUploadIntentRequest(
    int FundingSourceId,
    string FileName,
    string MimeType,
    long ContentLength);

public sealed record CompleteSourceDocumentUploadIntentRequest(string CompletionToken);

public sealed record SourceDocumentUploadIntentCreatedResponse(
    Guid IntentId,
    byte Status,
    DateTimeOffset ExpiresAtUtc,
    long MaxContentLength,
    string UploadMethod,
    Uri UploadUrl,
    IReadOnlyDictionary<string, string> RequiredHeaders,
    string CompletionToken,
    string StatusUrl,
    string ETag,
    string SecurityNotice);

public sealed record SourceDocumentOperationResponse(
    Guid? IntentId,
    byte? IntentStatus,
    Guid? SourceDocumentId,
    byte? StorageStatus,
    byte? ScanStatus,
    byte? ScanProvider,
    short? ScanAttemptCount,
    string ETag,
    bool WasReplay,
    bool IsTerminal,
    bool IsDevelopmentScan);

public sealed record SourceDocumentUploadIntentResponse(
    Guid IntentId,
    int FundingSourceId,
    string FundingSourceName,
    string FileName,
    string MimeType,
    long ExpectedContentLength,
    long MaxContentLength,
    byte Status,
    DateTimeOffset ExpiresAtUtc,
    Guid? SourceDocumentId,
    byte? StorageStatus,
    byte? ScanStatus,
    byte? ScanProvider,
    string? ScanResultCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    bool IsDevelopmentScan);

public sealed record SourceDocumentResponse(
    Guid SourceDocumentId,
    int FundingSourceId,
    string FundingSourceName,
    string FileName,
    string MimeType,
    long ContentLength,
    byte StorageStatus,
    byte ScanStatus,
    byte ScanProvider,
    bool IsProductionScan,
    short ScanAttemptCount,
    string? ScanResultCode,
    DateTimeOffset? ScanStartedAtUtc,
    DateTimeOffset? ScanCompletedAtUtc,
    byte ExtractionStatus,
    Guid UploadedByUserId,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    SourceDocumentExtractionSummaryResponse? Extraction = null,
    byte ContentRetentionStatus = 0,
    DateTimeOffset? RetentionUntilUtc = null,
    DateTimeOffset? ContentDeletionRequestedAtUtc = null,
    string? ContentRetentionLastErrorCode = null);

public sealed record SourceDocumentExtractionSummaryResponse(
    Guid JobId,
    byte Status,
    short AttemptCount,
    short MaxAttempts,
    int? PageCount,
    int? CharacterCount,
    bool? CompletedWithErrors,
    int EvidenceCount,
    int ErrorCount,
    string? ResultCode,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? UpdatedAtUtc,
    bool IsContentRedacted,
    DateTimeOffset? RedactedAtUtc,
    bool IsSecurityRevoked,
    string ETag);

public sealed record SourceDocumentExtractionStartedResponse(
    Guid SourceDocumentId,
    Guid JobId,
    byte Status,
    short? AttemptCount,
    short? MaxAttempts,
    string StatusUrl,
    string ETag,
    bool WasReplay);

public sealed record SourceDocumentExtractionResultResponse(
    Guid SourceDocumentId,
    Guid? JobId,
    byte Status,
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
    string? ResultCode,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset? UpdatedAtUtc,
    bool IsContentRedacted,
    DateTimeOffset? RedactedAtUtc,
    bool IsSecurityRevoked,
    string ETag,
    string DocumentETag);

public sealed record SourceDocumentExtractionEvidenceResponse(
    Guid EvidenceId,
    short Ordinal,
    int? PageNumber,
    int StartOffset,
    int CharacterLength,
    string Excerpt,
    DateTimeOffset CreatedAtUtc);

public sealed record SourceDocumentExtractionEvidencePageResponse(
    IReadOnlyList<SourceDocumentExtractionEvidenceResponse> Items,
    int Page,
    int PageSize,
    long TotalCount);
