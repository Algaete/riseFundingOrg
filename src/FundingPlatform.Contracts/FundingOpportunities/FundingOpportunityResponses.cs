namespace FundingPlatform.Contracts.FundingOpportunities;

public sealed record FundingOpportunityListResponse(
    IReadOnlyList<FundingOpportunityListItemResponse> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record FundingOpportunityListItemResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string SponsorName,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    string SourceName,
    string? SourceUrl,
    DateTimeOffset PublishedAtUtc,
    decimal DataQualityScore);

public sealed record FundingOpportunityDetailResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Description,
    string? Summary,
    string SponsorName,
    string? SponsorUrl,
    string? ApplicationUrl,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    string? EligibilityDescription,
    string? Requirements,
    string? Objectives,
    bool? RequiresCofunding,
    string SourceName,
    string? SourceUrl,
    string? ExternalId,
    DateTimeOffset LastVerifiedAtUtc,
    decimal DataQualityScore,
    IReadOnlyList<FundingOpportunityFunderResponse> Funders);
