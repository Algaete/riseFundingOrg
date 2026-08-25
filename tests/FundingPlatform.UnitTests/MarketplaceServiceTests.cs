using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.UnitTests;

public sealed class MarketplaceServiceTests
{
    [Fact]
    public async Task Search_normalizes_query_currency_and_identifier_sets()
    {
        var repository = new FakeMarketplaceRepository();
        var service = new MarketplaceService(repository);

        var result = await service.SearchProjectsAsync(
            new MarketplaceProjectFilters(
                "  agua  ",
                [152, 56, 152],
                [2, 1, 2],
                [8, 4, 8],
                ProjectStatus.SeekingFunding,
                " usd ",
                MarketplaceProjectSort.Newest,
                2,
                20),
            CancellationToken.None);

        Assert.Equal(MarketplaceOutcome.Success, result.Outcome);
        Assert.Equal("agua", repository.LastFilters!.Query);
        Assert.Equal("USD", repository.LastFilters.Currency);
        Assert.Equal([56, 152], repository.LastFilters.CountryIds);
        Assert.Equal([1, 2], repository.LastFilters.CategoryIds);
        Assert.Equal([4, 8], repository.LastFilters.ProjectTypeIds);
    }

    [Fact]
    public async Task Funding_gap_sort_requires_one_normalized_currency()
    {
        var repository = new FakeMarketplaceRepository();
        var service = new MarketplaceService(repository);

        var result = await service.SearchProjectsAsync(
            EmptyFilters() with { Sort = MarketplaceProjectSort.FundingGapDescending },
            CancellationToken.None);

        Assert.Equal(MarketplaceOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("currency", result.Errors!);
        Assert.Equal(0, repository.SearchCalls);
    }

    [Theory]
    [InlineData("US")]
    [InlineData("US1")]
    [InlineData("TOOLONG")]
    public async Task Search_rejects_invalid_currency(string currency)
    {
        var repository = new FakeMarketplaceRepository();
        var service = new MarketplaceService(repository);

        var result = await service.SearchProjectsAsync(
            EmptyFilters() with { Currency = currency },
            CancellationToken.None);

        Assert.Equal(MarketplaceOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("currency", result.Errors!);
        Assert.Equal(0, repository.SearchCalls);
    }

    [Fact]
    public async Task Organization_absence_is_a_public_not_found()
    {
        var service = new MarketplaceService(new FakeMarketplaceRepository());

        var result = await service.GetOrganizationAsync(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Equal(MarketplaceOutcome.NotFound, result.Outcome);
    }

    private static MarketplaceProjectFilters EmptyFilters() => new(
        null,
        [],
        [],
        [],
        null,
        null,
        MarketplaceProjectSort.Newest,
        1,
        20);

    private sealed class FakeMarketplaceRepository : IMarketplaceRepository
    {
        public int SearchCalls { get; private set; }
        public MarketplaceProjectFilters? LastFilters { get; private set; }

        public Task<MarketplaceProjectPage> SearchProjectsAsync(
            MarketplaceProjectFilters filters,
            CancellationToken cancellationToken)
        {
            SearchCalls++;
            LastFilters = filters;
            return Task.FromResult(new MarketplaceProjectPage(
                [], 0, filters.PageNumber, filters.PageSize));
        }

        public Task<PublicProjectDetails?> GetProjectBySlugAsync(
            string slug,
            CancellationToken cancellationToken) => Task.FromResult<PublicProjectDetails?>(null);

        public Task<MarketplaceOrganizationProfile?> GetOrganizationAsync(
            Guid organizationPublicId,
            CancellationToken cancellationToken) =>
            Task.FromResult<MarketplaceOrganizationProfile?>(null);
    }
}
