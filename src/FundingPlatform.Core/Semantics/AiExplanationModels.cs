namespace FundingPlatform.Core.Semantics;

public enum AiExplanationRunStatus : byte
{
    Processing = 0,
    Completed = 2,
    PermanentFailed = 4
}

public enum AiExplanationAssessment : byte
{
    Aligned = 0,
    Conflict = 1,
    Insufficient = 2
}

public sealed record AiExplanationJobLease(
    Guid JobPublicId,
    Guid LeaseId,
    Guid BudgetReservationPublicId,
    Guid ExplanationRunPublicId,
    string ExplanationConfigurationVersion,
    byte[] ConfigurationFingerprint,
    string ProviderCode,
    string ModelCode,
    string InputSchemaVersion,
    string OutputSchemaVersion,
    string PromptVersion,
    byte[] PromptFingerprint,
    byte[] ResponseSchemaFingerprint,
    short MaximumInputUtf8Bytes,
    short MaximumOutputTokens,
    byte MaximumAttempts,
    decimal MaximumCostUsdPerResult,
    byte[] InputContentHash,
    byte AttemptCount);

public sealed record AiExplanationInput(
    Guid JobPublicId,
    Guid LeaseId,
    string CanonicalInputJson,
    byte[] InputContentHash,
    AiProviderGovernanceContext ProviderGovernance);

public sealed record AiExplanationGeneration(
    string ProviderCode,
    string ModelCode,
    string PromptVersion,
    string OutputSchemaVersion,
    AiExplanationAssessment Assessment,
    string Summary,
    string PrimaryReasonCode,
    IReadOnlyList<string> CitedRuleCodes,
    byte[] OutputFingerprint,
    byte[]? ProviderRequestIdHash,
    int InputTokens,
    int OutputTokens,
    decimal EstimatedCostUsd,
    int LatencyMilliseconds);

public sealed record AiExplanationRunSummary(
    Guid PublicId,
    Guid SourceSemanticEvaluationRunPublicId,
    AiExplanationRunStatus Status,
    string ExplanationConfigurationVersion,
    string ProviderCode,
    string ModelCode,
    short ItemCount,
    short CompletedCount,
    short FailedCount,
    decimal? TotalEstimatedCostUsd,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc);

public sealed record AiExplanationResultItem(
    int CaseOrdinal,
    AiExplanationAssessment Assessment,
    string Summary,
    string PrimaryReasonCode,
    IReadOnlyList<string> CitedRuleCodes,
    int InputTokens,
    int OutputTokens,
    decimal EstimatedCostUsd,
    int LatencyMilliseconds,
    DateTimeOffset CreatedAtUtc);

public sealed record AiExplanationRunDetail(
    AiExplanationRunSummary Run,
    int ResultCount,
    int Page,
    int PageSize,
    IReadOnlyList<AiExplanationResultItem> Results);
