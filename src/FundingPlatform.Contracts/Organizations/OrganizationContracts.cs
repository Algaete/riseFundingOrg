namespace FundingPlatform.Contracts.Organizations;

public sealed record CatalogOptionResponse<TId>(TId Id, string Code, string Name);

public sealed record RegionOptionResponse(int Id, short CountryId, string Code, string Name);

public sealed record LegalEntityTypeOptionResponse(short Id, short? CountryId, string Code, string Name);

public sealed record CurrencyOptionResponse(string Code, string Name, byte MinorUnits);

public sealed record OrganizationCatalogsResponse(
    IReadOnlyList<CatalogOptionResponse<short>> Countries,
    IReadOnlyList<RegionOptionResponse> Regions,
    IReadOnlyList<CurrencyOptionResponse> Currencies,
    IReadOnlyList<CatalogOptionResponse<int>> FundingCategories,
    IReadOnlyList<CatalogOptionResponse<short>> FundingTypes,
    IReadOnlyList<CatalogOptionResponse<short>> OrganizationTypes,
    IReadOnlyList<LegalEntityTypeOptionResponse> LegalEntityTypes,
    IReadOnlyList<CatalogOptionResponse<short>> OrganizationSizes,
    IReadOnlyList<CatalogOptionResponse<int>> BeneficiaryTypes,
    IReadOnlyList<CatalogOptionResponse<int>> ProjectTypes,
    IReadOnlyList<CatalogOptionResponse<long>> Tags,
    IReadOnlyList<CatalogOptionResponse<short>> Languages);

public sealed record CreateOrganizationRequest(
    string Name,
    short HomeCountryId,
    short OrganizationTypeId);

public sealed record OrganizationSummaryResponse(
    Guid PublicId,
    string Name,
    string MembershipRole,
    byte ProfileStatus,
    decimal ProfileCompleteness,
    int ProfileVersion,
    DateTimeOffset UpdatedAtUtc);

public sealed record OrganizationCreatedResponse(
    Guid PublicId,
    int ProfileVersion,
    string ETag);

public sealed record OrganizationLanguageRequest(short LanguageId, byte? Proficiency);

public sealed record OrganizationLanguageResponse(short LanguageId, byte? Proficiency);

public sealed record UpdateOrganizationProfileRequest(
    string Name,
    string? LegalName,
    string? TaxIdentifier,
    short HomeCountryId,
    short OrganizationTypeId,
    short? LegalEntityTypeId,
    short? OrganizationSizeId,
    short? EstablishedYear,
    string? WebsiteUrl,
    string? Description,
    byte PreviousFundingExperience,
    string? ExperienceSummary,
    decimal? AnnualBudgetMin,
    decimal? AnnualBudgetMax,
    string? AnnualBudgetCurrency,
    decimal? DesiredFundingMin,
    decimal? DesiredFundingMax,
    string? DesiredFundingCurrency,
    IReadOnlyList<short>? CountryIds,
    IReadOnlyList<int>? RegionIds,
    IReadOnlyList<int>? CategoryIds,
    IReadOnlyList<int>? BeneficiaryTypeIds,
    IReadOnlyList<int>? ProjectTypeIds,
    IReadOnlyList<long>? TagIds,
    IReadOnlyList<OrganizationLanguageRequest>? Languages);

public sealed record OrganizationProfileResponse(
    Guid PublicId,
    string Name,
    string? LegalName,
    string? TaxIdentifier,
    short HomeCountryId,
    short OrganizationTypeId,
    short? LegalEntityTypeId,
    short? OrganizationSizeId,
    short? EstablishedYear,
    string? WebsiteUrl,
    string? Description,
    byte PreviousFundingExperience,
    string? ExperienceSummary,
    decimal? AnnualBudgetMin,
    decimal? AnnualBudgetMax,
    string? AnnualBudgetCurrency,
    decimal? DesiredFundingMin,
    decimal? DesiredFundingMax,
    string? DesiredFundingCurrency,
    byte ProfileStatus,
    decimal ProfileCompleteness,
    int ProfileVersion,
    string MembershipRole,
    bool CanEdit,
    string ETag,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<long> TagIds,
    IReadOnlyList<OrganizationLanguageResponse> Languages);

public sealed record ProfileCompletenessResponse(
    decimal Percentage,
    byte Status,
    int ProfileVersion);
