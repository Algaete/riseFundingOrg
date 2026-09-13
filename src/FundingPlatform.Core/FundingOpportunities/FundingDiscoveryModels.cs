namespace FundingPlatform.Core.FundingOpportunities;

public sealed record FundingDiscoveryFilters(string? Query = null, short? CountryId = null, int? RegionId = null,
    int? CategoryId = null, short? FundingTypeId = null, short? OrganizationTypeId = null, short? LanguageId = null,
    byte? FunderKind = null, bool? RequiresConsortium = null, bool? RequiresInternationalPartner = null,
    decimal? MinimumAmount = null, decimal? MaximumAmount = null, string? Currency = null,
    DateOnly? ClosingFrom = null, DateOnly? ClosingTo = null, bool OnlyOpen = true, int Page = 1, int PageSize = 20);
public sealed record FundingDiscoveryData(byte? FunderKind, bool? RequiresConsortium, bool? RequiresInternationalPartner, string? EvidenceUrl,
    PartnerGeography? PartnerGeography = null);
public sealed record FundingDiscoveryReview(int ContentVersion, FundingDiscoveryData Data);
public sealed record FundingDiscoveryAdmin(Guid OpportunityId, string Title, int ContentVersion, int? ReviewedContentVersion,
    FundingDiscoveryData? Data, string? ETag, IReadOnlyList<string> SourceUrls);
public sealed record FundingDiscoveryItem(Guid Id, string Slug, string Title, string? Summary, string SourceName,
    string SourceUrl, DateTimeOffset? LastVerifiedAtUtc, decimal? MinimumAmount, decimal? MaximumAmount,
    string? Currency, DateOnly? CloseDate, FundingDiscoveryData? Classification);
public sealed record FundingDiscoveryPage(IReadOnlyList<FundingDiscoveryItem> Items, long TotalCount, int Page, int PageSize);
