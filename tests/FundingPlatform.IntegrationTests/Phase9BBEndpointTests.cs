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

public sealed class Phase9BBEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid SourceRunId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid RunId =
        Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly byte[] SigningKey = new byte[64];
    private readonly FakeRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase9BBEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IAiExplanationAdministrationRepository>();
                services.RemoveAll<AiExplanationProcessingPolicy>();
                services.AddSingleton<IAiExplanationAdministrationRepository>(repository);
                services.AddSingleton(new AiExplanationProcessingPolicy(
                    true, 1, TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(1)));
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("POST", "/api/v1/admin/semantic-explanation-runs")]
    [InlineData("GET", "/api/v1/admin/semantic-explanation-runs/cccccccc-cccc-cccc-cccc-cccccccccccc")]
    public async Task Explanation_routes_require_admin_mfa_and_are_no_store(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Create_requires_idempotency_before_SQL()
    {
        using var request = Authenticated(HttpMethod.Post,
            "/api/v1/admin/semantic-explanation-runs");
        request.Content = JsonContent.Create(new
        {
            sourceSemanticEvaluationRunPublicId = SourceRunId,
            explanationConfigurationVersion = "explanation-shadow-v1"
        });

        using var response = await client.SendAsync(request);

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Create_is_admin_only_shadow_and_exposes_no_provider_input()
    {
        using var request = Authenticated(HttpMethod.Post,
            "/api/v1/admin/semantic-explanation-runs");
        request.Headers.Add("Idempotency-Key", "explanation-request-0001");
        request.Content = JsonContent.Create(new
        {
            sourceSemanticEvaluationRunPublicId = SourceRunId,
            explanationConfigurationVersion = "explanation-shadow-v1"
        });

        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.EndsWith($"/{RunId:D}", response.Headers.Location?.ToString());
        Assert.True(repository.RuntimeEnabled);
        Assert.DoesNotContain("canonical", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("prompt", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("responseSchema", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("providerRequest", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Detail_returns_only_safe_bounded_results_and_disclaimer()
    {
        using var request = Authenticated(HttpMethod.Get,
            $"/api/v1/admin/semantic-explanation-runs/{RunId:D}?page=1&pageSize=25");

        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        using var payload = JsonDocument.Parse(json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("modo sombra", json, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("signals-aligned",
            payload.RootElement.GetProperty("results")[0]
                .GetProperty("primaryReasonCode").GetString());
        Assert.DoesNotContain("email", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("taxIdentifier", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("inputContentHash", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Endpoint_metadata_freezes_mfa_and_bounded_write_rate()
    {
        var endpoints = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        var create = Assert.Single(endpoints, endpoint =>
            endpoint.RoutePattern.RawText?.TrimEnd('/').EndsWith(
                "api/v1/admin/semantic-explanation-runs", StringComparison.Ordinal) == true &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods.Contains("POST"));

        Assert.Equal("semantic-evaluation-create",
            create.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Contains(create.Metadata,
            metadata => metadata is Microsoft.AspNetCore.Authorization.AuthorizeAttribute
                { Policy: "admin-mfa" });
    }

    private static HttpRequestMessage Authenticated(HttpMethod method, string path)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        Claim[] claims =
        [
            new(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new(ClaimTypes.Role, PlatformRoles.Admin),
            new("auth_level", "full"),
            new("amr", "mfa"),
            new("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
        ];
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            "https://testing.fundingplatform.local",
            "FundingPlatform.Tests",
            claims,
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512)));
    }

    private static AiExplanationRunSummary Run() => new(
        RunId,
        SourceRunId,
        AiExplanationRunStatus.Completed,
        "explanation-shadow-v1",
        "openai",
        "gpt-5.6-sol",
        1,
        1,
        0,
        0.0004m,
        new DateTimeOffset(2026, 8, 25, 17, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 25, 17, 0, 2, TimeSpan.Zero));

    private sealed class FakeRepository : IAiExplanationAdministrationRepository
    {
        public int TotalCalls { get; private set; }
        public bool RuntimeEnabled { get; private set; }

        public Task<(bool Succeeded, string Code, bool WasReplay, AiExplanationRunSummary? Run)>
            CreateAsync(
                Guid adminUserPublicId,
                Guid sourceSemanticEvaluationRunPublicId,
                string explanationConfigurationVersion,
                byte[] idempotencyKeyHash,
                byte[] requestHash,
                bool runtimeEnabled,
                DateTimeOffset nowUtc,
                CancellationToken cancellationToken)
        {
            TotalCalls++;
            RuntimeEnabled = runtimeEnabled;
            return Task.FromResult((true, "created", false, (AiExplanationRunSummary?)Run()));
        }

        public Task<AiExplanationRunDetail?> GetAsync(
            Guid adminUserPublicId,
            Guid runPublicId,
            int page,
            int pageSize,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult<AiExplanationRunDetail?>(new(
                Run(),
                1,
                page,
                pageSize,
                [new AiExplanationResultItem(
                    1,
                    AiExplanationAssessment.Aligned,
                    "Las señales acotadas se encuentran alineadas.",
                    "signals-aligned",
                    ["categories", "geography"],
                    100,
                    20,
                    0.0004m,
                    250,
                    new DateTimeOffset(2026, 8, 25, 17, 0, 1, TimeSpan.Zero))]));
        }
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }
}
