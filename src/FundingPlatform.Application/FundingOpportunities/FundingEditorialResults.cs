using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public enum FundingEditorialOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    Forbidden,
    PreconditionFailed,
    Conflict,
    InvalidTransition,
    NotReady,
    IdempotencyConflict
}

public sealed record FundingEditorialCommandResult(
    FundingEditorialOutcome Outcome,
    Guid EntityPublicId,
    FundingPublicationStatus PublicationStatus = FundingPublicationStatus.Draft,
    int ContentVersion = 0,
    byte[]? RowVersion = null,
    bool WasReplay = false,
    IReadOnlyDictionary<string, string[]>? Errors = null,
    string? Code = null);

public sealed record FundingEditorialQueryResult<T>(
    FundingEditorialOutcome Outcome,
    T? Value = default);
