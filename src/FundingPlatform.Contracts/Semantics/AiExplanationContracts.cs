namespace FundingPlatform.Contracts.Semantics;

public sealed record CreateAiExplanationRunRequest(
    Guid SourceSemanticEvaluationRunPublicId,
    string ExplanationConfigurationVersion);

public sealed record AiExplanationRunSummaryResponse(
    Guid PublicId,
    Guid SourceSemanticEvaluationRunPublicId,
    byte Status,
    string ExplanationConfigurationVersion,
    string ProviderCode,
    string ModelCode,
    int ItemCount,
    int CompletedCount,
    int FailedCount,
    decimal? TotalEstimatedCostUsd,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc);

public sealed record AiExplanationRunAcceptedResponse(
    AiExplanationRunSummaryResponse Run,
    bool WasReplay,
    string StatusUrl);

public sealed record AiExplanationResultResponse(
    int CaseOrdinal,
    byte Assessment,
    string Summary,
    string PrimaryReasonCode,
    IReadOnlyList<string> CitedRuleCodes,
    int InputTokens,
    int OutputTokens,
    decimal EstimatedCostUsd,
    int LatencyMilliseconds,
    DateTimeOffset CreatedAtUtc);

public sealed record AiExplanationRunDetailResponse(
    AiExplanationRunSummaryResponse Run,
    int ResultCount,
    int Page,
    int PageSize,
    IReadOnlyList<AiExplanationResultResponse> Results,
    string Disclaimer);
