using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.UnitTests;

public sealed class FundingOpportunityWorkspaceServiceTests
{
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Fact]
    public async Task Search_normalizes_filters_before_calling_the_repository()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);
        var filters = ValidFilters() with
        {
            Query = "  agua segura  ",
            Currency = " usd ",
            CountryIds = [152, 56, 152],
            FunderPublicIds =
            [
                Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"),
                Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc")
            ]
        };

        var result = await service.SearchAsync(
            UserId, OrganizationId, filters, CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.Success, result.Outcome);
        Assert.Equal("agua segura", repository.LastFilters!.Query);
        Assert.Equal("USD", repository.LastFilters.Currency);
        Assert.Equal([56, 152], repository.LastFilters.CountryIds);
        Assert.Single(repository.LastFilters.FunderPublicIds);
        Assert.Equal(1, repository.SearchCalls);
    }

    [Theory]
    [InlineData(FundingOpportunitySearchSort.Relevance, null, "sort")]
    [InlineData(FundingOpportunitySearchSort.AmountAscending, null, "sort")]
    public async Task Search_rejects_orders_without_their_required_context(
        FundingOpportunitySearchSort sort,
        string? query,
        string errorKey)
    {
        var repository = new StubRepository();
        var service = CreateService(repository);
        var filters = ValidFilters() with { Sort = sort, Query = query, Currency = null };

        var result = await service.SearchAsync(
            UserId, OrganizationId, filters, CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.ValidationFailed, result.Outcome);
        Assert.Contains(errorKey, result.Errors!.Keys);
        Assert.Equal(0, repository.SearchCalls);
    }

    [Fact]
    public async Task Search_rejects_an_undefined_sort_without_calling_the_repository()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);

        var result = await service.SearchAsync(
            UserId,
            OrganizationId,
            ValidFilters() with { Sort = (FundingOpportunitySearchSort)255 },
            CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("sort", result.Errors!.Keys);
        Assert.Equal(0, repository.SearchCalls);
    }

    [Fact]
    public async Task Search_rejects_amount_filters_without_a_currency()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);

        var result = await service.SearchAsync(
            UserId,
            OrganizationId,
            ValidFilters() with { MinimumAmount = 100, Currency = null },
            CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("currency", result.Errors!.Keys);
        Assert.Equal(0, repository.SearchCalls);
    }

    [Fact]
    public async Task Search_normalizes_defensive_null_collections_to_empty_lists()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);
        var filters = ValidFilters() with
        {
            CountryIds = null!,
            RegionIds = null!,
            CategoryIds = null!,
            TagIds = null!,
            BeneficiaryTypeIds = null!,
            ProjectTypeIds = null!,
            FundingTypeIds = null!,
            OrganizationTypeIds = null!,
            FunderPublicIds = null!
        };

        var result = await service.SearchAsync(
            UserId, OrganizationId, filters, CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.Success, result.Outcome);
        Assert.Empty(repository.LastFilters!.CountryIds);
        Assert.Empty(repository.LastFilters.FunderPublicIds);
    }

    [Fact]
    public async Task Search_maps_the_SQL_filter_guard_to_a_sanitized_validation_error()
    {
        var repository = new StubRepository { SearchErrorNumber = 52002 };
        var service = CreateService(repository);

        var result = await service.SearchAsync(
            UserId, OrganizationId, ValidFilters(), CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(
            "Uno o más filtros no son válidos.",
            Assert.Single(result.Errors!["filters"]));
        Assert.DoesNotContain("database", result.Errors["filters"][0],
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Empty_tenant_or_favorite_identifier_fails_closed_without_repository_access()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);

        var search = await service.SearchAsync(
            UserId, Guid.Empty, ValidFilters(), CancellationToken.None);
        var favorite = await service.PutFavoriteAsync(
            UserId, OrganizationId, Guid.Empty, CancellationToken.None);

        Assert.Equal(FundingOpportunityWorkspaceSearchOutcome.NotFound, search.Outcome);
        Assert.Equal(FundingFavoriteMutationOutcome.NotFound, favorite.Outcome);
        Assert.Equal(0, repository.SearchCalls);
        Assert.Equal(0, repository.PutCalls);
    }

    [Fact]
    public async Task Get_routes_a_guid_as_public_id_and_a_slug_as_slug()
    {
        var repository = new StubRepository();
        var service = CreateService(repository);
        var opportunityId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

        _ = await service.GetAsync(
            UserId, OrganizationId, opportunityId.ToString("D"), CancellationToken.None);
        Assert.Equal(opportunityId, repository.LastOpportunityId);
        Assert.Null(repository.LastSlug);

        _ = await service.GetAsync(
            UserId, OrganizationId, "  fondo-agua-segura  ", CancellationToken.None);
        Assert.Null(repository.LastOpportunityId);
        Assert.Equal("fondo-agua-segura", repository.LastSlug);
    }

    private static FundingOpportunityWorkspaceService CreateService(StubRepository repository) =>
        new(repository);

    private static FundingOpportunitySearchFilters ValidFilters() => new(
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        true,
        FundingOpportunitySearchSort.ClosingSoon,
        1,
        20,
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        []);

    private sealed class StubRepository : IFundingOpportunityWorkspaceRepository
    {
        public int SearchCalls { get; private set; }
        public int PutCalls { get; private set; }
        public int? SearchErrorNumber { get; init; }
        public FundingOpportunitySearchFilters? LastFilters { get; private set; }
        public Guid? LastOpportunityId { get; private set; }
        public string? LastSlug { get; private set; }

        public Task<WorkspaceFundingOpportunityPage?> SearchAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            FundingOpportunitySearchFilters filters,
            CancellationToken cancellationToken)
        {
            SearchCalls++;
            LastFilters = filters;
            if (SearchErrorNumber.HasValue)
            {
                throw new FundingOpportunityWorkspaceDataException(
                    "search",
                    SearchErrorNumber.Value,
                    new Exception("sensitive database detail"));
            }
            return Task.FromResult<WorkspaceFundingOpportunityPage?>(new(
                [], 0, filters.PageNumber, filters.PageSize));
        }

        public Task<WorkspaceFundingOpportunityDetails?> GetPublishedAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid? fundingOpportunityPublicId,
            string? slug,
            CancellationToken cancellationToken)
        {
            LastOpportunityId = fundingOpportunityPublicId;
            LastSlug = slug;
            return Task.FromResult<WorkspaceFundingOpportunityDetails?>(null);
        }

        public Task<WorkspaceFundingOpportunityPage?> ListFavoritesAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            int pageNumber,
            int pageSize,
            CancellationToken cancellationToken) =>
            Task.FromResult<WorkspaceFundingOpportunityPage?>(new(
                [], 0, pageNumber, pageSize));

        public Task<FundingFavoriteMutation> PutFavoriteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingOpportunityPublicId,
            CancellationToken cancellationToken)
        {
            PutCalls++;
            return Task.FromResult(new FundingFavoriteMutation(
                FundingFavoriteMutationOutcome.Created,
                fundingOpportunityPublicId,
                new DateTimeOffset(2026, 8, 22, 12, 30, 0, TimeSpan.Zero)));
        }

        public Task<FundingFavoriteMutation> DeleteFavoriteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingOpportunityPublicId,
            CancellationToken cancellationToken) =>
            Task.FromResult(new FundingFavoriteMutation(
                FundingFavoriteMutationOutcome.Deleted,
                fundingOpportunityPublicId,
                null));
    }
}
