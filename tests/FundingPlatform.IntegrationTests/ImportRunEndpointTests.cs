using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Identity;
using FundingPlatform.Core.Imports;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class ImportRunEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid RunId = Guid.Parse("71717171-7171-7171-7171-717171717171");
    private static readonly DateTimeOffset CreatedAt =
        new(2026, 8, 22, 12, 0, 0, TimeSpan.Zero);

    private readonly FakeImportRunService service = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public ImportRunEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IImportRunService>();
                services.AddSingleton<IImportRunService>(service);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/admin/import-runs")]
    [InlineData("GET", "/api/v1/admin/import-runs/71717171-7171-7171-7171-717171717171")]
    [InlineData("POST", "/api/v1/admin/funding-sources/1/import-runs")]
    public async Task Import_routes_require_an_admin_session_with_recent_MFA(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, service.Calls);
    }

    [Fact]
    public async Task Create_requires_an_idempotency_key()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post, "/api/v1/admin/funding-sources/1/import-runs");
        request.Content = JsonContent.Create(new { keyword = "health", maximumResults = 10 });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.EndsWith("/idempotency-key-required",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(0, service.CreateCalls);
    }

    [Fact]
    public async Task Create_returns_202_location_and_a_stable_replay_identifier()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post, "/api/v1/admin/funding-sources/1/import-runs");
        request.Headers.TryAddWithoutValidation(
            "Idempotency-Key", "phase7a-manual-import-0001");
        request.Content = JsonContent.Create(new { keyword = "health", maximumResults = 10 });

        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Equal($"/api/v1/admin/import-runs/{RunId:D}",
            response.Headers.Location?.OriginalString);
        Assert.Equal(RunId, payload.RootElement.GetProperty("runId").GetGuid());
        Assert.Equal((byte)ImportRunStatus.Queued,
            payload.RootElement.GetProperty("status").GetByte());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal("health", service.LastKeyword);
        Assert.Equal(10, service.LastMaximumResults);
    }

    [Fact]
    public async Task List_rejects_unknown_status_with_field_validation()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get, "/api/v1/admin/import-runs?status=99");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.True(problem.RootElement.GetProperty("errors").TryGetProperty("status", out _));
        Assert.Equal(0, service.ListCalls);
    }

    [Fact]
    public async Task Detail_returns_only_safe_operational_fields()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get, $"/api/v1/admin/import-runs/{RunId:D}");

        using var response = await client.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        using var payload = JsonDocument.Parse(json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Grants.gov", payload.RootElement.GetProperty("sourceName").GetString());
        Assert.Equal("provider-timeout",
            payload.RootElement.GetProperty("errors")[0].GetProperty("code").GetString());
        Assert.DoesNotContain("rawContent", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("payloadJson", json, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
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
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new Claim(ClaimTypes.Role, PlatformRoles.Admin),
            new Claim("auth_level", "full"),
            new Claim("amr", "mfa"),
            new Claim("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
        };
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

    private sealed class FakeImportRunService : IImportRunService
    {
        public int Calls { get; private set; }
        public int CreateCalls { get; private set; }
        public int ListCalls { get; private set; }
        public string? LastKeyword { get; private set; }
        public int LastMaximumResults { get; private set; }

        public Task<ImportRunResult<ImportRunAccepted>> CreateManualAsync(
            Guid adminUserPublicId,
            int fundingSourceId,
            string keyword,
            int maximumResults,
            string idempotencyKey,
            string correlationId,
            CancellationToken cancellationToken)
        {
            Calls++;
            CreateCalls++;
            LastKeyword = keyword;
            LastMaximumResults = maximumResults;
            return Task.FromResult(new ImportRunResult<ImportRunAccepted>(
                ImportRunOutcome.Success,
                new ImportRunAccepted(
                    RunId, fundingSourceId, "Grants.gov", ImportRunStatus.Queued,
                    CreatedAt, false)));
        }

        public Task<ImportRunResult<ImportRunPage>> ListAsync(
            Guid adminUserPublicId,
            int? fundingSourceId,
            ImportRunStatus? status,
            int page,
            int pageSize,
            CancellationToken cancellationToken)
        {
            Calls++;
            ListCalls++;
            return Task.FromResult(new ImportRunResult<ImportRunPage>(
                ImportRunOutcome.Success,
                new ImportRunPage([], 0, page, pageSize)));
        }

        public Task<ImportRunResult<ImportRunDetail>> GetAsync(
            Guid adminUserPublicId,
            Guid runId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ImportRunResult<ImportRunDetail>(
                ImportRunOutcome.Success,
                new ImportRunDetail(
                    runId,
                    1,
                    "Grants.gov",
                    "grants-gov",
                    ImportTriggerType.Manual,
                    ImportRunStatus.Partial,
                    "health",
                    10,
                    2,
                    1,
                    0,
                    0,
                    1,
                    1,
                    1,
                    CreatedAt,
                    CreatedAt.AddSeconds(1),
                    CreatedAt.AddSeconds(5),
                    "provider-timeout",
                    [new ImportRunItem(
                        Guid.Parse("72727272-7272-7272-7272-727272727272"),
                        Guid.Parse("73737373-7373-7373-7373-737373737373"),
                        null,
                        "external-1",
                        ImportRunItemStatus.Failed,
                        "provider-timeout",
                        CreatedAt,
                        CreatedAt.AddSeconds(4))],
                    [new ImportRunError(
                        Guid.Parse("74747474-7474-7474-7474-747474747474"),
                        null,
                        "provider",
                        "provider-timeout",
                        "La fuente oficial no respondió a tiempo.",
                        true,
                        CreatedAt.AddSeconds(4))])));
        }
    }
}
