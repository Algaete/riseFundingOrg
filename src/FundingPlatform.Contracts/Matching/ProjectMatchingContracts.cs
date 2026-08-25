namespace FundingPlatform.Contracts.Matching;

public sealed record MatchingProjectResponse(
    Guid PublicId,
    string Slug,
    string Title);

public sealed record MatchingProfileResponse(
    string Name,
    int Version);

public sealed record ProjectMatchingRunSummaryResponse(
    Guid PublicId,
    MatchingProjectResponse Project,
    byte Status,
    string EngineVersion,
    MatchingProfileResponse MatchingProfile,
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

public sealed record ProjectMatchingRunPageResponse(
    IReadOnlyList<ProjectMatchingRunSummaryResponse> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record MatchingFundingOpportunityResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string SponsorName,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    byte DeadlinePrecision,
    int ContentVersion);

public sealed record MatchingRuleEvidenceResponse(
    string Source,
    string FieldCode,
    IReadOnlyList<string> ValueCodes);

public sealed record ProjectMatchingRuleResultResponse(
    string Code,
    string Name,
    bool IsHardGate,
    byte Outcome,
    byte DataState,
    decimal? RawScore,
    decimal Weight,
    decimal WeightedPoints,
    string ReasonCode,
    IReadOnlyDictionary<string, string?> ReasonParameters,
    MatchingRuleEvidenceResponse? Evidence,
    bool IsWarning);

public sealed record ProjectMatchingResultResponse(
    MatchingFundingOpportunityResponse FundingOpportunity,
    byte Classification,
    decimal? CompatibilityScore,
    decimal EvidenceCoverage,
    byte HardGateStatus,
    bool IsCurrent,
    IReadOnlyList<ProjectMatchingRuleResultResponse> RuleResults);

public sealed record ProjectMatchingRunDetailsResponse(
    ProjectMatchingRunSummaryResponse Run,
    IReadOnlyList<ProjectMatchingResultResponse> Items,
    string Disclaimer);

public sealed record ProjectMatchingExecutionResponse(
    ProjectMatchingRunDetailsResponse Run,
    bool WasReplay);
