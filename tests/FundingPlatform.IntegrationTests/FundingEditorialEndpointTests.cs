using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class FundingEditorialEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private const string CurrentETag = "\"0102030405060708\"";
    private const string NextETag = "\"A1A2A3A4A5A6A7A8\"";

    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid FunderId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid OpportunityId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeFunderRepository funders = new();
    private readonly FakeOpportunityEditorialRepository opportunities = new();
    private readonly FakeFundingSourceRepository sources = new();
    private readonly FakePublicOpportunityRepository publicOpportunities = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public FundingEditorialEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IFunderRepository>();
                services.RemoveAll<IFundingOpportunityEditorialRepository>();
                services.RemoveAll<IFundingSourceAdminRepository>();
                services.RemoveAll<IFundingOpportunityRepository>();
                services.AddSingleton<IFunderRepository>(funders);
                services.AddSingleton<IFundingOpportunityEditorialRepository>(opportunities);
                services.AddSingleton<IFundingSourceAdminRepository>(sources);
                services.AddSingleton<IFundingOpportunityRepository>(publicOpportunities);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/admin/funders")]
    [InlineData("POST", "/api/v1/admin/funders")]
    [InlineData("POST", "/api/v1/admin/funders/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/start-correction")]
    [InlineData("GET", "/api/v1/admin/funding-opportunities")]
    [InlineData("POST", "/api/v1/admin/funding-opportunities")]
    [InlineData("GET", "/api/v1/admin/funding-sources")]
    public async Task Editorial_admin_routes_reject_anonymous_requests(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, funders.Calls);
        Assert.Equal(0, opportunities.Calls);
        Assert.Equal(0, sources.Calls);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData(PlatformRoles.Admin, false)]
    [InlineData("OrganizationOwner", true)]
    public async Task Editorial_admin_routes_require_admin_role_and_MFA(
        string? role,
        bool mfaAuthenticated)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get, "/api/v1/admin/funders", role, mfaAuthenticated);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, funders.Calls);
    }

    [Fact]
    public async Task Editorial_admin_routes_reject_an_expired_MFA_session()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            "/api/v1/admin/funders",
            PlatformRoles.Admin,
            mfaAuthenticated: true,
            mfaAuthenticatedAtUtc: DateTimeOffset.UtcNow.AddMinutes(-61));

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, funders.Calls);
    }

    [Fact]
    public async Task Create_requires_an_idempotency_key_before_calling_the_service()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post, "/api/v1/admin/funders", PlatformRoles.Admin, true);
        request.Content = JsonContent.Create(new
        {
            name = "Fundación Ejemplo",
            description = "Financia iniciativas de impacto social.",
            websiteUrl = "https://example.org",
            countryId = 56,
            aliases = Array.Empty<string>()
        });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/idempotency-key-required",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(0, funders.CreateCalls);
    }

    [Theory]
    [InlineData(false, true, "if-match-required")]
    [InlineData(true, false, "idempotency-key-required")]
    public async Task Update_requires_ETag_and_idempotency_key(
        bool includeIfMatch,
        bool includeIdempotencyKey,
        string expectedProblemCode)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Put,
            $"/api/v1/admin/funders/{FunderId:D}",
            PlatformRoles.Admin,
            true);
        request.Content = JsonContent.Create(new
        {
            name = "Fundación Ejemplo",
            description = "Descripción vigente.",
            websiteUrl = "https://example.org",
            countryId = 56,
            aliases = Array.Empty<string>()
        });
        if (includeIfMatch) request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        if (includeIdempotencyKey)
            request.Headers.TryAddWithoutValidation("Idempotency-Key", "funder-update-0001");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(
            $"https://fundingplatform.local/problems/{expectedProblemCode}",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(0, funders.UpdateCalls);
    }

    [Fact]
    public async Task Create_returns_strong_ETag_and_non_cacheable_response()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post, "/api/v1/admin/funders", PlatformRoles.Admin, true);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "funder-create-0001");
        request.Content = JsonContent.Create(new
        {
            name = "Fundación Ejemplo",
            description = "Financia iniciativas de impacto social.",
            websiteUrl = "https://example.org",
            countryId = 56,
            aliases = new[] { "F. Ejemplo" }
        });

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(NextETag, response.Headers.GetValues("ETag").Single());
        Assert.Equal(NextETag, document.RootElement.GetProperty("eTag").GetString());
        Assert.Equal(FunderId, document.RootElement.GetProperty("entityId").GetGuid());
        Assert.Equal((byte)FundingPublicationStatus.Draft,
            document.RootElement.GetProperty("publicationStatus").GetByte());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(1, funders.CreateCalls);
        Assert.Equal(UserId, funders.LastAdminUserId);
    }

    [Fact]
    public async Task Concurrency_and_idempotency_conflicts_use_sanitized_stable_codes()
    {
        funders.UpdateResult = Mutation(false, "etag-conflict");
        using var concurrencyRequest = CreateFunderUpdateRequest("funder-update-0002");
        using var concurrencyResponse = await client.SendAsync(concurrencyRequest);
        using var concurrencyProblem = JsonDocument.Parse(
            await concurrencyResponse.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.PreconditionFailed, concurrencyResponse.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/funding-editorial-precondition-failed",
            concurrencyProblem.RootElement.GetProperty("type").GetString());
        Assert.DoesNotContain("SQL", concurrencyProblem.RootElement.GetRawText(),
            StringComparison.OrdinalIgnoreCase);

        funders.UpdateResult = Mutation(false, "idempotency-conflict");
        using var idempotencyRequest = CreateFunderUpdateRequest("funder-update-0003");
        using var idempotencyResponse = await client.SendAsync(idempotencyRequest);
        using var idempotencyProblem = JsonDocument.Parse(
            await idempotencyResponse.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Conflict, idempotencyResponse.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/idempotency-conflict",
            idempotencyProblem.RootElement.GetProperty("type").GetString());
    }

    [Fact]
    public async Task Start_correction_requires_headers_and_withdraws_published_content_to_draft()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/funders/{FunderId:D}/start-correction",
            PlatformRoles.Admin,
            true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "funder-correction-0001");
        request.Content = JsonContent.Create(new { reason = "  Corregir el enlace oficial.  " });

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(NextETag, response.Headers.GetValues("ETag").Single());
        Assert.Equal((byte)FundingPublicationStatus.Draft,
            document.RootElement.GetProperty("publicationStatus").GetByte());
        Assert.Equal("Corregir el enlace oficial.", funders.LastCorrectionReason);
        Assert.Equal(1, funders.CorrectionCalls);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Opportunity_readiness_issues_return_422_without_internal_details()
    {
        opportunities.RequestPublicationResult = new FundingEditorialMutation(
            false,
            "opportunity-not-ready",
            OpportunityId,
            FundingPublicationStatus.Draft,
            1,
            Convert.FromHexString("0102030405060708"),
            false,
            [
                new FundingReadinessIssue(
                    "country-required",
                    "/countryIds",
                    "Selecciona al menos un país elegible."),
                new FundingReadinessIssue(
                    "category-required",
                    "/categoryIds",
                    "Selecciona al menos una categoría.")
            ]);
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}/submit-review",
            PlatformRoles.Admin,
            true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "opportunity-review-0001");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/opportunity-not-ready",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(
            "Selecciona al menos un país elegible.",
            problem.RootElement.GetProperty("errors").GetProperty("/countryIds")[0].GetString());
        Assert.DoesNotContain("connection", problem.RootElement.GetRawText(),
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Opportunity_source_conflict_returns_actionable_field_errors()
    {
        opportunities.RequestPublicationResult = new FundingEditorialMutation(
            false,
            "source-link-conflict",
            OpportunityId,
            FundingPublicationStatus.Draft,
            1,
            Convert.FromHexString("0102030405060708"),
            false,
            []);
        using var request = AuthenticatedRequest(
            HttpMethod.Put,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}",
            PlatformRoles.Admin,
            true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation(
            "Idempotency-Key", "opportunity-source-conflict-0001");
        request.Content = JsonContent.Create(new
        {
            title = "Fondo para innovación social",
            sponsorName = "Fundación Ejemplo",
            funders = new[] { new { funderId = FunderId, role = 1 } },
            fundingSourceId = 7,
            externalId = "SOURCE-001",
            sourceUrl = "https://example.org/funds/source-001",
            geographicScope = 0,
            countryIds = Array.Empty<short>(),
            regionIds = Array.Empty<int>()
        });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/source-link-conflict",
            problem.RootElement.GetProperty("type").GetString());
        var errors = problem.RootElement.GetProperty("errors");
        Assert.True(errors.TryGetProperty("fundingSourceId", out _));
        Assert.True(errors.TryGetProperty("externalId", out _));
        Assert.True(errors.TryGetProperty("sourceUrl", out _));
        Assert.DoesNotContain("SQL", problem.RootElement.GetRawText(),
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Funding_source_options_are_admin_only_and_non_cacheable()
    {
        sources.Items = [new FundingSourceAdminOption(
            10, "Manual editorial", 0, null, true)];
        using var request = AuthenticatedRequest(
            HttpMethod.Get, "/api/v1/admin/funding-sources", PlatformRoles.Admin, true);

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal("Manual editorial", document.RootElement[0].GetProperty("name").GetString());
        Assert.Equal(1, sources.Calls);
    }

    [Fact]
    public async Task Public_catalogs_return_only_repository_publication_results_with_public_cache()
    {
        publicOpportunities.Published = new FundingOpportunityDetails(
            OpportunityId,
            "fondo-publicado",
            "Fondo publicado",
            "Descripción pública.",
            "Resumen público.",
            "Fundación Ejemplo",
            "https://example.org",
            "https://example.org/apply",
            "USD",
            1000m,
            5000m,
            new DateOnly(2026, 8, 1),
            new DateOnly(2026, 12, 1),
            "ONG elegibles.",
            null,
            null,
            false,
            "Manual editorial",
            "https://example.org/fondo",
            null,
            new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
            90m,
            [new FundingOpportunityFunder(
                FunderId, "fundacion-ejemplo", "Fundación Ejemplo",
                FunderOpportunityRole.Primary)]);

        using var publishedResponse = await client.GetAsync(
            "/api/v1/funding-opportunities/fondo-publicado");
        using var publishedDocument = JsonDocument.Parse(
            await publishedResponse.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, publishedResponse.StatusCode);
        Assert.True(publishedResponse.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(60), publishedResponse.Headers.CacheControl?.MaxAge);
        Assert.Equal(FunderId,
            publishedDocument.RootElement.GetProperty("funders")[0]
                .GetProperty("funderId").GetGuid());
        Assert.False(publishedDocument.RootElement.TryGetProperty("publicationStatus", out _));
        Assert.False(publishedDocument.RootElement.TryGetProperty("rowVersion", out _));

        publicOpportunities.Published = null;
        using var draftResponse = await client.GetAsync(
            "/api/v1/funding-opportunities/borrador-o-rechazado");
        Assert.Equal(HttpStatusCode.NotFound, draftResponse.StatusCode);

        funders.PublishedDetails = null;
        using var rejectedFunderResponse = await client.GetAsync(
            "/api/v1/funders/funder-rechazado");
        Assert.Equal(HttpStatusCode.NotFound, rejectedFunderResponse.StatusCode);
    }

    [Fact]
    public async Task Public_funder_success_is_cacheable()
    {
        funders.PublishedDetails = new PublicFunderDetails(
            FunderId,
            "fundacion-ejemplo",
            "Fundación Ejemplo",
            "Financiamiento social.",
            "https://example.org",
            "CL",
            "Chile",
            [],
            new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
            []);

        using var response = await client.GetAsync("/api/v1/funders/fundacion-ejemplo");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(60), response.Headers.CacheControl?.MaxAge);
    }

    [Fact]
    public async Task OpenApi_contains_every_phase_6_editorial_route()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var paths = document.RootElement.GetProperty("paths");
        var expected = new (string Path, string Method)[]
        {
            ("/api/v1/admin/funders", "get"),
            ("/api/v1/admin/funders", "post"),
            ("/api/v1/admin/funders/{funderId}", "get"),
            ("/api/v1/admin/funders/{funderId}", "put"),
            ("/api/v1/admin/funders/{funderId}/submit-review", "post"),
            ("/api/v1/admin/funders/{funderId}/reviews", "post"),
            ("/api/v1/admin/funders/{funderId}/start-correction", "post"),
            ("/api/v1/admin/funders/{funderId}/deactivate", "post"),
            ("/api/v1/admin/funding-opportunities", "get"),
            ("/api/v1/admin/funding-opportunities", "post"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}", "get"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}", "put"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}/submit-review", "post"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}/reviews", "post"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}/start-correction", "post"),
            ("/api/v1/admin/funding-opportunities/{opportunityId}/deactivate", "post"),
            ("/api/v1/admin/funding-sources", "get"),
            ("/api/v1/funders", "get"),
            ("/api/v1/funders/{slug}", "get"),
            ("/api/v1/funding-opportunities", "get"),
            ("/api/v1/funding-opportunities/{slug}", "get")
        };

        foreach (var (path, method) in expected)
        {
            Assert.True(paths.TryGetProperty(path, out var pathItem),
                $"OpenAPI is missing '{path}'.");
            Assert.True(pathItem.TryGetProperty(method, out _),
                $"OpenAPI path '{path}' is missing '{method}'.");
        }

        Assert.True(paths
            .GetProperty("/api/v1/admin/funders/{funderId}/start-correction")
            .GetProperty("post")
            .GetProperty("responses")
            .TryGetProperty("412", out _));

        Assert.True(document.RootElement.GetProperty("components").GetProperty("schemas")
            .GetProperty("OrganizationCatalogsResponse").GetProperty("properties")
            .TryGetProperty("fundingTypes", out _));

        var schemas = document.RootElement.GetProperty("components").GetProperty("schemas");
        var canonicalFields = new[]
        {
            "issuerCountryId", "fundingTypeId", "currency", "minimumAmount",
            "maximumAmount", "amountStatus", "openDate", "closeDate", "closeAtUtc",
            "deadlineTimeZoneId", "deadlineType", "deadlinePrecision",
            "eligibilityDescription", "requirements", "objectives", "allowedActivities",
            "excludedActivities", "restrictions", "targetOrganizationsDescription",
            "targetPopulationsDescription", "minimumOperatingYears", "requiresLegalEntity",
            "requiresPriorExperience", "requiresCofunding", "cofundingPercentage",
            "geographicScope", "remoteApplication", "lastVerifiedAtUtc", "countryIds",
            "regionIds", "categoryIds", "beneficiaryTypeIds", "projectTypeIds", "funders"
        };
        foreach (var schemaName in new[]
                 {
                     "FundingOpportunityWriteRequest",
                     "FundingOpportunityAdminDetailResponse"
                 })
        {
            var properties = schemas.GetProperty(schemaName).GetProperty("properties");
            foreach (var field in canonicalFields)
            {
                Assert.True(properties.TryGetProperty(field, out _),
                    $"OpenAPI schema '{schemaName}' is missing canonical field '{field}'.");
            }
        }
    }

    [Fact]
    public void Public_funding_catalogs_use_the_bounded_marketplace_read_policy()
    {
        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        foreach (var pattern in new[]
                 {
                     "/api/v1/funders/",
                     "/api/v1/funders/{slug}",
                     "/api/v1/funding-opportunities/",
                     "/api/v1/funding-opportunities/{slug}"
                 })
        {
            var endpoint = Assert.Single(endpoints, item => item.RoutePattern.RawText == pattern);
            Assert.Equal(
                "marketplace-read",
                endpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        }
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private HttpRequestMessage CreateFunderUpdateRequest(string idempotencyKey)
    {
        var request = AuthenticatedRequest(
            HttpMethod.Put,
            $"/api/v1/admin/funders/{FunderId:D}",
            PlatformRoles.Admin,
            true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", idempotencyKey);
        request.Content = JsonContent.Create(new
        {
            name = "Fundación Ejemplo",
            description = "Descripción vigente.",
            websiteUrl = "https://example.org",
            countryId = 56,
            aliases = Array.Empty<string>()
        });
        return request;
    }

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        string? role = null,
        bool mfaAuthenticated = false,
        DateTimeOffset? mfaAuthenticatedAtUtc = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateJwt(role, mfaAuthenticated, mfaAuthenticatedAtUtc));
        return request;
    }

    private static string CreateJwt(
        string? role,
        bool mfaAuthenticated,
        DateTimeOffset? mfaAuthenticatedAtUtc = null)
    {
        var now = DateTime.UtcNow;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new("auth_level", "full"),
            new("amr", mfaAuthenticated ? "mfa" : "pwd"),
            new("auth_time", (mfaAuthenticatedAtUtc ?? new DateTimeOffset(now))
                .ToUnixTimeSeconds().ToString())
        };
        if (!string.IsNullOrWhiteSpace(role)) claims.Add(new Claim(ClaimTypes.Role, role));

        var token = new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            claims,
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static FundingEditorialMutation Mutation(bool succeeded, string code) => new(
        succeeded,
        code,
        FunderId,
        FundingPublicationStatus.Draft,
        1,
        Convert.FromHexString(succeeded ? "A1A2A3A4A5A6A7A8" : "0102030405060708"),
        false,
        []);

    private sealed class FakeFunderRepository : IFunderRepository
    {
        public int Calls { get; private set; }
        public int CreateCalls { get; private set; }
        public int UpdateCalls { get; private set; }
        public int CorrectionCalls { get; private set; }
        public Guid LastAdminUserId { get; private set; }
        public string? LastCorrectionReason { get; private set; }
        public FundingEditorialMutation UpdateResult { get; set; } = Mutation(true, "updated");
        public FundingEditorialMutation CorrectionResult { get; set; } = new(
            true, "correction-started", FunderId, FundingPublicationStatus.Draft, 2,
            Convert.FromHexString("A1A2A3A4A5A6A7A8"), false, []);
        public PublicFunderDetails? PublishedDetails { get; set; }

        public Task<FunderPage> ListAdminAsync(
            Guid adminUserPublicId, string? query, FundingPublicationStatus? publicationStatus,
            bool includeInactive, int pageNumber, int pageSize,
            CancellationToken cancellationToken)
        {
            Calls++;
            LastAdminUserId = adminUserPublicId;
            return Task.FromResult(new FunderPage([], 0, pageNumber, pageSize));
        }

        public Task<FunderDetails?> GetAdminAsync(
            Guid adminUserPublicId, Guid funderPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult<FunderDetails?>(null);
        }

        public Task<FundingEditorialMutation> CreateAsync(
            Guid adminUserPublicId, string slug, FunderData data,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            Calls++;
            CreateCalls++;
            LastAdminUserId = adminUserPublicId;
            return Task.FromResult(Mutation(true, "created"));
        }

        public Task<FundingEditorialMutation> UpdateAsync(
            Guid adminUserPublicId, Guid funderPublicId, byte[] expectedRowVersion,
            FunderData data, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            Calls++;
            UpdateCalls++;
            LastAdminUserId = adminUserPublicId;
            return Task.FromResult(UpdateResult);
        }

        public Task<FundingEditorialMutation> RequestPublicationAsync(
            Guid adminUserPublicId, Guid funderPublicId, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(Mutation(true, "review-requested"));

        public Task<FundingEditorialMutation> ReviewAsync(
            Guid adminUserPublicId, Guid funderPublicId, FundingReviewDecision decision,
            string? reason, byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken) =>
            Task.FromResult(Mutation(true,
                decision == FundingReviewDecision.Approve ? "published" : "rejected"));

        public Task<FundingEditorialMutation> StartCorrectionAsync(
            Guid adminUserPublicId, Guid funderPublicId, string reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            Calls++;
            CorrectionCalls++;
            LastAdminUserId = adminUserPublicId;
            LastCorrectionReason = reason;
            return Task.FromResult(CorrectionResult);
        }

        public Task<FundingEditorialMutation> DeactivateAsync(
            Guid adminUserPublicId, Guid funderPublicId, string? reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(Mutation(true, "deactivated"));

        public Task<PublicFunderPage> ListPublishedAsync(
            string? query, int pageNumber, int pageSize, CancellationToken cancellationToken) =>
            Task.FromResult(new PublicFunderPage([], 0, pageNumber, pageSize));

        public Task<PublicFunderDetails?> GetPublishedBySlugAsync(
            string slug, CancellationToken cancellationToken) =>
            Task.FromResult(PublishedDetails);
    }

    private sealed class FakeOpportunityEditorialRepository : IFundingOpportunityEditorialRepository
    {
        public int Calls { get; private set; }
        public FundingEditorialMutation RequestPublicationResult { get; set; } = new(
            true,
            "review-requested",
            OpportunityId,
            FundingPublicationStatus.PendingReview,
            1,
            Convert.FromHexString("A1A2A3A4A5A6A7A8"),
            false,
            []);

        public Task<FundingOpportunityAdminPage> ListAdminAsync(
            Guid adminUserPublicId, string? query, FundingPublicationStatus? publicationStatus,
            bool includeInactive, int pageNumber, int pageSize,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new FundingOpportunityAdminPage([], 0, pageNumber, pageSize));
        }

        public Task<FundingOpportunityAdminDetails?> GetAdminAsync(
            Guid adminUserPublicId, Guid opportunityPublicId,
            CancellationToken cancellationToken) =>
            Task.FromResult<FundingOpportunityAdminDetails?>(null);

        public Task<FundingEditorialMutation> CreateAsync(
            Guid adminUserPublicId, string slug, FundingOpportunityEditorialData data,
            string snapshotJson, byte[] contentHash, decimal dataQualityScore,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestPublicationResult);

        public Task<FundingEditorialMutation> UpdateAsync(
            Guid adminUserPublicId, Guid opportunityPublicId, byte[] expectedRowVersion,
            FundingOpportunityEditorialData data, string snapshotJson, byte[] contentHash,
            decimal dataQualityScore, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestPublicationResult);

        public Task<FundingEditorialMutation> RequestPublicationAsync(
            Guid adminUserPublicId, Guid opportunityPublicId, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(RequestPublicationResult);
        }

        public Task<FundingEditorialMutation> ReviewAsync(
            Guid adminUserPublicId, Guid opportunityPublicId,
            FundingReviewDecision decision, string? reason, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestPublicationResult);

        public Task<FundingEditorialMutation> StartCorrectionAsync(
            Guid adminUserPublicId, Guid opportunityPublicId, string reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestPublicationResult);

        public Task<FundingEditorialMutation> DeactivateAsync(
            Guid adminUserPublicId, Guid opportunityPublicId, string? reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestPublicationResult);
    }

    private sealed class FakeFundingSourceRepository : IFundingSourceAdminRepository
    {
        public int Calls { get; private set; }
        public IReadOnlyList<FundingSourceAdminOption> Items { get; set; } = [];

        public Task<IReadOnlyList<FundingSourceAdminOption>> ListAsync(
            Guid adminUserPublicId, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(Items);
        }
    }

    private sealed class FakePublicOpportunityRepository : IFundingOpportunityRepository
    {
        public FundingOpportunityDetails? Published { get; set; }

        public Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
            int expectedFundingSourceId, string expectedProviderCode,
            ExternalFundingOpportunity opportunity,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<FundingOpportunityPage> SearchPublishedAsync(
            string? query, int pageNumber, int pageSize,
            CancellationToken cancellationToken) =>
            Task.FromResult(new FundingOpportunityPage([], 0, pageNumber, pageSize));

        public Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(
            string slug, CancellationToken cancellationToken) => Task.FromResult(Published);
    }
}
