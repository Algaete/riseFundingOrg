namespace FundingPlatform.Core.Applications;

public enum FundingApplicationStatus : byte
{
    Interested = 0,
    Applying = 1,
    Submitted = 2,
    Won = 3,
    Rejected = 4,
    Discarded = 5
}

public sealed record FundingApplicationReference(
    Guid PublicId,
    string Slug,
    string Title);

public sealed record FundingApplicationOpportunityReference(
    Guid PublicId,
    string Slug,
    string Title,
    string SponsorName,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    byte DeadlinePrecision);

public sealed record FundingApplicationDetails(
    Guid PublicId,
    FundingApplicationReference Project,
    FundingApplicationOpportunityReference FundingOpportunity,
    FundingApplicationStatus Status,
    string? Notes,
    DateOnly? ApplicationDate,
    decimal? RequestedAmount,
    string? Currency,
    DateOnly? ResultDate,
    Guid OwnerUserPublicId,
    bool CanEdit,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record FundingApplicationPage(
    IReadOnlyList<FundingApplicationDetails> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record FundingApplicationListFilters(
    FundingApplicationStatus? Status,
    Guid? ProjectPublicId,
    Guid? FundingOpportunityPublicId,
    int PageNumber,
    int PageSize);

public sealed record FundingApplicationData(
    FundingApplicationStatus Status,
    string? Notes,
    DateOnly? ApplicationDate,
    decimal? RequestedAmount,
    string? Currency,
    DateOnly? ResultDate);

public sealed record FundingApplicationMutation(
    bool Succeeded,
    string Code,
    Guid FundingApplicationPublicId,
    FundingApplicationStatus Status,
    Guid OwnerUserPublicId,
    byte[] RowVersion,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    bool WasReplay);

public enum FundingApplicationOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    PreconditionFailed,
    Conflict,
    IdempotencyConflict
}

public sealed record FundingApplicationPageResult(
    FundingApplicationOutcome Outcome,
    FundingApplicationPage? Page = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record FundingApplicationDetailsResult(
    FundingApplicationOutcome Outcome,
    FundingApplicationDetails? Application = null,
    IReadOnlyDictionary<string, string[]>? Errors = null,
    bool WasReplay = false);

public sealed record FundingCalendarItem(
    string EventKey,
    string EventType,
    DateOnly EventDate,
    DateTimeOffset? EventAtUtc,
    byte DatePrecision,
    string Title,
    FundingApplicationStatus? Status,
    Guid? FundingApplicationPublicId,
    Guid? ProjectPublicId,
    Guid? FundingOpportunityPublicId);

public sealed record FundingCalendarResult(
    FundingApplicationOutcome Outcome,
    DateOnly From,
    DateOnly To,
    IReadOnlyList<FundingCalendarItem> Items,
    IReadOnlyDictionary<string, string[]>? Errors = null);
