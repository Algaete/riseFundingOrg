using FundingPlatform.Core.Projects;

namespace FundingPlatform.Core.Marketplace;

public enum MarketplaceProjectSort : byte
{
    Newest = 0,
    Title = 1,
    FundingGapDescending = 2
}

public sealed record MarketplaceProjectFilters(
    string? Query,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> ProjectTypeIds,
    ProjectStatus? ProjectStatus,
    string? Currency,
    MarketplaceProjectSort Sort,
    int PageNumber,
    int PageSize);

public sealed record MarketplaceProjectSummary(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    ProjectStatus Status,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    DateTimeOffset PublishedAtUtc,
    PublicProjectOrganization Organization);

public sealed record MarketplaceProjectPage(
    IReadOnlyList<MarketplaceProjectSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public enum MarketplaceOutcome
{
    Success,
    ValidationFailed,
    NotFound
}

public sealed record MarketplaceProjectPageResult(
    MarketplaceOutcome Outcome,
    MarketplaceProjectPage? Page = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record MarketplaceProjectDetailsResult(
    MarketplaceOutcome Outcome,
    PublicProjectDetails? Project = null);

public sealed record MarketplaceOrganizationResult(
    MarketplaceOutcome Outcome,
    MarketplaceOrganizationProfile? Organization = null);

public sealed record PublicOrganizationCatalogItem<TId>(
    TId Id,
    string Code,
    string Name);

public sealed record PublicOrganizationRegion(
    int Id,
    short CountryId,
    string Code,
    string Name);

public sealed record MarketplaceOrganizationProfile(
    Guid PublicId,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? EstablishedYear,
    PublicOrganizationCatalogItem<short> HomeCountry,
    PublicOrganizationCatalogItem<short> OrganizationType,
    PublicOrganizationCatalogItem<short>? OrganizationSize,
    IReadOnlyList<PublicOrganizationCatalogItem<short>> Countries,
    IReadOnlyList<PublicOrganizationRegion> Regions,
    IReadOnlyList<PublicOrganizationCatalogItem<int>> Categories,
    IReadOnlyList<PublicOrganizationCatalogItem<int>> BeneficiaryTypes,
    IReadOnlyList<PublicOrganizationCatalogItem<int>> ProjectTypes,
    IReadOnlyList<MarketplaceProjectSummary> Projects);
