using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public interface IFundingOpportunityRepository
{
    Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
        int expectedFundingSourceId,
        string expectedProviderCode,
        ExternalFundingOpportunity opportunity,
        CancellationToken cancellationToken);

    Task<FundingOpportunityPage> SearchPublishedAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken);
}

public sealed record FundingOpportunityUpsertResult(
    FundingOpportunityUpsertOutcome Outcome,
    Guid? OpportunityId);

public enum FundingOpportunityUpsertOutcome
{
    Created,
    Updated,
    Unchanged,
    StagedForReview
}
