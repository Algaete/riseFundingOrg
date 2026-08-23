namespace FundingPlatform.Core.FundingOpportunities;

public sealed record FundingOpportunitySummary(
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

public sealed record FundingOpportunityDetails(
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
    IReadOnlyList<FundingOpportunityFunder>? Funders = null);

public sealed record FundingOpportunityPage(
    IReadOnlyList<FundingOpportunitySummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);
