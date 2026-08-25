namespace FundingPlatform.Contracts.Applications;

public sealed record FundingApplicationProjectResponse(
    Guid PublicId,
    string Slug,
    string Title);

public sealed record FundingApplicationOpportunityResponse(
    Guid PublicId,
    string Slug,
    string Title,
    string SponsorName,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    byte DeadlinePrecision);

public sealed record FundingApplicationResponse(
    Guid PublicId,
    FundingApplicationProjectResponse Project,
    FundingApplicationOpportunityResponse FundingOpportunity,
    byte Status,
    string? Notes,
    DateOnly? ApplicationDate,
    decimal? RequestedAmount,
    string? Currency,
    DateOnly? ResultDate,
    Guid OwnerUserPublicId,
    bool CanEdit,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record FundingApplicationPageResponse(
    IReadOnlyList<FundingApplicationResponse> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record CreateFundingApplicationRequest(
    Guid ProjectId,
    Guid FundingOpportunityId,
    string? Notes,
    DateOnly? ApplicationDate,
    decimal? RequestedAmount,
    string? Currency,
    DateOnly? ResultDate);

public sealed record UpdateFundingApplicationRequest(
    byte Status,
    string? Notes,
    DateOnly? ApplicationDate,
    decimal? RequestedAmount,
    string? Currency,
    DateOnly? ResultDate);

public sealed record FundingCalendarResponse(
    DateOnly From,
    DateOnly To,
    IReadOnlyList<FundingCalendarItemResponse> Items);

public sealed record FundingCalendarItemResponse(
    string EventKey,
    string EventType,
    DateOnly EventDate,
    DateTimeOffset? EventAtUtc,
    byte DatePrecision,
    string Title,
    byte? Status,
    Guid? FundingApplicationPublicId,
    Guid? ProjectPublicId,
    Guid? FundingOpportunityPublicId);
