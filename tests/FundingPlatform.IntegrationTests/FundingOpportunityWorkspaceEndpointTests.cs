using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class FundingOpportunityWorkspaceEndpointTests :
    IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";

    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid OpportunityId =
        Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid FunderId =
        Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeWorkspaceRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public FundingOpportunityWorkspaceEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IFundingOpportunityWorkspaceRepository>();
                services.AddSingleton<IFundingOpportunityWorkspaceRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/funding-opportunities")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/funding-opportunities/fondo-agua")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/favorites")]
    [InlineData("PUT", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/favorites/cccccccc-cccc-cccc-cccc-cccccccccccc")]
    [InlineData("DELETE", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/favorites/cccccccc-cccc-cccc-cccc-cccccccccccc")]
    public async Task Workspace_routes_reject_anonymous_requests(string method, string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Search_binds_csv_filters_and_uses_relevance_for_a_query()
    {
        repository.SearchPage = new WorkspaceFundingOpportunityPage(
            [CreateSummary(isFavorite: true)], 1, 2, 10, "full-text");
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities" +
            $"?q=agua&countryIds=152,56&categoryIds=2&categoryIds=1" +
            $"&funderIds={FunderId:D}&page=2&pageSize=10");

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Contains("no-cache", response.Headers.Pragma.ToString());
        Assert.Equal(1, repository.SearchCalls);
        Assert.Equal(UserId, repository.LastUserId);
        Assert.Equal(OrganizationId, repository.LastOrganizationId);
        Assert.Equal("agua", repository.LastFilters!.Query);
        Assert.Equal(FundingOpportunitySearchSort.Relevance, repository.LastFilters.Sort);
        Assert.Equal([56, 152], repository.LastFilters.CountryIds);
        Assert.Equal([1, 2], repository.LastFilters.CategoryIds);
        Assert.Equal([FunderId], repository.LastFilters.FunderPublicIds);

        var payload = document.RootElement;
        Assert.Equal("full-text", payload.GetProperty("searchMode").GetString());
        Assert.Equal(2, payload.GetProperty("pageNumber").GetInt32());
        Assert.True(payload.GetProperty("items")[0].GetProperty("isFavorite").GetBoolean());
        Assert.Equal(FunderId,
            payload.GetProperty("items")[0].GetProperty("primaryFunderPublicId").GetGuid());
        Assert.Equal(new DateTimeOffset(2026, 12, 1, 20, 30, 0, TimeSpan.Zero),
            payload.GetProperty("items")[0].GetProperty("closeAtUtc").GetDateTimeOffset());
        Assert.Equal((byte)FundingDeadlineType.Fixed,
            payload.GetProperty("items")[0].GetProperty("deadlineType").GetByte());
        Assert.Equal((byte)FundingDeadlinePrecision.DateTime,
            payload.GetProperty("items")[0].GetProperty("deadlinePrecision").GetByte());
    }

    [Theory]
    [InlineData("countryIds=152,nope", "countryIds")]
    [InlineData("onlyOpen=yes", "onlyOpen")]
    [InlineData("closingFrom=22-08-2026", "closingFrom")]
    [InlineData("sort=Title%20DESC", "sort")]
    [InlineData("minAmount=100", "currency")]
    [InlineData("sort=amount-desc", "sort")]
    [InlineData("sort=relevance", "sort")]
    [InlineData("page=10001", "page")]
    [InlineData("currency=USD&minAmount=9999999999999999", "amount")]
    [InlineData("currency=USD&minAmount=1.00001", "amount")]
    public async Task Search_rejects_malformed_or_semantically_invalid_filters(
        string query,
        string expectedError)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities?{query}");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True(problem.RootElement.GetProperty("errors").TryGetProperty(
            expectedError, out _));
        Assert.Equal(0, repository.SearchCalls);
    }

    [Fact]
    public async Task Explicit_amount_sort_with_currency_is_allowlisted()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities" +
            "?currency=usd&minAmount=100.50&sort=amount-desc");

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("USD", repository.LastFilters!.Currency);
        Assert.Equal(100.50m, repository.LastFilters.MinimumAmount);
        Assert.Equal(
            FundingOpportunitySearchSort.AmountDescending,
            repository.LastFilters.Sort);
    }

    [Theory]
    [InlineData("search")]
    [InlineData("details")]
    [InlineData("favorites")]
    [InlineData("put")]
    [InlineData("delete")]
    public async Task Missing_membership_or_content_is_always_an_indistinguishable_404(
        string operation)
    {
        repository.FailClosed = true;
        var (method, path) = operation switch
        {
            "search" => (HttpMethod.Get,
                $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities"),
            "details" => (HttpMethod.Get,
                $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities/fondo-agua"),
            "favorites" => (HttpMethod.Get,
                $"/api/v1/organizations/{OrganizationId:D}/favorites"),
            "put" => (HttpMethod.Put,
                $"/api/v1/organizations/{OrganizationId:D}/favorites/{OpportunityId:D}"),
            _ => (HttpMethod.Delete,
                $"/api/v1/organizations/{OrganizationId:D}/favorites/{OpportunityId:D}")
        };
        using var request = AuthenticatedRequest(method, path);

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/organization-funding-not-found",
            problem.RootElement.GetProperty("type").GetString());
        Assert.DoesNotContain("membership", problem.RootElement.GetRawText(),
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Detail_returns_the_complete_published_projection_and_relations()
    {
        repository.Details = CreateDetails();
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/funding-opportunities/{OpportunityId:D}");

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var payload = document.RootElement;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(OpportunityId, repository.LastOpportunityId);
        Assert.Null(repository.LastSlug);
        Assert.True(payload.GetProperty("isFavorite").GetBoolean());
        Assert.Equal("ABC-123", payload.GetProperty("externalId").GetString());
        Assert.Equal("Solo implementación", payload.GetProperty("allowedActivities").GetString());
        Assert.Equal(152, payload.GetProperty("countryIds")[0].GetInt16());
        Assert.Equal(1,
            payload.GetProperty("organizationTypes")[0].GetProperty("eligibilityMode").GetByte());
        Assert.Equal("grants.gov",
            payload.GetProperty("sources")[0].GetProperty("sourceName").GetString());
        Assert.False(payload.TryGetProperty("rowVersion", out _));
        Assert.False(payload.TryGetProperty("evidence", out _));
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Favorite_put_and_delete_are_idempotent_204_mutations()
    {
        using var put = AuthenticatedRequest(
            HttpMethod.Put,
            $"/api/v1/organizations/{OrganizationId:D}/favorites/{OpportunityId:D}");
        using var firstResponse = await client.SendAsync(put);
        repository.PutOutcome = FundingFavoriteMutationOutcome.Unchanged;
        using var repeatedPut = AuthenticatedRequest(
            HttpMethod.Put,
            $"/api/v1/organizations/{OrganizationId:D}/favorites/{OpportunityId:D}");
        using var secondResponse = await client.SendAsync(repeatedPut);
        using var delete = AuthenticatedRequest(
            HttpMethod.Delete,
            $"/api/v1/organizations/{OrganizationId:D}/favorites/{OpportunityId:D}");
        using var deleteResponse = await client.SendAsync(delete);

        Assert.Equal(HttpStatusCode.NoContent, firstResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, secondResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);
        Assert.Equal(2, repository.PutCalls);
        Assert.Equal(1, repository.DeleteCalls);
        Assert.Contains("no-store", deleteResponse.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Favorite_list_is_paginated_and_never_publicly_cacheable()
    {
        repository.FavoritePage = new WorkspaceFundingOpportunityPage(
            [CreateSummary(isFavorite: true)], 11, 2, 5);
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/favorites?page=2&pageSize=5");

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(2, repository.LastPageNumber);
        Assert.Equal(5, repository.LastPageSize);
        Assert.Equal(11, document.RootElement.GetProperty("totalCount").GetInt64());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task OpenApi_contains_the_workspace_search_detail_and_favorite_routes()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var paths = document.RootElement.GetProperty("paths");

        var search = paths.GetProperty(
            "/api/v1/organizations/{organizationId}/funding-opportunities")
            .GetProperty("get");
        Assert.True(search.GetProperty("responses").TryGetProperty("429", out _));
        Assert.True(paths.GetProperty(
            "/api/v1/organizations/{organizationId}/funding-opportunities/{idOrSlug}")
            .TryGetProperty("get", out _));
        var favorites = paths.GetProperty(
            "/api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}");
        Assert.True(favorites.TryGetProperty("put", out _));
        Assert.True(favorites.TryGetProperty("delete", out _));
    }

    [Fact]
    public void Workspace_routes_have_explicit_read_and_write_rate_limit_policies()
    {
        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();

        var search = Assert.Single(endpoints, endpoint => endpoint.RoutePattern.RawText ==
            "/api/v1/organizations/{organizationId:guid}/funding-opportunities");
        var favoritePut = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText ==
                "/api/v1/organizations/{organizationId:guid}/favorites/{fundingOpportunityId:guid}" &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("PUT"));

        Assert.Equal(
            "organization-funding-read",
            search.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Equal(
            "organization-write",
            favoritePut.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedRequest(HttpMethod method, string path)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
                new Claim("auth_level", "full"),
                new Claim("amr", "pwd"),
                new Claim("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
            ],
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static WorkspaceFundingOpportunitySummary CreateSummary(bool isFavorite) => new(
        OpportunityId,
        "fondo-agua",
        "Fondo de agua segura",
        "Financia proyectos de agua.",
        "Fundación Global",
        "USD",
        10_000,
        50_000,
        new DateOnly(2026, 8, 1),
        new DateOnly(2026, 12, 1),
        new DateTimeOffset(2026, 12, 1, 20, 30, 0, TimeSpan.Zero),
        FundingDeadlineType.Fixed,
        FundingDeadlinePrecision.DateTime,
        new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
        95,
        FunderId,
        "Fundación Global",
        "grants.gov",
        "https://www.grants.gov/example",
        isFavorite);

    private static WorkspaceFundingOpportunityDetails CreateDetails() => new(
        OpportunityId,
        "fondo-agua",
        "Fondo de agua segura",
        "Descripción completa.",
        "Financia proyectos de agua.",
        "Fundación Global",
        "https://funder.example",
        "https://apply.example",
        152,
        1,
        "USD",
        10_000,
        50_000,
        FundingAmountStatus.Specified,
        new DateOnly(2026, 8, 1),
        new DateOnly(2026, 12, 1),
        null,
        null,
        FundingDeadlineType.Fixed,
        FundingDeadlinePrecision.Date,
        "Fundaciones activas.",
        "Entidad legal.",
        "Mejorar acceso al agua.",
        "Solo implementación",
        "Sin compra de terrenos",
        "Chile",
        "Fundaciones",
        "Comunidades rurales",
        2,
        true,
        false,
        false,
        null,
        FundingGeographicScope.Specified,
        FundingRemoteApplication.Yes,
        new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
        95,
        3,
        new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
        FunderId,
        "fundacion-global",
        "Fundación Global",
        "grants.gov",
        "https://www.grants.gov/example",
        "ABC-123",
        true,
        [152],
        [7],
        [1],
        [8],
        [1],
        [12L],
        [new FundingOpportunityEligibilityType(2, 1)],
        [new FundingOpportunityEligibilityType(1, 1)],
        [new FundingOpportunityLanguage(2, 1)],
        [new FundingOpportunityFunder(
            FunderId, "fundacion-global", "Fundación Global", FunderOpportunityRole.Primary)],
        [new WorkspaceFundingOpportunitySource(
            1,
            "grants.gov",
            "ABC-123",
            "https://www.grants.gov/example",
            new DateTimeOffset(2026, 8, 1, 0, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 20, 0, 0, 0, TimeSpan.Zero),
            true,
            true)]);

    private sealed class FakeWorkspaceRepository : IFundingOpportunityWorkspaceRepository
    {
        public bool FailClosed { get; set; }
        public WorkspaceFundingOpportunityPage SearchPage { get; set; } =
            new([], 0, 1, 20);
        public WorkspaceFundingOpportunityPage FavoritePage { get; set; } =
            new([], 0, 1, 20);
        public WorkspaceFundingOpportunityDetails? Details { get; set; }
        public FundingFavoriteMutationOutcome PutOutcome { get; set; } =
            FundingFavoriteMutationOutcome.Created;
        public int SearchCalls { get; private set; }
        public int GetCalls { get; private set; }
        public int FavoriteListCalls { get; private set; }
        public int PutCalls { get; private set; }
        public int DeleteCalls { get; private set; }
        public int TotalCalls => SearchCalls + GetCalls + FavoriteListCalls + PutCalls + DeleteCalls;
        public Guid? LastUserId { get; private set; }
        public Guid? LastOrganizationId { get; private set; }
        public Guid? LastOpportunityId { get; private set; }
        public string? LastSlug { get; private set; }
        public FundingOpportunitySearchFilters? LastFilters { get; private set; }
        public int? LastPageNumber { get; private set; }
        public int? LastPageSize { get; private set; }

        public Task<WorkspaceFundingOpportunityPage?> SearchAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            FundingOpportunitySearchFilters filters,
            CancellationToken cancellationToken)
        {
            SearchCalls++;
            Capture(userPublicId, organizationPublicId);
            LastFilters = filters;
            return Task.FromResult(FailClosed ? null : SearchPage)!;
        }

        public Task<WorkspaceFundingOpportunityDetails?> GetPublishedAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid? fundingOpportunityPublicId,
            string? slug,
            CancellationToken cancellationToken)
        {
            GetCalls++;
            Capture(userPublicId, organizationPublicId);
            LastOpportunityId = fundingOpportunityPublicId;
            LastSlug = slug;
            return Task.FromResult(FailClosed ? null : Details);
        }

        public Task<WorkspaceFundingOpportunityPage?> ListFavoritesAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            int pageNumber,
            int pageSize,
            CancellationToken cancellationToken)
        {
            FavoriteListCalls++;
            Capture(userPublicId, organizationPublicId);
            LastPageNumber = pageNumber;
            LastPageSize = pageSize;
            return Task.FromResult(FailClosed ? null : FavoritePage)!;
        }

        public Task<FundingFavoriteMutation> PutFavoriteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingOpportunityPublicId,
            CancellationToken cancellationToken)
        {
            PutCalls++;
            Capture(userPublicId, organizationPublicId);
            LastOpportunityId = fundingOpportunityPublicId;
            return Task.FromResult(new FundingFavoriteMutation(
                FailClosed ? FundingFavoriteMutationOutcome.NotFound : PutOutcome,
                fundingOpportunityPublicId,
                FailClosed
                    ? null
                    : new DateTimeOffset(2026, 8, 22, 12, 30, 0, TimeSpan.Zero)));
        }

        public Task<FundingFavoriteMutation> DeleteFavoriteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingOpportunityPublicId,
            CancellationToken cancellationToken)
        {
            DeleteCalls++;
            Capture(userPublicId, organizationPublicId);
            LastOpportunityId = fundingOpportunityPublicId;
            return Task.FromResult(new FundingFavoriteMutation(
                FailClosed
                    ? FundingFavoriteMutationOutcome.NotFound
                    : FundingFavoriteMutationOutcome.Deleted,
                fundingOpportunityPublicId,
                null));
        }

        private void Capture(Guid userId, Guid organizationId)
        {
            LastUserId = userId;
            LastOrganizationId = organizationId;
        }
    }
}
