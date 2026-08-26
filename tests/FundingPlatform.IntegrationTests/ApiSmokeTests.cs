using System.Net;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Api.Configuration;
using FundingPlatform.Api.Endpoints;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.IntegrationTests;

public sealed class ApiSmokeTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private readonly ApiFactory factory = factory;
    private readonly HttpClient client = factory.CreateClient(new()
    {
        AllowAutoRedirect = false
    });

    [Theory]
    [InlineData("/health")]
    [InlineData("/health/ready")]
    public async Task Health_endpoints_are_healthy(string path)
    {
        using var response = await client.GetAsync(path);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Swagger_and_OpenApi_are_exposed_in_testing()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(document.RootElement.TryGetProperty("openapi", out _));
        Assert.True(document.RootElement.GetProperty("paths").TryGetProperty("/", out _));

        using var uiResponse = await client.GetAsync("/swagger/index.html");
        Assert.Equal(HttpStatusCode.OK, uiResponse.StatusCode);
    }

    [Fact]
    public async Task Correlation_id_is_echoed_and_added_to_problem_details()
    {
        const string correlationId = "integration-smoke-01";
        using var request = new HttpRequestMessage(HttpMethod.Get, "/missing");
        request.Headers.Add("X-Correlation-ID", correlationId);

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(correlationId, response.Headers.GetValues("X-Correlation-ID").Single());
        Assert.Equal(correlationId, problem.RootElement.GetProperty("correlationId").GetString());
    }

    [Fact]
    public async Task Protected_account_endpoint_rejects_anonymous_requests_without_caching()
    {
        using var response = await client.GetAsync("/api/v1/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Equal("DENY", response.Headers.GetValues("X-Frame-Options").Single());
    }

    [Theory]
    [InlineData("/api/v1/catalogs")]
    [InlineData("/api/v1/organizations")]
    [InlineData("/api/v1/organizations/11111111-1111-1111-1111-111111111111/profile")]
    public async Task Organization_endpoints_reject_anonymous_requests(string path)
    {
        using var response = await client.GetAsync(path);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        if (path.StartsWith("/api/v1/organizations", StringComparison.Ordinal))
            Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Project_endpoints_reject_anonymous_requests()
    {
        using var response = await client.GetAsync(
            "/api/v1/organizations/11111111-1111-1111-1111-111111111111/projects");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task External_provider_discovery_is_safe_when_entra_is_disabled()
    {
        using var response = await client.GetAsync("/api/v1/auth/external/providers");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("entra", document.RootElement[0].GetProperty("code").GetString());
        Assert.False(document.RootElement[0].GetProperty("enabled").GetBoolean());
    }

    [Theory]
    [InlineData("/api/v1/auth/register", "{\"email\":\"user@example.test\",\"displayName\":\"Test User\",\"password\":\"Safe-password-1234\",\"preferredLocale\":\"es-CL\"}")]
    [InlineData("/api/v1/auth/resend-verification", "{\"email\":\"user@example.test\"}")]
    [InlineData("/api/v1/auth/forgot-password", "{\"email\":\"user@example.test\"}")]
    public async Task Email_dependent_identity_flows_fail_closed_before_database_work(
        string path,
        string body)
    {
        await using var disabledApplication = factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Email:Enabled"] = "false"
                })));
        using var disabledClient = disabledApplication.CreateClient();
        using var content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");

        using var response = await disabledClient.PostAsync(path, content);
        var responseBody = await response.Content.ReadAsStringAsync();
        using var problem = JsonDocument.Parse(responseBody);

        Assert.True(
            response.StatusCode == HttpStatusCode.ServiceUnavailable,
            $"Expected 503 for {path}; received {(int)response.StatusCode}: {responseBody}");
        Assert.Equal(
            "https://fundingplatform.local/problems/identity-email-disabled",
            problem.RootElement.GetProperty("type").GetString());
    }

    [Fact]
    public void Public_entra_oidc_uses_common_authority_and_cross_site_safe_cookies()
    {
        var options = new OpenIdConnectOptions();
        EntraOpenIdConnectConfiguration.Configure(options, new EntraAuthenticationOptions
        {
            Enabled = true,
            TenantId = EntraAuthenticationOptions.PublicTenant,
            ClientId = "11111111-1111-1111-1111-111111111111",
            ClientSecret = new string('x', 32)
        });

        Assert.Equal("https://login.microsoftonline.com/common/v2.0", options.Authority);
        Assert.False(options.MapInboundClaims);
        Assert.True(options.UsePkce);
        Assert.True(options.TokenValidationParameters.ValidateIssuer);
        Assert.NotNull(options.TokenValidationParameters.IssuerValidator);
        Assert.True(options.TokenValidationParameters.ValidateAudience);
        Assert.Equal("11111111-1111-1111-1111-111111111111", options.TokenValidationParameters.ValidAudience);
        Assert.Equal(SameSiteMode.None, options.CorrelationCookie.SameSite);
        Assert.Equal(CookieSecurePolicy.Always, options.CorrelationCookie.SecurePolicy);
        Assert.Equal(SameSiteMode.None, options.NonceCookie.SameSite);
        Assert.Equal(CookieSecurePolicy.Always, options.NonceCookie.SecurePolicy);
        Assert.NotNull(options.Events.OnTokenValidated);

        var challenge = ExternalAuthenticationEndpoints.NewProperties("login", "/dashboard");
        Assert.Equal("select_account", challenge.Prompt);
        Assert.Equal("/api/v1/auth/external/complete", challenge.RedirectUri);
    }

    [Fact]
    public void Validated_microsoft_token_is_normalized_into_an_external_identity()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "microsoft-subject-123"),
            new Claim("preferred_username", "new-user@example.test"),
            new Claim("name", "New User")
        ], "oidc"));

        var normalized = EntraExternalIdentityClaims.TryAddValidatedIdentity(
            principal,
            "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0");
        var identity = ExternalAuthenticationEndpoints.ReadIdentity(principal);

        Assert.True(normalized);
        Assert.NotNull(identity);
        Assert.Equal("entra", identity.Provider);
        Assert.Equal("microsoft-subject-123", identity.Subject);
        Assert.Equal("new-user@example.test", identity.Email);
        Assert.Equal("New User", identity.DisplayName);
    }

    [Fact]
    public void Untrusted_microsoft_issuer_cannot_create_an_external_identity()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "microsoft-subject-123"),
            new Claim("email", "new-user@example.test"),
            new Claim("name", "New User")
        ], "oidc"));

        Assert.False(EntraExternalIdentityClaims.TryAddValidatedIdentity(
            principal,
            "https://login.microsoftonline.com.evil.test/11111111-1111-1111-1111-111111111111/v2.0"));
        Assert.Null(ExternalAuthenticationEndpoints.ReadIdentity(principal));
    }

    [Fact]
    public void Validated_microsoft_identity_replaces_untrusted_canonical_claims()
    {
        const string trustedIssuer =
            "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0";
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "trusted-subject"),
            new Claim("email", "new-user@example.test"),
            new Claim("name", "New User"),
            new Claim(EntraExternalIdentityClaims.ValidatedIssuer,
                "https://login.microsoftonline.com/22222222-2222-2222-2222-222222222222/v2.0"),
            new Claim(EntraExternalIdentityClaims.ValidatedSubject, "injected-subject")
        ], "oidc"));

        Assert.True(EntraExternalIdentityClaims.TryAddValidatedIdentity(
            principal,
            trustedIssuer));

        var identity = ExternalAuthenticationEndpoints.ReadIdentity(principal);
        Assert.NotNull(identity);
        Assert.Equal(trustedIssuer, identity.Issuer);
        Assert.Equal("trusted-subject", identity.Subject);
        Assert.Single(principal.FindAll(EntraExternalIdentityClaims.ValidatedIssuer));
        Assert.Single(principal.FindAll(EntraExternalIdentityClaims.ValidatedSubject));
    }

    [Fact]
    public void Microsoft_link_cookie_satisfies_host_prefix_requirements()
    {
        var options = ExternalAuthenticationEndpoints.CreateLinkIntentCookieOptions(
            TimeSpan.FromMinutes(3));

        Assert.True(options.HttpOnly);
        Assert.True(options.Secure);
        Assert.Equal(SameSiteMode.Lax, options.SameSite);
        Assert.Equal("/", options.Path);
        Assert.Null(options.Domain);
        Assert.Equal(TimeSpan.FromMinutes(3), options.MaxAge);
    }
}
