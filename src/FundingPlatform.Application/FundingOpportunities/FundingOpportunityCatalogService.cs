using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FundingOpportunityCatalogService(IFundingOpportunityRepository repository)
{
    public Task<FundingOpportunityPage> SearchAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (pageNumber < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(pageNumber));
        }

        if (pageSize is < 1 or > 50)
        {
            throw new ArgumentOutOfRangeException(nameof(pageSize));
        }

        var normalizedQuery = string.IsNullOrWhiteSpace(query) ? null : query.Trim();
        if (normalizedQuery?.Length > 300)
        {
            throw new ArgumentOutOfRangeException(nameof(query));
        }

        return repository.SearchPublishedAsync(
            normalizedQuery,
            pageNumber,
            pageSize,
            cancellationToken);
    }

    public Task<FundingOpportunityDetails?> GetBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        var normalized = slug?.Trim();
        return string.IsNullOrWhiteSpace(normalized) || normalized.Length > 320
            ? Task.FromResult<FundingOpportunityDetails?>(null)
            : repository.GetPublishedBySlugAsync(normalized, cancellationToken);
    }
}
