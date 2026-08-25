namespace FundingPlatform.Contracts.Semantics;

public sealed record CreateSemanticEvaluationRunRequest(
    string EvalSetVersion,
    string SemanticConfigurationVersion);

public sealed record SemanticEvaluationMetricsResponse(
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

public sealed record SemanticEvaluationRunSummaryResponse(
    Guid PublicId,
    byte Status,
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
    SemanticEvaluationMetricsResponse Metrics,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    string? LastErrorCode);

public sealed record SemanticEvaluationRunAcceptedResponse(
    SemanticEvaluationRunSummaryResponse Run,
    bool WasReplay,
    string StatusUrl);

public sealed record SemanticEvaluationRunPageResponse(
    IReadOnlyList<SemanticEvaluationRunSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record SemanticEvaluationRunDetailResponse(
    SemanticEvaluationRunSummaryResponse Run,
    int QueuedEmbeddingJobCount,
    int ProcessingEmbeddingJobCount,
    int SucceededEmbeddingJobCount,
    int RetryScheduledEmbeddingJobCount,
    int PermanentFailedEmbeddingJobCount,
    int SkippedStaleEmbeddingJobCount,
    int RejectedInputEmbeddingJobCount,
    string Disclaimer);

public sealed record SemanticEvaluationSplitReportResponse(
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

public sealed record SemanticEvaluationRunReportResponse(
    SemanticEvaluationRunSummaryResponse Run,
    IReadOnlyList<SemanticEvaluationSplitReportResponse> Splits,
    string Disclaimer);
