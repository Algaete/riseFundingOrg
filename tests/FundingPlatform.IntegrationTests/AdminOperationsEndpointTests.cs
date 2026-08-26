using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Administration;
using FundingPlatform.Core.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class AdminOperationsEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly byte[] SigningKey = new byte[64];
    private readonly FakeRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public AdminOperationsEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IAdminOperationsRepository>();
                services.AddSingleton<IAdminOperationsRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("/api/v1/admin/organizations")]
    [InlineData("/api/v1/admin/operational-errors")]
    public async Task Lists_require_authenticated_admin_mfa(string path)
    {
        using var response = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(0, repository.Calls);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Organization_list_passes_bounded_filters_and_returns_safe_summary()
    {
        using var request = Request("/api/v1/admin/organizations?q=fundacion&profileStatus=2&isActive=true&page=2&pageSize=10");
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        Assert.Equal("fundacion", repository.OrganizationQuery?.Search);
        Assert.Equal((byte)2, repository.OrganizationQuery?.ProfileStatus);
        Assert.True(repository.OrganizationQuery?.IsActive);
        Assert.Equal(2, repository.OrganizationQuery?.Page);
        using var json = JsonDocument.Parse(body);
        var item = json.RootElement.GetProperty("items")[0];
        Assert.Equal("Fundación Segura", item.GetProperty("name").GetString());
        Assert.False(item.TryGetProperty("taxIdentifier", out _));
        Assert.False(item.TryGetProperty("annualBudgetMin", out _));
    }

    [Theory]
    [InlineData("?profileStatus=3")]
    [InlineData("?page=0")]
    [InlineData("?pageSize=51")]
    public async Task Organization_list_rejects_invalid_filters(string query)
    {
        using var response = await client.SendAsync(Request("/api/v1/admin/organizations" + query));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task Organization_detail_is_tenant_neutral_read_only_and_not_found_is_404()
    {
        using var response = await client.SendAsync(Request($"/api/v1/admin/organizations/{OrganizationId}"));
        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        using var json = JsonDocument.Parse(body);
        Assert.Equal(OrganizationId, json.RootElement.GetProperty("publicId").GetGuid());
        Assert.Equal(3, json.RootElement.GetProperty("memberCount").GetInt64());
        Assert.False(json.RootElement.TryGetProperty("taxIdentifier", out _));

        using var missing = await client.SendAsync(Request(
            "/api/v1/admin/organizations/cccccccc-cccc-cccc-cccc-cccccccccccc"));
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
    }

    [Fact]
    public async Task Operational_errors_are_sanitized_and_filters_are_allowlisted()
    {
        using var response = await client.SendAsync(Request(
            "/api/v1/admin/operational-errors?q=timeout&category=extraction&retryable=true&page=1&pageSize=10"));
        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        Assert.Equal("extraction", repository.ErrorQuery?.Category);
        Assert.True(repository.ErrorQuery?.Retryable);
        using var json = JsonDocument.Parse(body);
        var item = json.RootElement.GetProperty("items")[0];
        Assert.Equal("extraction-timeout", item.GetProperty("code").GetString());
        Assert.Equal("La extracción se reintentará.", item.GetProperty("message").GetString());
        Assert.False(item.TryGetProperty("rawPayload", out _));
        Assert.False(item.TryGetProperty("providerEventId", out _));

        using var invalid = await client.SendAsync(Request(
            "/api/v1/admin/operational-errors?category=credential"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, invalid.StatusCode);
    }

    [Fact]
    public void Endpoint_metadata_freezes_mfa_and_bounded_read_policy()
    {
        var routes = application.Services.GetRequiredService<EndpointDataSource>()
            .Endpoints.OfType<RouteEndpoint>().ToArray();
        foreach (var pattern in new[]
                 {
                     "/api/v1/admin/organizations",
                     "/api/v1/admin/organizations/{organizationId:guid}",
                     "/api/v1/admin/operational-errors"
                 })
        {
            var endpoint = Assert.Single(routes, candidate => candidate.RoutePattern.RawText == pattern);
            Assert.Equal("organization-activity-read",
                endpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
            Assert.Contains(endpoint.Metadata,
                metadata => metadata is Microsoft.AspNetCore.Authorization.AuthorizeAttribute
                    { Policy: "admin-mfa" });
        }
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage Request(string path)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new(ClaimTypes.Role, PlatformRoles.SuperAdmin),
            new("auth_level", "full"), new("amr", "mfa"),
            new("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
        };
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            JwtIssuer, JwtAudience, claims, now.AddMinutes(-1), now.AddMinutes(10),
            new SigningCredentials(new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512)));
    }

    private sealed class FakeRepository : IAdminOperationsRepository
    {
        public int Calls { get; private set; }
        public AdminOrganizationQuery? OrganizationQuery { get; private set; }
        public AdminOperationalErrorQuery? ErrorQuery { get; private set; }

        public Task<AdminOrganizationPage> ListOrganizationsAsync(Guid adminUserPublicId,
            AdminOrganizationQuery query, CancellationToken cancellationToken)
        {
            Calls++;
            OrganizationQuery = query;
            return Task.FromResult(new AdminOrganizationPage([Summary()], 1, query.Page, query.PageSize));
        }

        public Task<AdminOrganizationDetail?> GetOrganizationAsync(Guid adminUserPublicId,
            Guid organizationPublicId, CancellationToken cancellationToken)
        {
            Calls++;
            if (organizationPublicId != OrganizationId)
                return Task.FromResult<AdminOrganizationDetail?>(null);
            var summary = Summary();
            return Task.FromResult<AdminOrganizationDetail?>(new AdminOrganizationDetail(
                summary.PublicId, summary.Name, "Fundación Segura SpA", summary.CountryCode,
                summary.CountryName, summary.OrganizationTypeName, "Fundación", "Pequeña",
                2020, "https://example.test", "Descripción pública", summary.ProfileStatus,
                summary.ProfileCompleteness, 4, summary.IsActive, 3, 1, 2, 1,
                summary.PlanCode, summary.PlanName, summary.SubscriptionStatus, null,
                summary.CreatedAtUtc, summary.UpdatedAtUtc));
        }

        public Task<AdminOperationalErrorPage> ListOperationalErrorsAsync(Guid adminUserPublicId,
            AdminOperationalErrorQuery query, CancellationToken cancellationToken)
        {
            Calls++;
            ErrorQuery = query;
            return Task.FromResult(new AdminOperationalErrorPage([
                new AdminOperationalErrorItem("extraction:1", "extraction", 1,
                    "extraction-timeout", "La extracción se reintentará.", true,
                    DateTimeOffset.UtcNow, OrganizationId, "Documento oficial")
            ], 1, query.Page, query.PageSize));
        }

        private static AdminOrganizationSummary Summary() => new(
            OrganizationId, "Fundación Segura", "CL", "Chile", "Fundación", 2, 95,
            true, 3, 2, "FREE", "Free", null,
            new DateTimeOffset(2026, 8, 1, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 26, 12, 0, 0, TimeSpan.Zero));
    }
}
