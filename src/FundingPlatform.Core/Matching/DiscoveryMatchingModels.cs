namespace FundingPlatform.Core.Matching;

public enum DiscoverySubjectKind : byte { Project = 1, Organization = 2, Funder = 3, Opportunity = 4 }
public enum DiscoveryTargetKind : byte { Projects = 1, Organizations = 2, Professionals = 3 }
public sealed record DiscoveryCriteria(int? CountryId = null, int? CategoryId = null, decimal? MinimumAmount = null,
    decimal? MaximumAmount = null, string? Currency = null, byte? ProjectStage = null);
public sealed record DiscoveryMatchingRequest(DiscoverySubjectKind SourceKind, Guid SourceId, DiscoveryTargetKind TargetKind,
    DiscoveryCriteria? Criteria = null, int Page = 1, int PageSize = 20);
public sealed record DiscoveryFeatures(int[] Countries, int[] Categories, int[] OrganizationTypes,
    decimal? MinimumAmount, decimal? MaximumAmount, string? Currency, bool Global = false,
    byte? ProjectStage = null, string? Needs = null, string[]? Skills = null, int[]? ExcludedOrganizationTypes = null);
public sealed record DiscoveryCandidate(Guid Id, string Name, string? Summary, string Href, DiscoveryFeatures Features);
public sealed record DiscoveryMatchingContext(string SourceName, DiscoveryFeatures Source, IReadOnlyList<DiscoveryCandidate> Candidates,
    long TotalCandidateCount, DateTimeOffset EvaluatedAtUtc);
public sealed record DiscoveryRule(string Code, string Outcome, int Weight, IReadOnlyList<string> Evidence);
public sealed record DiscoveryMatch(Guid Id, string Name, string? Summary, string Href, decimal? Score,
    decimal EvidenceCoverage, string Classification, IReadOnlyList<DiscoveryRule> Reasons);
public sealed record DiscoveryMatchingPage(string SourceName, string EngineVersion, DateTimeOffset EvaluatedAtUtc,
    IReadOnlyList<DiscoveryMatch> Items, long TotalCount, long TotalCandidateCount, bool IsTruncated, int Page, int PageSize);
