using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class Phase9AEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";

    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid RunId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static readonly Guid OpportunityId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeProjectMatchingRepository matching = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase9AEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProjectMatchingRepository>();
                services.AddSingleton<IProjectMatchingRepository>(matching);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/matching-runs")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/matching-runs")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/matching-runs/dddddddd-dddd-dddd-dddd-dddddddddddd")]
    public async Task Matching_routes_require_full_session_and_are_no_store(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, matching.TotalCalls);
    }

    [Fact]
    public async Task Create_requires_idempotency_and_returns_terminal_explainable_result()
    {
        using var missing = AuthenticatedRequest(
            HttpMethod.Post,
            MatchingRunsPath());
        using var missingResponse = await client.SendAsync(missing);

        Assert.Equal((HttpStatusCode)428, missingResponse.StatusCode);
        Assert.Equal(0, matching.CreateCalls);

        using var create = AuthenticatedRequest(HttpMethod.Post, MatchingRunsPath());
        create.Headers.Add("Idempotency-Key", "1234567890abcdef");
        using var response = await client.SendAsync(create);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.EndsWith($"/matching-runs/{RunId:D}", response.Headers.Location?.ToString());
        Assert.False(payload.RootElement.GetProperty("wasReplay").GetBoolean());
        var details = payload.RootElement.GetProperty("run");
        Assert.Equal((byte)MatchingRunStatus.Completed,
            details.GetProperty("run").GetProperty("status").GetByte());
        Assert.True(details.GetProperty("run").GetProperty("isCurrent").GetBoolean());
        Assert.Equal(200, details.GetProperty("run").GetProperty("candidateCount").GetInt32());
        Assert.Equal(230, details.GetProperty("run").GetProperty("totalCandidateCount").GetInt32());
        Assert.True(details.GetProperty("run").GetProperty("isTruncated").GetBoolean());
        var result = details.GetProperty("items")[0];
        Assert.Equal((byte)MatchingClassification.Incompatible,
            result.GetProperty("classification").GetByte());
        Assert.Equal(JsonValueKind.Null,
            result.GetProperty("compatibilityScore").ValueKind);
        Assert.Equal((byte)MatchingHardGateStatus.Fail,
            result.GetProperty("hardGateStatus").GetByte());
        Assert.Contains("no confirma elegibilidad",
            details.GetProperty("disclaimer").GetString(),
            StringComparison.OrdinalIgnoreCase);
        var json = payload.RootElement.GetRawText();
        Assert.DoesNotContain("taxIdentifier", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("email", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("notes", json, StringComparison.OrdinalIgnoreCase);

        matching.CreateReplay = true;
        using var replay = AuthenticatedRequest(HttpMethod.Post, MatchingRunsPath());
        replay.Headers.Add("Idempotency-Key", "1234567890abcdef");
        using var replayResponse = await client.SendAsync(replay);
        using var replayPayload = JsonDocument.Parse(await replayResponse.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, replayResponse.StatusCode);
        Assert.True(replayPayload.RootElement.GetProperty("wasReplay").GetBoolean());
    }

    [Fact]
    public async Task List_is_server_paged_and_marks_stale_runs_without_client_inference()
    {
        matching.Current = false;
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            MatchingRunsPath() + "?page=2&pageSize=10");
        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(2, payload.RootElement.GetProperty("pageNumber").GetInt32());
        Assert.Equal(10, payload.RootElement.GetProperty("pageSize").GetInt32());
        Assert.False(payload.RootElement.GetProperty("items")[0]
            .GetProperty("isCurrent").GetBoolean());
        Assert.Equal(1, matching.ListCalls);

        using var invalid = AuthenticatedRequest(
            HttpMethod.Get,
            MatchingRunsPath() + "?pageSize=51");
        using var invalidResponse = await client.SendAsync(invalid);

        Assert.Equal(HttpStatusCode.BadRequest, invalidResponse.StatusCode);
        Assert.Equal(1, matching.ListCalls);
    }

    [Fact]
    public async Task Foreign_tenant_and_missing_run_are_indistinguishable_safe_404()
    {
        matching.ThrowNotFound = true;
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"{MatchingRunsPath()}/{RunId:D}");
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain("tenant", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("membership", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("organization member", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Missing_active_profile_is_a_safe_service_unavailable()
    {
        matching.ThrowUnavailable = true;
        using var request = AuthenticatedRequest(HttpMethod.Post, MatchingRunsPath());
        request.Headers.Add("Idempotency-Key", "1234567890abcdef");
        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/project-matching-unavailable",
            problem.RootElement.GetProperty("type").GetString());
    }

    [Fact]
    public async Task Matching_rate_limit_is_per_user_and_auth_failures_do_not_consume_it()
    {
        for (var index = 0; index < 6; index++)
        {
            using var unauthorized = new HttpRequestMessage(
                HttpMethod.Post,
                MatchingRunsPath());
            using var unauthorizedResponse = await client.SendAsync(unauthorized);
            Assert.Equal(HttpStatusCode.Unauthorized, unauthorizedResponse.StatusCode);
        }

        for (var index = 0; index < 5; index++)
        {
            using var request = AuthenticatedRequest(HttpMethod.Post, MatchingRunsPath());
            request.Headers.Add("Idempotency-Key", $"rate-user-a-{index:0000}");
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        }

        using var limited = AuthenticatedRequest(HttpMethod.Post, MatchingRunsPath());
        limited.Headers.Add("Idempotency-Key", "rate-user-a-9999");
        using var limitedResponse = await client.SendAsync(limited);
        Assert.Equal(HttpStatusCode.TooManyRequests, limitedResponse.StatusCode);

        var secondUserId = Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff");
        using var secondUser = AuthenticatedRequest(
            HttpMethod.Post,
            MatchingRunsPath(),
            secondUserId);
        secondUser.Headers.Add("Idempotency-Key", "rate-user-b-0001");
        using var secondUserResponse = await client.SendAsync(secondUser);
        Assert.Equal(HttpStatusCode.Created, secondUserResponse.StatusCode);
    }

    [Fact]
    public async Task OpenApi_and_metadata_freeze_matching_routes_and_limits()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var paths = document.RootElement.GetProperty("paths");
        var collectionPath =
            "/api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs";
        var detailPath = collectionPath + "/{matchingRunId}";

        Assert.True(paths.GetProperty(collectionPath).TryGetProperty("get", out _));
        var post = paths.GetProperty(collectionPath).GetProperty("post");
        Assert.False(post.TryGetProperty("requestBody", out _));
        Assert.True(post.GetProperty("responses").TryGetProperty("201", out _));
        Assert.True(post.GetProperty("responses").TryGetProperty("428", out _));
        Assert.True(post.GetProperty("responses").TryGetProperty("503", out _));
        Assert.True(paths.GetProperty(detailPath).TryGetProperty("get", out _));

        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        var create = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText ==
                "/api/v1/organizations/{organizationId:guid}/projects/{projectId:guid}/matching-runs" &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("POST"));
        var list = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText ==
                "/api/v1/organizations/{organizationId:guid}/projects/{projectId:guid}/matching-runs" &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("GET"));
        Assert.Equal("matching-run-create",
            create.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Equal("organization-activity-read",
            list.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static string MatchingRunsPath() =>
        $"/api/v1/organizations/{OrganizationId:D}/projects/{ProjectId:D}/matching-runs";

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        Guid? userId = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            CreateJwt(userId ?? UserId));
        return request;
    }

    private static string CreateJwt(Guid userId)
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, userId.ToString("D")),
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

    private static ProjectMatchingRunDetails Details(bool current) => new(
        new ProjectMatchingRunSummary(
            RunId,
            new MatchingProjectReference(ProjectId, "agua-segura", "Agua segura"),
            MatchingRunStatus.Completed,
            "deterministic-v1",
            new MatchingProfileReference("project-deterministic", 1),
            3,
            4,
            200,
            0,
            200,
            0,
            230,
            true,
            current,
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 1, TimeSpan.Zero)),
        [
            new ProjectMatchingResult(
                new MatchingFundingOpportunityReference(
                    OpportunityId,
                    "fondo-agua",
                    "Fondo de agua",
                    "Fundación Global",
                    new DateOnly(2026, 12, 1),
                    null,
                    1,
                    7),
                MatchingClassification.Incompatible,
                null,
                100,
                MatchingHardGateStatus.Fail,
                current,
                [
                    new ProjectMatchingRuleResult(
                        "geography",
                        "Geografía",
                        true,
                        MatchingRuleOutcome.NoMatch,
                        MatchingDataState.Known,
                        0,
                        20,
                        0,
                        "geography.explicit_no_match",
                        new Dictionary<string, string?>(),
                        new MatchingRuleEvidence(
                            "versioned-snapshots",
                            "geography",
                            ["CL", "PE"]),
                        true)
                ])
        ]);

    private sealed class FakeProjectMatchingRepository : IProjectMatchingRepository
    {
        public bool CreateReplay { get; set; }
        public bool Current { get; set; } = true;
        public bool ThrowNotFound { get; set; }
        public bool ThrowUnavailable { get; set; }
        public int CreateCalls { get; private set; }
        public int ListCalls { get; private set; }
        public int TotalCalls { get; private set; }

        public Task<ProjectMatchingRunPage> ListRunsAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            ProjectMatchingRunListFilters filters,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            ListCalls++;
            if (ThrowNotFound)
            {
                throw new ProjectMatchingDataException("list", 52401, new Exception());
            }

            return Task.FromResult(new ProjectMatchingRunPage(
                [Details(Current).Run], 1, filters.PageNumber, filters.PageSize));
        }

        public Task<ProjectMatchingRunDetails?> GetRunAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid matchingRunPublicId,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            if (ThrowNotFound)
            {
                throw new ProjectMatchingDataException("get", 52401, new Exception());
            }

            return Task.FromResult<ProjectMatchingRunDetails?>(Details(Current));
        }

        public Task<ProjectMatchingRunMutation> CreateRunAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            CreateCalls++;
            if (ThrowUnavailable)
            {
                throw new ProjectMatchingDataException("create", 52404, new Exception());
            }

            return Task.FromResult(new ProjectMatchingRunMutation(
                true,
                CreateReplay ? "replayed" : "created",
                RunId,
                CreateReplay));
        }
    }
}
