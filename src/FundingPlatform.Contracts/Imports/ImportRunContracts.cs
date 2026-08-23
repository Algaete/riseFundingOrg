namespace FundingPlatform.Contracts.Imports;

public sealed record CreateImportRunRequest(
    string Keyword,
    int MaximumResults);

public sealed record ImportRunAcceptedResponse(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    byte Status,
    DateTimeOffset CreatedAtUtc,
    bool WasReplay,
    string StatusUrl);

public sealed record ImportRunListResponse(
    IReadOnlyList<ImportRunSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record ImportRunSummaryResponse(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    string ProviderCode,
    byte TriggerType,
    byte Status,
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

public sealed record ImportRunDetailResponse(
    Guid RunId,
    int FundingSourceId,
    string SourceName,
    string ProviderCode,
    byte TriggerType,
    byte Status,
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
    IReadOnlyList<ImportRunItemResponse> Items,
    IReadOnlyList<ImportRunErrorResponse> Errors);

public sealed record ImportRunItemResponse(
    Guid ItemId,
    Guid? RawObservationId,
    Guid? OpportunityId,
    string ExternalId,
    byte Status,
    string? OutcomeCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    Guid? DuplicateCandidateId,
    byte? DuplicateCandidateStatus,
    byte? DuplicateMatchKind,
    decimal? DuplicateConfidence,
    Guid? SuggestedCanonicalOpportunityId,
    string? SuggestedCanonicalTitle,
    Guid? DuplicateDecisionId,
    byte? DuplicateDecision,
    string? DuplicateCandidateETag);

public sealed record ImportRunErrorResponse(
    Guid ErrorId,
    Guid? ItemId,
    string Stage,
    string Code,
    string Message,
    bool IsRetryable,
    DateTimeOffset OccurredAtUtc);
