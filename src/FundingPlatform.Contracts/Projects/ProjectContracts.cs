namespace FundingPlatform.Contracts.Projects;

public sealed record ProjectSummaryResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    byte Status,
    byte PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    DateTimeOffset UpdatedAtUtc);

public sealed record ProjectResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    byte Status,
    byte PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    string? RejectionReason,
    DateTimeOffset? PublishedAtUtc);

public sealed record ProjectWriteRequest(
    string Title,
    string? Summary,
    string? Description,
    byte Status,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    IReadOnlyList<short>? CountryIds,
    IReadOnlyList<int>? RegionIds,
    IReadOnlyList<int>? CategoryIds,
    IReadOnlyList<int>? BeneficiaryTypeIds,
    IReadOnlyList<int>? ProjectTypeIds);

public sealed record ProjectCreatedResponse(Guid PublicId, int ProjectVersion, string ETag);
