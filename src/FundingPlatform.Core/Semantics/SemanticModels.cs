namespace FundingPlatform.Core.Semantics;

public enum SemanticSubjectType : byte
{
    Project = 0,
    FundingOpportunity = 1
}

public enum SemanticEvaluationRunStatus : byte
{
    Queued = 0,
    Processing = 1,
    Completed = 2,
    RetryScheduled = 3,
    PermanentFailed = 4
}

public enum SemanticJobStatus : byte
{
    Queued = 0,
    Processing = 1,
    Succeeded = 2,
    RetryScheduled = 3,
    PermanentFailed = 4,
    SkippedStale = 5
}

public enum SemanticProviderCallAccounting : byte
{
    NotInvoked = 0,
    ChargeUncertain = 1
}

public enum AiProviderRetentionMode : byte
{
    Default = 0,
    ModifiedAbuseMonitoring = 1,
    ZeroDataRetention = 2
}

public sealed record AiProviderGovernanceContext(
    Guid PolicyPublicId,
    string PolicyVersion,
    byte[] PolicyFingerprint,
    byte Capability,
    string EndpointOrigin,
    AiProviderRetentionMode RetentionMode,
    short MaximumProviderRetentionDays,
    string DataResidencyCode,
    decimal InputTokenCostUsdPerMillion,
    decimal OutputTokenCostUsdPerMillion,
    DateTimeOffset ApprovedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    bool ExternalProcessingAllowed);

public sealed record SemanticEmbeddingJobLease(
    Guid JobPublicId,
    Guid LeaseId,
    Guid BudgetReservationPublicId,
    SemanticSubjectType SubjectType,
    Guid SubjectPublicId,
    int SubjectVersion,
    string SemanticConfigurationVersion,
    byte[] SemanticConfigurationFingerprint,
    string ProviderCode,
    string ModelCode,
    int Dimensions,
    string PurposeCode,
    string TemplateVersion,
    string NormalizationVersion,
    short MaximumInputUtf8Bytes,
    byte MaximumBatchSize,
    byte MaximumAttempts,
    decimal MaximumCostUsdPerEmbedding,
    byte[] InputContentHash,
    short AttemptCount);

public sealed record SemanticEmbeddingInput(
    Guid JobPublicId,
    Guid LeaseId,
    SemanticSubjectType SubjectType,
    Guid SubjectPublicId,
    int SubjectVersion,
    string PurposeCode,
    string CanonicalText,
    byte[] InputContentHash,
    AiProviderGovernanceContext? ProviderGovernance);

public sealed record SemanticEmbeddingGeneration(
    string ProviderCode,
    string ModelCode,
    string TemplateVersion,
    int Dimensions,
    float[] Vector,
    int? InputTokens,
    int? OutputTokens,
    decimal EstimatedCostUsd,
    byte[]? ProviderRequestIdHash,
    int LatencyMilliseconds);

public sealed record SemanticShadowEvaluationRunLease(
    Guid RunPublicId,
    Guid LeaseId,
    string SemanticConfigurationVersion,
    byte[] SemanticConfigurationFingerprint,
    string ProviderCode,
    string ModelCode,
    string PurposeCode,
    string NormalizationVersion,
    string ProjectTemplateVersion,
    string OpportunityTemplateVersion,
    string CalibrationVersion,
    byte DistanceMetric,
    byte MaximumAttempts,
    int Dimensions,
    int PairCount,
    short AttemptCount);

public sealed record SemanticShadowEvaluationWorkState(
    Guid RunPublicId,
    Guid LeaseId,
    int PairCount,
    int ReadyPairCount,
    int PendingEmbeddingJobCount,
    int PermanentFailedEmbeddingJobCount);

public sealed record SemanticProcessingBatchResult(
    int ClaimedCount,
    int CompletedCount,
    int FailedCount,
    int DeferredCount = 0,
    int SkippedCount = 0);

public sealed record SemanticEvaluationMetrics(
    decimal? CoveragePercentage,
    decimal? ProviderSuccessPercentage,
    decimal? RecallAt10,
    decimal? NormalizedDiscountedCumulativeGainAt10,
    decimal? BaselineNormalizedDiscountedCumulativeGainAt10,
    decimal? NormalizedDiscountedCumulativeGainDelta,
    decimal? MeanReciprocalRankAt10,
    decimal? MeanRankDelta,
    decimal? TotalEstimatedCostUsd,
    int? LatencyP95Milliseconds,
    int? HardGatePromotionCount,
    bool? MeetsPromotionGate);

public sealed record SemanticEvaluationRunSummary(
    Guid PublicId,
    SemanticEvaluationRunStatus Status,
    string EvaluationSetVersion,
    string SemanticConfigurationVersion,
    string ProviderCode,
    string ModelCode,
    int Dimensions,
    string PurposeCode,
    string NormalizationVersion,
    int ProjectCount,
    int OpportunityCount,
    int PairCount,
    int PrimaryCohortCount,
    int EvaluatedCount,
    int LabelledCount,
    SemanticEvaluationMetrics Metrics,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    string? LastErrorCode);

public sealed record SemanticEvaluationRunDetail(
    SemanticEvaluationRunSummary Run,
    int QueuedEmbeddingJobCount,
    int ProcessingEmbeddingJobCount,
    int SucceededEmbeddingJobCount,
    int RetryScheduledEmbeddingJobCount,
    int PermanentFailedEmbeddingJobCount,
    int SkippedStaleEmbeddingJobCount,
    int RejectedInputEmbeddingJobCount);

public sealed record SemanticEvaluationSplitReport(
    byte DatasetSplit,
    long PairCount,
    long EvaluatedCount,
    long LabelledCount,
    long RelevantLabelCount,
    decimal CoveragePercentage,
    decimal? RecallAt10,
    decimal? NormalizedDiscountedCumulativeGainAt10,
    decimal? BaselineNormalizedDiscountedCumulativeGainAt10,
    decimal? NormalizedDiscountedCumulativeGainDelta,
    decimal? MeanReciprocalRankAt10,
    decimal? MeanRankDelta);

public sealed record SemanticEvaluationRunReport(
    SemanticEvaluationRunSummary Run,
    IReadOnlyList<SemanticEvaluationSplitReport> Splits);

public sealed record SemanticEvaluationRunPage(
    IReadOnlyList<SemanticEvaluationRunSummary> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record SemanticEvaluationRunMutation(
    bool Succeeded,
    string Code,
    SemanticEvaluationRunSummary? Run,
    bool WasReplay);

public enum SemanticEvaluationOutcome
{
    Success,
    Invalid,
    Forbidden,
    NotFound,
    Conflict,
    Unavailable
}

public sealed record SemanticEvaluationResult<T>(
    SemanticEvaluationOutcome Outcome,
    T? Value = default,
    string? Code = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);
