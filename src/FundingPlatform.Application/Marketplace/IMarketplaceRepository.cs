using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Application.Marketplace;

public interface IMarketplaceRepository
{
    Task<MarketplaceProjectPage> SearchProjectsAsync(
        MarketplaceProjectFilters filters,
        CancellationToken cancellationToken);

    Task<PublicProjectDetails?> GetProjectBySlugAsync(
        string slug,
        CancellationToken cancellationToken);

    Task<MarketplaceOrganizationProfile?> GetOrganizationAsync(
        Guid organizationPublicId,
        CancellationToken cancellationToken);
}

public sealed class MarketplaceDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Marketplace data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
