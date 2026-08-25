using FundingPlatform.Contracts.Organizations;
using FundingPlatform.Contracts.Projects;

namespace FundingPlatform.Contracts.Marketplace;

public sealed record MarketplaceCatalogsResponse(
    IReadOnlyList<CatalogOptionResponse<short>> Countries,
    IReadOnlyList<CurrencyOptionResponse> Currencies,
    IReadOnlyList<CatalogOptionResponse<int>> FundingCategories,
    IReadOnlyList<CatalogOptionResponse<int>> ProjectTypes);

public sealed record MarketplaceProjectOrganizationResponse(
    Guid PublicId,
    string Name,
    string? WebsiteUrl);

public sealed record MarketplaceProjectSummaryResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    byte Status,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    DateTimeOffset PublishedAtUtc,
    MarketplaceProjectOrganizationResponse Organization);

public sealed record MarketplaceProjectPageResponse(
    IReadOnlyList<MarketplaceProjectSummaryResponse> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record MarketplaceProjectDetailsResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    byte Status,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    DateTimeOffset PublishedAtUtc,
    MarketplaceProjectOrganizationResponse Organization,
    IReadOnlyList<PublicProjectTaxonomyResponse> Countries,
    IReadOnlyList<PublicProjectRegionResponse> Regions,
    IReadOnlyList<PublicProjectTaxonomyResponse> Categories,
    IReadOnlyList<PublicProjectTaxonomyResponse> BeneficiaryTypes,
    IReadOnlyList<PublicProjectTaxonomyResponse> ProjectTypes);

public sealed record MarketplaceOrganizationProfileResponse(
    Guid PublicId,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? EstablishedYear,
    CatalogOptionResponse<short> HomeCountry,
    CatalogOptionResponse<short> OrganizationType,
    CatalogOptionResponse<short>? OrganizationSize,
    IReadOnlyList<CatalogOptionResponse<short>> Countries,
    IReadOnlyList<RegionOptionResponse> Regions,
    IReadOnlyList<CatalogOptionResponse<int>> Categories,
    IReadOnlyList<CatalogOptionResponse<int>> BeneficiaryTypes,
    IReadOnlyList<CatalogOptionResponse<int>> ProjectTypes,
    IReadOnlyList<MarketplaceProjectSummaryResponse> Projects);
