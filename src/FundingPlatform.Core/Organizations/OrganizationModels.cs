namespace FundingPlatform.Core.Organizations;

public sealed record CatalogOption<TId>(TId Id, string Code, string Name);

public sealed record RegionOption(int Id, short CountryId, string Code, string Name);

public sealed record LegalEntityTypeOption(short Id, short? CountryId, string Code, string Name);

public sealed record CurrencyOption(string Code, string Name, byte MinorUnits);

public sealed record OrganizationCatalogs(
    IReadOnlyList<CatalogOption<short>> Countries,
    IReadOnlyList<RegionOption> Regions,
    IReadOnlyList<CurrencyOption> Currencies,
    IReadOnlyList<CatalogOption<int>> FundingCategories,
    IReadOnlyList<CatalogOption<short>> FundingTypes,
    IReadOnlyList<CatalogOption<short>> OrganizationTypes,
    IReadOnlyList<LegalEntityTypeOption> LegalEntityTypes,
    IReadOnlyList<CatalogOption<short>> OrganizationSizes,
    IReadOnlyList<CatalogOption<int>> BeneficiaryTypes,
    IReadOnlyList<CatalogOption<int>> ProjectTypes,
    IReadOnlyList<CatalogOption<long>> Tags,
    IReadOnlyList<CatalogOption<short>> Languages);

public sealed record OrganizationSummary(
    Guid PublicId,
    string Name,
    byte MembershipRole,
    byte ProfileStatus,
    decimal ProfileCompleteness,
    int ProfileVersion,
    DateTimeOffset UpdatedAtUtc);

public sealed record OrganizationLanguage(short LanguageId, byte? Proficiency);

public sealed record OrganizationProfile(
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
    byte MembershipRole,
    byte[] RowVersion,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<long> TagIds,
    IReadOnlyList<OrganizationLanguage> Languages);

public sealed record OrganizationProfileData(
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
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<long> TagIds,
    IReadOnlyList<OrganizationLanguage> Languages);

public sealed record PersistedOrganization(
    Guid PublicId,
    int ProfileVersion,
    byte[] RowVersion);

public enum OrganizationWriteOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    Forbidden,
    Conflict,
    OwnedLimitReached
}

public sealed record OrganizationWriteResult(
    OrganizationWriteOutcome Outcome,
    PersistedOrganization? Organization = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);
