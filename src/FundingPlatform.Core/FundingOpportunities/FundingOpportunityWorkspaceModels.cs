namespace FundingPlatform.Core.FundingOpportunities;

public enum FundingOpportunitySearchSort : byte
{
    Relevance = 1,
    ClosingSoon = 2,
    Newest = 3,
    AmountAscending = 4,
    AmountDescending = 5
}

public sealed record FundingOpportunitySearchFilters(
    string? Query,
    string? Sponsor,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    string? Currency,
    DateOnly? ClosingFrom,
    DateOnly? ClosingTo,
    bool OnlyOpen,
    FundingOpportunitySearchSort Sort,
    int PageNumber,
    int PageSize,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<long> TagIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<short> FundingTypeIds,
    IReadOnlyList<short> OrganizationTypeIds,
    IReadOnlyList<Guid> FunderPublicIds);

public sealed record WorkspaceFundingOpportunitySummary(
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
    DateTimeOffset? CloseAtUtc,
    FundingDeadlineType DeadlineType,
    FundingDeadlinePrecision DeadlinePrecision,
    DateTimeOffset PublishedAtUtc,
    decimal DataQualityScore,
    Guid PrimaryFunderPublicId,
    string PrimaryFunderName,
    string SourceName,
    string SourceUrl,
    bool IsFavorite);

public sealed record WorkspaceFundingOpportunityPage(
    IReadOnlyList<WorkspaceFundingOpportunitySummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize,
    string SearchMode = "none");

public sealed record FundingOpportunityEligibilityType(
    short Id,
    byte EligibilityMode);

public sealed record FundingOpportunityLanguage(
    short Id,
    byte LanguagePurpose);

public sealed record WorkspaceFundingOpportunitySource(
    int FundingSourceId,
    string SourceName,
    string? ExternalId,
    string SourceUrl,
    DateTimeOffset FirstSeenAtUtc,
    DateTimeOffset LastSeenAtUtc,
    bool IsPrimary,
    bool IsActive);

public sealed record WorkspaceFundingOpportunityDetails(
    Guid PublicId,
    string Slug,
    string Title,
    string? Description,
    string? Summary,
    string SponsorName,
    string? SponsorUrl,
    string? ApplicationUrl,
    short? IssuerCountryId,
    short? FundingTypeId,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    FundingAmountStatus AmountStatus,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    string? DeadlineTimeZoneId,
    FundingDeadlineType DeadlineType,
    FundingDeadlinePrecision DeadlinePrecision,
    string? EligibilityDescription,
    string? Requirements,
    string? Objectives,
    string? AllowedActivities,
    string? ExcludedActivities,
    string? Restrictions,
    string? TargetOrganizationsDescription,
    string? TargetPopulationsDescription,
    short? MinimumOperatingYears,
    bool? RequiresLegalEntity,
    bool? RequiresPriorExperience,
    bool? RequiresCofunding,
    decimal? CofundingPercentage,
    FundingGeographicScope GeographicScope,
    FundingRemoteApplication RemoteApplication,
    DateTimeOffset LastVerifiedAtUtc,
    decimal DataQualityScore,
    int ContentVersion,
    DateTimeOffset PublishedAtUtc,
    Guid PrimaryFunderPublicId,
    string PrimaryFunderSlug,
    string PrimaryFunderName,
    string SourceName,
    string SourceUrl,
    string? ExternalId,
    bool IsFavorite,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<long> TagIds,
    IReadOnlyList<FundingOpportunityEligibilityType> OrganizationTypes,
    IReadOnlyList<FundingOpportunityEligibilityType> LegalEntityTypes,
    IReadOnlyList<FundingOpportunityLanguage> Languages,
    IReadOnlyList<FundingOpportunityFunder> Funders,
    IReadOnlyList<WorkspaceFundingOpportunitySource> Sources);

public enum FundingFavoriteMutationOutcome
{
    Created,
    Deleted,
    Unchanged,
    NotFound
}

public sealed record FundingFavoriteMutation(
    FundingFavoriteMutationOutcome Outcome,
    Guid FundingOpportunityPublicId,
    DateTimeOffset? CreatedAtUtc);
