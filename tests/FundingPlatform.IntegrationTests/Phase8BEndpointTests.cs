using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Applications;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Applications;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Projects;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class Phase8BEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";

    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid OpportunityId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static readonly Guid ApplicationId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeMarketplaceRepository marketplace = new();
    private readonly FakeFundingApplicationRepository applications = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase8BEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IMarketplaceRepository>();
                services.AddSingleton<IMarketplaceRepository>(marketplace);
                services.RemoveAll<IFundingApplicationRepository>();
                services.AddSingleton<IFundingApplicationRepository>(applications);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Fact]
    public async Task Marketplace_search_is_anonymous_cacheable_and_server_paged()
    {
        marketplace.Page = new MarketplaceProjectPage(
            [ProjectSummary()], 17, 2, 10);

        using var response = await client.GetAsync(
            "/api/v1/marketplace/projects?q=agua&countryIds=152,56" +
            "&categoryIds=2,1&projectTypeIds=8&projectStatus=2" +
            "&currency=usd&sort=newest&page=2&pageSize=10");
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(60), response.Headers.CacheControl?.MaxAge);
        Assert.Equal("agua", marketplace.LastFilters!.Query);
        Assert.Equal("USD", marketplace.LastFilters.Currency);
        Assert.Equal([56, 152], marketplace.LastFilters.CountryIds);
        Assert.Equal([1, 2], marketplace.LastFilters.CategoryIds);
        Assert.Equal(17, payload.RootElement.GetProperty("totalCount").GetInt64());
        Assert.Equal(2, payload.RootElement.GetProperty("pageNumber").GetInt32());
        Assert.Equal(OrganizationId,
            payload.RootElement.GetProperty("items")[0]
                .GetProperty("organization").GetProperty("publicId").GetGuid());
    }

    [Fact]
    public async Task Marketplace_rejects_cross_currency_gap_sort_before_repository()
    {
        using var response = await client.GetAsync(
            "/api/v1/marketplace/projects?sort=funding-gap-desc");
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True(problem.RootElement.GetProperty("errors").TryGetProperty("currency", out _));
        Assert.Equal(0, marketplace.SearchCalls);
    }

    [Fact]
    public async Task Public_organization_projection_excludes_private_profile_fields()
    {
        marketplace.Organization = OrganizationProfile();

        using var response = await client.GetAsync(
            $"/api/v1/marketplace/organizations/{OrganizationId:D}");
        var json = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("description", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("taxIdentifier", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("legalName", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("annualBudget", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("membership", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("verified", json, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/applications")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/applications")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/applications/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")]
    [InlineData("PATCH", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/applications/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/calendar?from=2026-01-01&to=2026-12-31")]
    public async Task Private_activity_routes_require_a_full_session(string method, string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, applications.TotalCalls);
    }

    [Fact]
    public async Task Application_create_requires_idempotency_and_returns_created_with_etag()
    {
        using var missingKey = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/applications",
            CreateBody());
        using var missingResponse = await client.SendAsync(missingKey);

        Assert.Equal((HttpStatusCode)428, missingResponse.StatusCode);
        Assert.Equal(0, applications.CreateCalls);

        using var create = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/applications",
            CreateBody());
        create.Headers.Add("Idempotency-Key", "1234567890abcdef");
        using var response = await client.SendAsync(create);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal("\"0102030405060708\"", response.Headers.ETag?.Tag);
        Assert.Equal((byte)FundingApplicationStatus.Interested,
            payload.RootElement.GetProperty("status").GetByte());
        Assert.True(payload.RootElement.GetProperty("canEdit").GetBoolean());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(1, applications.CreateCalls);

        applications.CreateReplay = true;
        using var replay = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/applications",
            CreateBody());
        replay.Headers.Add("Idempotency-Key", "1234567890abcdef");
        using var replayResponse = await client.SendAsync(replay);

        Assert.Equal(HttpStatusCode.OK, replayResponse.StatusCode);
        Assert.Equal(2, applications.CreateCalls);
    }

    [Fact]
    public async Task Application_list_defaults_are_stable_and_invalid_status_is_rejected()
    {
        using var list = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/applications");
        using var response = await client.SendAsync(list);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, payload.RootElement.GetProperty("pageNumber").GetInt32());
        Assert.Equal(20, payload.RootElement.GetProperty("pageSize").GetInt32());

        using var invalid = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/applications?status=6");
        using var invalidResponse = await client.SendAsync(invalid);
        Assert.Equal(HttpStatusCode.BadRequest, invalidResponse.StatusCode);
    }

    [Fact]
    public async Task Stale_application_etag_is_412_and_foreign_tenant_is_safe_404()
    {
        applications.UpdateCode = "etag-conflict";
        using var stale = AuthenticatedRequest(
            HttpMethod.Patch,
            $"/api/v1/organizations/{OrganizationId:D}/applications/{ApplicationId:D}",
            UpdateBody());
        stale.Headers.IfMatch.Add(new EntityTagHeaderValue("\"FFFFFFFFFFFFFFFF\""));
        using var staleResponse = await client.SendAsync(stale);
        using var staleProblem = JsonDocument.Parse(await staleResponse.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.PreconditionFailed, staleResponse.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/funding-application-precondition-failed",
            staleProblem.RootElement.GetProperty("type").GetString());

        applications.ThrowNotFound = true;
        using var get = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/applications/{ApplicationId:D}");
        using var notFound = await client.SendAsync(get);
        var body = await notFound.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, notFound.StatusCode);
        Assert.DoesNotContain("member", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("tenant", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Calendar_is_no_store_bounded_and_keeps_application_status_typed()
    {
        applications.CalendarItems =
        [
            new FundingCalendarItem(
                $"application-deadline:{ApplicationId:D}",
                "application-deadline",
                new DateOnly(2026, 12, 1),
                null,
                1,
                "Fondo",
                FundingApplicationStatus.Applying,
                ApplicationId,
                ProjectId,
                OpportunityId),
            new FundingCalendarItem(
                $"project-start:{ProjectId:D}",
                "project-start",
                new DateOnly(2026, 9, 1),
                null,
                1,
                "Proyecto",
                null,
                null,
                ProjectId,
                null)
        ];
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/calendar" +
            "?from=2026-01-01&to=2026-12-31");
        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal((byte)FundingApplicationStatus.Applying,
            payload.RootElement.GetProperty("items")[0].GetProperty("status").GetByte());
        Assert.Equal(JsonValueKind.Null,
            payload.RootElement.GetProperty("items")[1].GetProperty("status").ValueKind);

        using var oversized = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/organizations/{OrganizationId:D}/calendar" +
            "?from=2026-01-01&to=2027-01-02");
        using var oversizedResponse = await client.SendAsync(oversized);
        Assert.Equal(HttpStatusCode.BadRequest, oversizedResponse.StatusCode);
        Assert.Equal(1, applications.CalendarCalls);
    }

    [Fact]
    public async Task OpenApi_and_endpoint_metadata_freeze_phase_8b_routes_and_limits()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var paths = document.RootElement.GetProperty("paths");

        Assert.True(paths.TryGetProperty("/api/v1/marketplace/catalogs", out _));
        Assert.True(paths.TryGetProperty("/api/v1/marketplace/projects", out _));
        Assert.True(paths.TryGetProperty(
            "/api/v1/marketplace/organizations/{organizationId}", out _));
        Assert.True(paths.GetProperty(
            "/api/v1/organizations/{organizationId}/applications").TryGetProperty("post", out _));
        var patch = paths.GetProperty(
            "/api/v1/organizations/{organizationId}/applications/{applicationId}")
            .GetProperty("patch");
        Assert.True(patch.GetProperty("responses").TryGetProperty("412", out _));
        Assert.True(patch.GetProperty("responses").TryGetProperty("428", out _));
        Assert.True(paths.TryGetProperty(
            "/api/v1/organizations/{organizationId}/calendar", out _));

        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        var marketplaceEndpoint = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText == "/api/v1/marketplace/projects");
        var applicationCreate = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText ==
                "/api/v1/organizations/{organizationId:guid}/applications" &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("POST"));
        var legacyProjectDetail = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText == "/api/v1/projects/{slug}");
        Assert.Equal("marketplace-read",
            marketplaceEndpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Equal("marketplace-read",
            legacyProjectDetail.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Equal("organization-write",
            applicationCreate.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        object? body = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

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

    private static object CreateBody() => new
    {
        projectId = ProjectId,
        fundingOpportunityId = OpportunityId,
        notes = "Preparar antecedentes",
        applicationDate = "2026-10-01",
        requestedAmount = 1000,
        currency = "USD",
        resultDate = (string?)null
    };

    private static object UpdateBody() => new
    {
        status = (byte)FundingApplicationStatus.Applying,
        notes = "Preparando",
        applicationDate = "2026-10-01",
        requestedAmount = 1000,
        currency = "USD",
        resultDate = (string?)null
    };

    private static MarketplaceProjectSummary ProjectSummary() => new(
        ProjectId,
        "agua-segura",
        "Agua segura",
        "Proyecto comunitario",
        ProjectStatus.SeekingFunding,
        new DateOnly(2026, 9, 1),
        new DateOnly(2027, 3, 1),
        10_000,
        2_000,
        "USD",
        8_000,
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        new PublicProjectOrganization(OrganizationId, "Fundación Demo", "https://demo.example"));

    private static MarketplaceOrganizationProfile OrganizationProfile() => new(
        OrganizationId,
        "Fundación Demo",
        "Trabajamos por el agua.",
        "https://demo.example",
        2010,
        new PublicOrganizationCatalogItem<short>(152, "CL", "Chile"),
        new PublicOrganizationCatalogItem<short>(1, "foundation", "Fundación"),
        null,
        [new PublicOrganizationCatalogItem<short>(152, "CL", "Chile")],
        [],
        [new PublicOrganizationCatalogItem<int>(1, "environment", "Medio ambiente")],
        [],
        [],
        [ProjectSummary()]);

    private static FundingApplicationDetails ApplicationDetails() => new(
        ApplicationId,
        new FundingApplicationReference(ProjectId, "agua-segura", "Agua segura"),
        new FundingApplicationOpportunityReference(
            OpportunityId,
            "fondo-agua",
            "Fondo de agua",
            "Fundación Global",
            new DateOnly(2026, 12, 1),
            null,
            1),
        FundingApplicationStatus.Interested,
        "Preparar antecedentes",
        new DateOnly(2026, 10, 1),
        1000,
        "USD",
        null,
        UserId,
        true,
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        [1, 2, 3, 4, 5, 6, 7, 8]);

    private sealed class FakeMarketplaceRepository : IMarketplaceRepository
    {
        public int SearchCalls { get; private set; }
        public MarketplaceProjectFilters? LastFilters { get; private set; }
        public MarketplaceProjectPage Page { get; set; } = new([], 0, 1, 20);
        public MarketplaceOrganizationProfile? Organization { get; set; }

        public Task<MarketplaceProjectPage> SearchProjectsAsync(
            MarketplaceProjectFilters filters,
            CancellationToken cancellationToken)
        {
            SearchCalls++;
            LastFilters = filters;
            return Task.FromResult(Page);
        }

        public Task<PublicProjectDetails?> GetProjectBySlugAsync(
            string slug,
            CancellationToken cancellationToken) => Task.FromResult<PublicProjectDetails?>(null);

        public Task<MarketplaceOrganizationProfile?> GetOrganizationAsync(
            Guid organizationPublicId,
            CancellationToken cancellationToken) => Task.FromResult(Organization);
    }

    private sealed class FakeFundingApplicationRepository : IFundingApplicationRepository
    {
        public bool ThrowNotFound { get; set; }
        public bool CreateReplay { get; set; }
        public string UpdateCode { get; set; } = "updated";
        public IReadOnlyList<FundingCalendarItem> CalendarItems { get; set; } = [];
        public int CreateCalls { get; private set; }
        public int CalendarCalls { get; private set; }
        public int TotalCalls { get; private set; }

        public Task<FundingApplicationPage> ListAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            FundingApplicationListFilters filters,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult(new FundingApplicationPage(
                [ApplicationDetails()], 1, filters.PageNumber, filters.PageSize));
        }

        public Task<FundingApplicationDetails?> GetAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingApplicationPublicId,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            if (ThrowNotFound)
            {
                throw new FundingApplicationDataException("get", 52101, new Exception());
            }

            return Task.FromResult<FundingApplicationDetails?>(ApplicationDetails());
        }

        public Task<FundingApplicationMutation> CreateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid fundingOpportunityPublicId,
            FundingApplicationData application,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            CreateCalls++;
            return Task.FromResult(Mutation(
                true,
                CreateReplay ? "replayed" : "created",
                CreateReplay));
        }

        public Task<FundingApplicationMutation> UpdateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingApplicationPublicId,
            byte[] expectedRowVersion,
            FundingApplicationData application,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult(Mutation(UpdateCode == "updated", UpdateCode));
        }

        public Task<IReadOnlyList<FundingCalendarItem>> ListCalendarAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            DateOnly from,
            DateOnly to,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            CalendarCalls++;
            return Task.FromResult(CalendarItems);
        }

        private static FundingApplicationMutation Mutation(
            bool succeeded,
            string code,
            bool wasReplay = false) => new(
            succeeded,
            code,
            ApplicationId,
            FundingApplicationStatus.Interested,
            UserId,
            [1, 2, 3, 4, 5, 6, 7, 8],
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            wasReplay);
    }
}
