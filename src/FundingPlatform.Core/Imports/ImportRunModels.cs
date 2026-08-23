namespace FundingPlatform.Core.Imports;

public enum ImportTriggerType : byte
{
    Manual = 0,
    Scheduled = 1,
    Retry = 2
}

public enum ImportRunStatus : byte
{
    Queued = 0,
    Running = 1,
    Completed = 2,
    Partial = 3,
    Failed = 4,
    Canceled = 5
}

public enum ImportRunItemStatus : byte
{
    Pending = 0,
    Processing = 1,
    Completed = 2,
    Failed = 3
}

public sealed record ImportRunAccepted(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    ImportRunStatus Status,
    DateTimeOffset CreatedAtUtc,
    bool WasReplay);

public sealed record ImportRunSummary(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    string ProviderCode,
    ImportTriggerType TriggerType,
    ImportRunStatus Status,
    string Keyword,
    int MaximumResults,
    int RetrievedCount,
    int CreatedCount,
    int UpdatedCount,
    int UnchangedCount,
    int StagedForReviewCount,
    int FailedCount,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    string? LastErrorCode);

public sealed record ImportRunPage(
    IReadOnlyList<ImportRunSummary> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record ImportRunItem(
    Guid ItemId,
    Guid? RawObservationId,
    Guid? OpportunityId,
    string ExternalId,
    ImportRunItemStatus Status,
    string? OutcomeCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    Guid? DuplicateCandidateId = null,
    byte? DuplicateCandidateStatus = null,
    byte? DuplicateMatchKind = null,
    decimal? DuplicateConfidence = null,
    Guid? SuggestedCanonicalOpportunityId = null,
    string? SuggestedCanonicalTitle = null,
    Guid? DuplicateDecisionId = null,
    byte? DuplicateDecision = null,
    byte[]? DuplicateCandidateRowVersion = null);

public sealed record ImportRunError(
    Guid ErrorId,
    Guid? ItemId,
    string Stage,
    string Code,
    string Message,
    bool IsRetryable,
    DateTimeOffset OccurredAtUtc);

public sealed record ImportRunDetail(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    string ProviderCode,
    ImportTriggerType TriggerType,
    ImportRunStatus Status,
    string Keyword,
    int MaximumResults,
    int RetrievedCount,
    int CreatedCount,
    int UpdatedCount,
    int UnchangedCount,
    int StagedForReviewCount,
    int FailedCount,
    short AttemptCount,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    string? LastErrorCode,
    IReadOnlyList<ImportRunItem> Items,
    IReadOnlyList<ImportRunError> Errors);

public sealed record ImportRunClaim(
    Guid RunId,
    int FundingSourceId,
    string ProviderCode,
    string Keyword,
    int MaximumResults,
    int RetrievedCount,
    short AttemptCount,
    Guid LeaseId,
    int RequestRateLimitPerMinute,
    int MaximumResponseBytes,
    short ContentRetentionDays,
    int AcquisitionPolicyVersion,
    byte[] AcquisitionPolicyFingerprint);

public sealed record ImportRunQueueMessage(Guid RunId, int Version = 1);

public sealed record ImportOutboxMessage(
    Guid MessageId,
    string MessageType,
    string PayloadJson,
    short AttemptCount);

public sealed record ScheduledImportRun(
    Guid RunId,
    int FundingSourceId,
    string ProviderCode);

public sealed record PendingImportRunItem(
    Guid ItemId,
    Guid RawObservationId,
    string ExternalId,
    short SnapshotVersion,
    string SnapshotJson,
    byte[] SnapshotHash);
