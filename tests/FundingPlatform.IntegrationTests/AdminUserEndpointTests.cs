using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Core.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class AdminUserEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public AdminUserEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IAdminUserDirectoryRepository>();
                services.AddSingleton<IAdminUserDirectoryRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Fact]
    public async Task List_requires_an_authenticated_admin_mfa_session()
    {
        using var response = await client.GetAsync("/api/v1/admin/users");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.Calls);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData("Admin", false)]
    [InlineData("Professional", true)]
    public async Task List_requires_both_platform_admin_role_and_recent_mfa(
        string? role,
        bool mfa)
    {
        using var request = AuthenticatedRequest(role, mfa);
        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task List_returns_safe_user_summaries_and_passes_filters()
    {
        using var request = AuthenticatedRequest(PlatformRoles.SuperAdmin, mfa: true,
            "/api/v1/admin/users?q=alfonso&status=2&role=Admin&page=2&pageSize=10");
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        using var payload = JsonDocument.Parse(body);
        Assert.Equal(1, repository.Calls);
        Assert.Equal("alfonso", repository.Query?.Search);
        Assert.Equal(UserStatus.Active, repository.Query?.Status);
        Assert.Equal("Admin", repository.Query?.Role);
        Assert.Equal(2, repository.Query?.Page);
        Assert.Equal(10, repository.Query?.PageSize);
        var user = payload.RootElement.GetProperty("items")[0];
        Assert.Equal("admin@example.test", user.GetProperty("email").GetString());
        Assert.Equal("Active", user.GetProperty("status").GetString());
        Assert.True(user.GetProperty("mfaEnabled").GetBoolean());
        Assert.Equal("Admin", user.GetProperty("roles")[0].GetString());
        Assert.False(user.TryGetProperty("passwordHash", out _));
        Assert.False(user.TryGetProperty("securityStamp", out _));
    }

    [Theory]
    [InlineData("?status=9")]
    [InlineData("?page=0")]
    [InlineData("?pageSize=101")]
    public async Task List_rejects_invalid_filters_before_repository(string query)
    {
        using var request = AuthenticatedRequest(
            PlatformRoles.Admin, mfa: true, "/api/v1/admin/users" + query);
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True(response.StatusCode == HttpStatusCode.UnprocessableEntity, body);
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public void Endpoint_metadata_freezes_admin_mfa_and_bounded_read_rate()
    {
        var endpoint = Assert.Single(application.Services
            .GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>(), candidate =>
                candidate.RoutePattern.RawText == "/api/v1/admin/users");

        Assert.Equal("organization-activity-read",
            endpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        Assert.Contains(endpoint.Metadata,
            metadata => metadata is Microsoft.AspNetCore.Authorization.AuthorizeAttribute
                { Policy: "admin-mfa" });
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedRequest(
        string? role,
        bool mfa,
        string path = "/api/v1/admin/users")
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
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

    private sealed class FakeRepository : IAdminUserDirectoryRepository
    {
        public int Calls { get; private set; }
        public AdminUserDirectoryQuery? Query { get; private set; }

        public Task<AdminUserDirectoryPage> ListAsync(
            AdminUserDirectoryQuery query,
            CancellationToken cancellationToken)
        {
            Calls++;
            Query = query;
            return Task.FromResult(new AdminUserDirectoryPage(
                [new AdminUserDirectoryItem(
                    UserId,
                    "admin@example.test",
                    "Administradora",
                    "es-CL",
                    UserStatus.Active,
                    true,
                    true,
                    new DateTimeOffset(2026, 8, 26, 12, 0, 0, TimeSpan.Zero),
                    new DateTimeOffset(2026, 8, 1, 12, 0, 0, TimeSpan.Zero),
                    [PlatformRoles.Admin])],
                11,
                query.Page,
                query.PageSize));
        }
    }
}
