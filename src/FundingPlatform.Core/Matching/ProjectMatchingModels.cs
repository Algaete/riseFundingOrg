namespace FundingPlatform.Core.Matching;

public enum MatchingRunStatus : byte
{
    Pending = 0,
    Running = 1,
    Completed = 2,
    Failed = 3
}

public enum MatchingClassification : byte
{
    Compatible = 0,
    Incompatible = 1,
    InsufficientData = 2
}

public enum MatchingHardGateStatus : byte
{
    Pass = 0,
    Fail = 1,
    Unknown = 2
}

public enum MatchingRuleOutcome : byte
{
    Match = 0,
    Partial = 1,
    NoMatch = 2,
    Unknown = 3
}

public enum MatchingDataState : byte
{
    Known = 0,
    Unknown = 1,
    NotApplicable = 2
}

public sealed record MatchingProjectReference(
    Guid PublicId,
    string Slug,
    string Title);

public sealed record MatchingProfileReference(
    string Name,
    int Version);

public sealed record ProjectMatchingRunSummary(
    Guid PublicId,
    MatchingProjectReference Project,
    MatchingRunStatus Status,
    string EngineVersion,
    MatchingProfileReference MatchingProfile,
    int ProjectVersion,
    int OrganizationProfileVersion,
    int CandidateCount,
    int CompatibleCount,
    int IncompatibleCount,
    int InsufficientDataCount,
    int TotalCandidateCount,
    bool IsTruncated,
    bool IsCurrent,
    DateTimeOffset CatalogSnapshotAtUtc,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? CompletedAtUtc);

public sealed record MatchingFundingOpportunityReference(
    Guid PublicId,
    string Slug,
    string Title,
    string SponsorName,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    byte DeadlinePrecision,
    int ContentVersion);

public sealed record MatchingRuleEvidence(
    string Source,
    string FieldCode,
    IReadOnlyList<string> ValueCodes);

public sealed record ProjectMatchingRuleResult(
    string Code,
    string Name,
    bool IsHardGate,
    MatchingRuleOutcome Outcome,
    MatchingDataState DataState,
    decimal? RawScore,
    decimal Weight,
    decimal WeightedPoints,
    string ReasonCode,
    IReadOnlyDictionary<string, string?> ReasonParameters,
    MatchingRuleEvidence? Evidence,
    bool IsWarning);

public sealed record ProjectMatchingResult(
    MatchingFundingOpportunityReference FundingOpportunity,
    MatchingClassification Classification,
    decimal? CompatibilityScore,
    decimal EvidenceCoverage,
    MatchingHardGateStatus HardGateStatus,
    bool IsCurrent,
    IReadOnlyList<ProjectMatchingRuleResult> RuleResults);

public sealed record ProjectMatchingRunDetails(
    ProjectMatchingRunSummary Run,
    IReadOnlyList<ProjectMatchingResult> Items);

public sealed record ProjectMatchingRunPage(
    IReadOnlyList<ProjectMatchingRunSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record ProjectMatchingRunMutation(
    bool Succeeded,
    string Code,
    Guid MatchingRunPublicId,
    bool WasReplay);

public sealed record ProjectMatchingRunListFilters(
    int PageNumber,
    int PageSize);

public enum ProjectMatchingOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    NotReady,
    Unavailable,
    Conflict,
    IdempotencyConflict
}

public sealed record ProjectMatchingRunPageResult(
    ProjectMatchingOutcome Outcome,
    ProjectMatchingRunPage? Page = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record ProjectMatchingRunDetailsResult(
    ProjectMatchingOutcome Outcome,
    ProjectMatchingRunDetails? Details = null,
    IReadOnlyDictionary<string, string[]>? Errors = null,
    bool WasReplay = false);
