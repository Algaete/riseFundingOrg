namespace FundingPlatform.Contracts.Projects;

public sealed record ProjectWorkflowResponse(
    Guid ProjectId,
    byte PublicationStatus,
    decimal Completeness,
    string ETag,
    bool WasReplay);

public sealed record ProjectReviewRequest(
    string Decision,
    string? Reason);

public sealed record ProjectReviewQueueResponse(
    IReadOnlyList<ProjectReviewQueueItemResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record ProjectReviewQueueItemResponse(
    Guid ProjectId,
    string Slug,
    string Title,
    string? Summary,
    byte ProjectStatus,
    byte PublicationStatus,
    Guid OrganizationPublicId,
    string OrganizationName,
    decimal Completeness,
    DateTimeOffset SubmittedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record ProjectAdminReviewDetailResponse(
    Guid ProjectId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    byte ProjectStatus,
    byte PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    decimal Completeness,
    DateTimeOffset SubmittedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    PublicProjectOrganizationResponse Organization,
    IReadOnlyList<PublicProjectTaxonomyResponse> Countries,
    IReadOnlyList<PublicProjectRegionResponse> Regions,
    IReadOnlyList<PublicProjectTaxonomyResponse> Categories,
    IReadOnlyList<PublicProjectTaxonomyResponse> BeneficiaryTypes,
    IReadOnlyList<PublicProjectTaxonomyResponse> ProjectTypes);

public sealed record PublicProjectResponse(
    Guid ProjectId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    byte ProjectStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    DateTimeOffset PublishedAtUtc,
    PublicProjectOrganizationResponse Organization,
    IReadOnlyList<PublicProjectTaxonomyResponse> Countries,
    IReadOnlyList<PublicProjectRegionResponse> Regions,
    IReadOnlyList<PublicProjectTaxonomyResponse> Categories,
    IReadOnlyList<PublicProjectTaxonomyResponse> BeneficiaryTypes,
    IReadOnlyList<PublicProjectTaxonomyResponse> ProjectTypes);

public sealed record PublicProjectOrganizationResponse(
    Guid PublicId,
    string Name,
    string? WebsiteUrl);

public sealed record PublicProjectTaxonomyResponse(
    int Id,
    string Code,
    string Name);

public sealed record PublicProjectRegionResponse(
    int Id,
    short CountryId,
    string Code,
    string Name);
