using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Identity;
using FundingPlatform.Core.Semantics;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class Phase9BEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid RunId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeEvaluationRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase9BEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ISemanticEvaluationRepository>();
                services.RemoveAll<SemanticProcessingPolicy>();
                services.AddSingleton<ISemanticEvaluationRepository>(repository);
                services.AddSingleton(Policy(enabled: true));
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/admin/semantic-evaluation-runs")]
    [InlineData("POST", "/api/v1/admin/semantic-evaluation-runs")]
    [InlineData("GET", "/api/v1/admin/semantic-evaluation-runs/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")]
    [InlineData("GET", "/api/v1/admin/semantic-evaluation-runs/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/report")]
    public async Task Routes_require_an_authenticated_admin_mfa_session(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.TotalCalls);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData("Admin", false)]
    [InlineData("OrganizationOwner", true)]
    public async Task Routes_require_both_platform_admin_role_and_recent_mfa(
        string? role,
        bool mfa)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get, "/api/v1/admin/semantic-evaluation-runs", role, mfa);
        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Create_requires_idempotency_before_persistence()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            "/api/v1/admin/semantic-evaluation-runs",
            PlatformRoles.Admin,
            mfa: true);
        request.Content = JsonContent.Create(new
        {
            evalSetVersion = "quality-gate-v1",
            semanticConfigurationVersion = "development-shadow-v1"
        });

        using var response = await client.SendAsync(request);

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Create_is_shadow_only_idempotent_and_never_accepts_provider_selection()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            "/api/v1/admin/semantic-evaluation-runs",
            PlatformRoles.SuperAdmin,
            mfa: true);
        request.Headers.Add("Idempotency-Key", "semantic-eval-0001");
        request.Content = JsonContent.Create(new
        {
            evalSetVersion = "quality-gate-v1",
            semanticConfigurationVersion = "development-shadow-v1"
        });

        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        using var payload = JsonDocument.Parse(json);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.EndsWith($"/{RunId:D}", response.Headers.Location?.ToString());
        Assert.False(payload.RootElement.GetProperty("wasReplay").GetBoolean());
        Assert.Equal(1, repository.CreateCalls);
        Assert.True(repository.RuntimeEnabled);
        Assert.Equal("quality-gate-v1", repository.EvaluationSetVersion);
        Assert.Equal("development-shadow-v1", repository.ConfigurationVersion);
        Assert.DoesNotContain("canonicalText", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("prompt", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("inputContentHash", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Budget_exhaustion_has_a_stable_non_active_run_problem_code()
    {
        repository.CreateCode = "budget-insufficient";
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            "/api/v1/admin/semantic-evaluation-runs",
            PlatformRoles.Admin,
            mfa: true);
        request.Headers.Add("Idempotency-Key", "semantic-budget-01");
        request.Content = JsonContent.Create(new
        {
            evalSetVersion = "quality-gate-v1",
            semanticConfigurationVersion = "development-shadow-v1"
        });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/semantic-budget-insufficient",
            problem.RootElement.GetProperty("type").GetString());
    }

    [Fact]
    public async Task Detail_exposes_only_aggregate_shadow_metrics_and_safe_job_counts()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/admin/semantic-evaluation-runs/{RunId:D}",
            PlatformRoles.Admin,
            mfa: true);
        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("modo sombra", json, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("normalizedDiscountedCumulativeGainAt10", json,
            StringComparison.Ordinal);
        Assert.Contains("coveragePercentage", json, StringComparison.Ordinal);
        Assert.Contains("providerSuccessPercentage", json, StringComparison.Ordinal);
        Assert.Contains("\"meetsPromotionGate\":false", json, StringComparison.Ordinal);
        Assert.Contains("rejectedInputEmbeddingJobCount", json,
            StringComparison.Ordinal);
        Assert.DoesNotContain("canonicalText", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("email", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("taxIdentifier", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Report_uses_distinct_safe_dataset_split_aggregates()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/admin/semantic-evaluation-runs/{RunId:D}/report",
            PlatformRoles.Admin,
            mfa: true);
        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        using var payload = JsonDocument.Parse(json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var splits = payload.RootElement.GetProperty("splits");
        Assert.Equal(2, splits.GetArrayLength());
        Assert.Equal(0, splits[0].GetProperty("datasetSplit").GetByte());
        Assert.Equal(JsonValueKind.Null, splits[0].GetProperty("recallAt10").ValueKind);
        Assert.Equal(1, splits[1].GetProperty("datasetSplit").GetByte());
        Assert.Equal(180, splits[1].GetProperty("pairCount").GetInt64());
        Assert.Equal(300, splits.EnumerateArray()
            .Sum(split => split.GetProperty("pairCount").GetInt64()));
        Assert.Equal(.9m, splits[1].GetProperty("recallAt10").GetDecimal());
        Assert.Contains("modo sombra", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("embeddingJobCount", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("casePublicId", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("canonical", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("vector", json, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(0, repository.GetCalls);
        Assert.Equal(1, repository.ReportCalls);
    }

    [Fact]
    public void Endpoint_metadata_freezes_admin_mfa_and_bounded_create_rate()
    {
        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        var create = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText?.TrimEnd('/').EndsWith(
                "api/v1/admin/semantic-evaluation-runs", StringComparison.Ordinal) == true &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("POST"));

        Assert.Equal("semantic-evaluation-create",
            create.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Contains(create.Metadata,
            metadata => metadata is Microsoft.AspNetCore.Authorization.AuthorizeAttribute
                { Policy: "admin-mfa" });
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        string? role,
        bool mfa)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateJwt(role, mfa));
        return request;
    }

    private static string CreateJwt(string? role, bool mfa)
    {
        var now = DateTime.UtcNow;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new("auth_level", "full"),
            new("amr", mfa ? "mfa" : "pwd"),
            new("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
        };
        if (!string.IsNullOrWhiteSpace(role)) claims.Add(new Claim(ClaimTypes.Role, role));
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            claims,
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512)));
    }

    private static SemanticProcessingPolicy Policy(bool enabled) => new(
        enabled, true, 1536, 8, TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30),
        3, 8192, "matching", "project-semantic-v1", "opportunity-semantic-v1",
        "semantic-text-v1", "cosine-linear-shadow-v1");

    private static SemanticEvaluationRunSummary Run() => new(
        RunId,
        SemanticEvaluationRunStatus.Completed,
        "quality-gate-v1",
        "development-shadow-v1",
        "development-deterministic",
        "lexical-hash-1536-v1",
        1536,
        "matching",
        "semantic-text-v1",
        30,
        100,
        300,
        30,
        300,
        300,
        new SemanticEvaluationMetrics(
            100m, 100m, .9m, .8m, .7m, .1m, .75m, 3m, 0m, 12, 0, false),
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 24, 12, 0, 1, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 24, 12, 0, 2, TimeSpan.Zero),
        null);

    private sealed class FakeEvaluationRepository : ISemanticEvaluationRepository
    {
        public int CreateCalls { get; private set; }
        public int TotalCalls { get; private set; }
        public int GetCalls { get; private set; }
        public int ReportCalls { get; private set; }
        public bool RuntimeEnabled { get; private set; }
        public string? EvaluationSetVersion { get; private set; }
        public string? ConfigurationVersion { get; private set; }
        public string CreateCode { get; set; } = "created";

        public Task<SemanticEvaluationRunMutation> CreateAsync(
            Guid adminUserPublicId,
            string evaluationSetVersion,
            string semanticConfigurationVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            bool runtimeEnabled,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            CreateCalls++;
            RuntimeEnabled = runtimeEnabled;
            EvaluationSetVersion = evaluationSetVersion;
            ConfigurationVersion = semanticConfigurationVersion;
            return Task.FromResult(new SemanticEvaluationRunMutation(
                CreateCode == "created",
                CreateCode,
                CreateCode == "created" ? Run() : null,
                false));
        }

        public Task<SemanticEvaluationRunPage> ListAsync(
            Guid adminUserPublicId,
            int page,
            int pageSize,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult(new SemanticEvaluationRunPage(
                [Run()], 1, page, pageSize));
        }

        public Task<SemanticEvaluationRunDetail?> GetAsync(
            Guid adminUserPublicId,
            Guid runPublicId,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            GetCalls++;
            return Task.FromResult<SemanticEvaluationRunDetail?>(new(
                Run(), 0, 0, 129, 0, 0, 0, 1));
        }

        public Task<SemanticEvaluationRunReport?> GetReportAsync(
            Guid adminUserPublicId,
            Guid runPublicId,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            ReportCalls++;
            return Task.FromResult<SemanticEvaluationRunReport?>(new(
                Run(),
                [
                    new SemanticEvaluationSplitReport(
                        0, 120, 120, 120, 40, 100m,
                        null, null, null, null, null, null),
                    new SemanticEvaluationSplitReport(
                        1, 180, 180, 180, 80, 100m,
                        .9m, .8m, .7m, .1m, .75m, 3m)
                ]));
        }
    }
}
