using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public interface IFundingOpportunityWorkspaceRepository
{
    Task<WorkspaceFundingOpportunityPage?> SearchAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingOpportunitySearchFilters filters,
        CancellationToken cancellationToken);

    Task<WorkspaceFundingOpportunityDetails?> GetPublishedAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid? fundingOpportunityPublicId,
        string? slug,
        CancellationToken cancellationToken);

    Task<WorkspaceFundingOpportunityPage?> ListFavoritesAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<FundingFavoriteMutation> PutFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken);

    Task<FundingFavoriteMutation> DeleteFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken);
}

public sealed class FundingOpportunityWorkspaceDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Funding opportunity workspace operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;

    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
