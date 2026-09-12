namespace FundingPlatform.Core.Marketplace;

public sealed record ProjectMapFilters(string? Query = null, short? CountryId = null,
    int? CategoryId = null, byte? ProjectStage = null, int? SustainableDevelopmentGoalId = null,
    byte? ProjectStatus = null, int Page = 1, int PageSize = 100,
    short? OrganizationTypeId = null, decimal? MinimumFundingGap = null,
    decimal? MaximumFundingGap = null, string? Currency = null,
    bool SeekingFunding = false, bool SeekingPartners = false,
    bool SeekingProfessionals = false, bool SeekingConsortium = false,
    IReadOnlyList<Guid>? ProjectIds = null);

// Coordinates in this contract have already passed the public opt-in boundary.
public sealed record ProjectMapPoint(Guid PublicId, string Slug, string Title, string? Summary,
    string OrganizationName, decimal Latitude, decimal Longitude, byte ProjectStatus,
    byte? ProjectStage, decimal? FundingGap, string? Currency);

public sealed record ProjectMapPage(IReadOnlyList<ProjectMapPoint> Items, long TotalCount,
    long WithoutPublicLocationCount, int Page, int PageSize);
