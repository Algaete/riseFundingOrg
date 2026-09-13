using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Core.Matching;

public sealed record GapRecommendationRequest(Guid ProjectId, Guid OpportunityId);

// Private input: loaded for an active member of the project's organization only.
public sealed record GapRecommendationContext(
    string ProjectTitle, string OpportunityTitle, int ContentVersion, int? HomeCountryId,
    int? ReviewedContentVersion, bool? RequiresConsortium, bool? RequiresInternationalPartner,
    string? EvidenceUrl, string? SoughtPartners, string? SoughtProfessionals, bool? SeekingConsortium,
    DateTimeOffset EvaluatedAtUtc, PartnerGeography? PartnerGeography = null,
    IReadOnlyList<int>? EligiblePartnerCountryIds = null, bool PartnerGeographyValid = true);

public sealed record GapCandidate(Guid Id, string Name, string? Summary, string Href,
    IReadOnlyList<int> SharedCategoryIds, IReadOnlyList<string> SharedSkills, int? HomeCountryId);
public sealed record GapRecommendation(string Code, IReadOnlyList<string> Origins, string? DeclaredNeed,
    string State, IReadOnlyList<GapCandidate> Candidates, int EvaluatedCandidateCount,
    long TotalCandidateCount, bool IsTruncated);
public sealed record GapRecommendationResult(string EngineVersion, string ProjectTitle, string OpportunityTitle,
    int ContentVersion, bool ClassificationCurrent, string? EvidenceUrl, DateTimeOffset EvaluatedAtUtc,
    IReadOnlyList<GapRecommendation> Items, PartnerGeography? PartnerGeography = null,
    string GeographyState = "unverified");
