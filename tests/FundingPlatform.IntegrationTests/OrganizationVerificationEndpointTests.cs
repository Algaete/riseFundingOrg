using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Identity;
using FundingPlatform.Core.Organizations;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class OrganizationVerificationEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private static readonly Guid Admin = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid Organization = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private const string Route = "/api/v1/admin/organizations/{organizationId:guid}/verification";
    private static readonly string Path = $"/api/v1/admin/organizations/{Organization}/verification";
    private readonly FakeRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public OrganizationVerificationEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IOrganizationVerificationRepository>();
            services.AddSingleton<IOrganizationVerificationRepository>(repository);
        }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
    }

    [Theory]
    [InlineData("GET")]
    [InlineData("POST")]
    public async Task Anonymous_cannot_read_or_decide(string method)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), Path);
        if (method == "POST") request.Content = JsonContent.Create(ValidDecision());
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(0, repository.Calls);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Theory]
    [InlineData("GET", "Member", true)]
    [InlineData("POST", "Member", true)]
    [InlineData("GET", "Admin", false)]
    [InlineData("POST", "Admin", false)]
    public async Task Both_routes_require_platform_admin_and_mfa(string method, string role, bool mfa)
    {
        using var request = Request(method, role: role, mfa: mfa);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }

    [Theory]
    [InlineData("GET")]
    [InlineData("POST")]
    public async Task Stale_admin_mfa_cannot_access_verification(string method)
    {
        using var request = Request(method, authenticationAgeMinutes: 1440);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task Read_returns_independent_pending_state_and_non_null_history()
    {
        using var response = await client.SendAsync(Request("GET"));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var value = json.RootElement;
        Assert.Equal(Organization, value.GetProperty("organizationPublicId").GetGuid());
        Assert.Equal(0, value.GetProperty("status").GetByte());
        Assert.Equal(0, value.GetProperty("revision").GetInt32());
        Assert.Equal(4, value.GetProperty("profileVersion").GetInt32());
        Assert.Equal(JsonValueKind.Null, value.GetProperty("reviewedAtUtc").ValueKind);
        Assert.Empty(value.GetProperty("history").EnumerateArray());
        Assert.False(value.TryGetProperty("taxIdentifier", out _));
        Assert.False(value.TryGetProperty("profileStatus", out _));
    }

    [Fact]
    public async Task Stale_verified_record_reads_as_pending_preserving_audit()
    {
        repository.Snapshot = Snapshot() with { Status = 1, RecordedStatus = 1,
            ReviewedProfileVersion = 3, Reason = "Antecedentes verificados.", Revision = 1 };
        using var response = await client.SendAsync(Request("GET"));
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(0, json.RootElement.GetProperty("status").GetByte());
        Assert.Equal(1, json.RootElement.GetProperty("recordedStatus").GetByte());
        Assert.True(json.RootElement.GetProperty("needsReverification").GetBoolean());
        Assert.Equal("Antecedentes verificados.", json.RootElement.GetProperty("reason").GetString());
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    public async Task Decision_uses_authenticated_actor_and_returns_new_snapshot_with_audit(int status)
    {
        var forgedActor = Guid.NewGuid();
        using var request = Request("POST", body: new { status, reason = "  Revisión manual confirmada.  ",
            expectedRevision = 0, expectedProfileVersion = 4, adminUserPublicId = forgedActor });
        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        Assert.Equal(Admin, repository.Actor);
        Assert.Equal(Organization, repository.OrganizationId);
        Assert.Equal(new(status, "Revisión manual confirmada.", 0, 4), repository.Decision);
        using var json = JsonDocument.Parse(body);
        Assert.Equal(status, json.RootElement.GetProperty("status").GetInt32());
        Assert.Equal(1, json.RootElement.GetProperty("revision").GetInt32());
        var history = Assert.Single(json.RootElement.GetProperty("history").EnumerateArray());
        Assert.Equal(Admin, history.GetProperty("reviewedByUserPublicId").GetGuid());
        Assert.Equal("Administración", history.GetProperty("reviewedByName").GetString());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Theory]
    [InlineData(-1, "Revisión manual.", 0, 4, "status")]
    [InlineData(3, "Revisión manual.", 0, 4, "status")]
    [InlineData(1, "abcd", 0, 4, "reason")]
    [InlineData(0, "   ", 0, 4, "reason")]
    [InlineData(2, null, 0, 4, "reason")]
    [InlineData(1, "Revisión manual.", -1, 4, "expectedRevision")]
    [InlineData(1, "Revisión manual.", int.MaxValue, 4, "expectedRevision")]
    [InlineData(1, "Revisión manual.", 0, 0, "expectedProfileVersion")]
    public async Task Invalid_decision_returns_field_errors_without_repository_call(
        int status, string? reason, int expectedRevision, int expectedProfileVersion, string field)
    {
        using var response = await client.SendAsync(Request("POST", body: new
            { status, reason, expectedRevision, expectedProfileVersion }));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(0, repository.Calls);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.True(json.RootElement.GetProperty("errors").TryGetProperty(field, out _));
        Assert.True(json.RootElement.GetProperty("validationIssues").TryGetProperty(field, out _));
    }

    [Fact]
    public async Task Omitted_numeric_fields_do_not_silently_reset_pending()
    {
        using var response = await client.SendAsync(Request("POST", body: new { reason = "Revisión manual." }));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(0, repository.Calls);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var errors = json.RootElement.GetProperty("errors");
        Assert.True(errors.TryGetProperty("status", out _));
        Assert.True(errors.TryGetProperty("expectedRevision", out _));
        Assert.True(errors.TryGetProperty("expectedProfileVersion", out _));
    }

    [Fact]
    public async Task Overlong_reason_is_not_truncated_and_saved()
    {
        using var response = await client.SendAsync(Request("POST", body: new
            { status = 1, reason = new string('x', 2001), expectedRevision = 0, expectedProfileVersion = 4 }));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task Missing_organization_read_returns_404()
    {
        repository.Snapshot = null;
        using var response = await client.SendAsync(Request("GET"));
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Theory]
    [InlineData(51601, 403)]
    [InlineData(51602, 403)]
    [InlineData(56301, 404)]
    [InlineData(56302, 409)]
    [InlineData(56303, 422)]
    [InlineData(-2, 503)]
    [InlineData(208, 503)]
    public async Task Database_failures_are_sanitized_and_mapped(int errorNumber, int httpStatus)
    {
        repository.FailureNumber = errorNumber;
        using var response = await client.SendAsync(Request("POST"));
        Assert.Equal(httpStatus, (int)response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("private SQL", body);
        Assert.DoesNotContain("server.example", body);
        Assert.Equal(1, repository.Calls);
    }

    [Fact]
    public void Endpoint_metadata_keeps_review_private_and_rate_limited()
    {
        var endpoints = application.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .OfType<RouteEndpoint>().Where(endpoint => endpoint.RoutePattern.RawText?.TrimEnd('/') == Route).ToArray();
        Assert.Equal(2, endpoints.Length);
        foreach (var endpoint in endpoints)
        {
            Assert.Contains(endpoint.Metadata, metadata => metadata is
                Microsoft.AspNetCore.Authorization.AuthorizeAttribute { Policy: "admin-mfa" });
            var method = Assert.Single(endpoint.Metadata.GetMetadata<HttpMethodMetadata>()!.HttpMethods);
            Assert.Equal(method == "GET" ? "organization-activity-read" : "organization-write",
                endpoint.Metadata.GetMetadata<EnableRateLimitingAttribute>()?.PolicyName);
        }
    }

    public void Dispose() { client.Dispose(); application.Dispose(); }

    private static object ValidDecision() => new
        { status = 1, reason = "Revisión manual confirmada.", expectedRevision = 0, expectedProfileVersion = 4 };

    private static HttpRequestMessage Request(string method, object? body = null,
        string role = PlatformRoles.SuperAdmin, bool mfa = true, int authenticationAgeMinutes = 0)
    {
        var request = new HttpRequestMessage(new HttpMethod(method), Path);
        if (method == "POST") request.Content = JsonContent.Create(body ?? ValidDecision());
        var now = DateTime.UtcNow;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, Admin.ToString("D")),
            new(ClaimTypes.NameIdentifier, Admin.ToString("D")),
            new(ClaimTypes.Role, role), new("auth_level", "full"),
            new("auth_time", new DateTimeOffset(now.AddMinutes(-authenticationAgeMinutes)).ToUnixTimeSeconds().ToString())
        };
        if (mfa) claims.Add(new("amr", "mfa"));
        var token = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
            claims, now.AddMinutes(-1), now.AddMinutes(10), new SigningCredentials(
                new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer",
            new JwtSecurityTokenHandler().WriteToken(token));
        return request;
    }

    private static OrganizationVerification Snapshot() => new(Organization, "Organización de prueba",
        0, 0, 0, 4, null, null, null, null, null, false, []);

    private sealed class FakeRepository : IOrganizationVerificationRepository
    {
        public int Calls { get; private set; }
        public int? FailureNumber { get; set; }
        public Guid Actor { get; private set; }
        public Guid OrganizationId { get; private set; }
        public OrganizationVerificationDecision? Decision { get; private set; }
        public OrganizationVerification? Snapshot { get; set; } = OrganizationVerificationEndpointTests.Snapshot();

        public Task<OrganizationVerification?> GetAsync(Guid adminUserPublicId,
            Guid organizationPublicId, CancellationToken cancellationToken)
        {
            CountOrFail();
            return Task.FromResult(Snapshot);
        }

        public Task<OrganizationVerification> DecideAsync(Guid adminUserPublicId,
            Guid organizationPublicId, OrganizationVerificationDecision decision, CancellationToken cancellationToken)
        {
            CountOrFail();
            Actor = adminUserPublicId;
            OrganizationId = organizationPublicId;
            Decision = decision;
            var now = DateTimeOffset.UtcNow;
            var value = Snapshot! with { Revision = decision.ExpectedRevision + 1,
                Status = (byte)decision.Status, RecordedStatus = (byte)decision.Status,
                ReviewedProfileVersion = decision.ExpectedProfileVersion, ReviewedAtUtc = now,
                Reason = decision.Reason, ReviewedByUserPublicId = adminUserPublicId,
                ReviewedByName = "Administración", History = [new(decision.ExpectedRevision + 1,
                    (byte)decision.Status, decision.ExpectedProfileVersion, decision.Reason!, now,
                    adminUserPublicId, "Administración")] };
            return Task.FromResult(value);
        }

        private void CountOrFail()
        {
            Calls++;
            if (FailureNumber is { } number)
                throw new OrganizationVerificationDataException(number,
                    new InvalidOperationException("private SQL connection server.example"));
        }
    }
}
