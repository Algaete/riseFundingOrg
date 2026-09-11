using System.Net;
using System.Net.Http.Json;
using FundingPlatform.Api.Configuration;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed class RefreshSessionCookieTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private const string Origin = "http://localhost:5173";
    private const string SyntheticRefresh = "synthetic-refresh-not-a-real-credential";

    private WebApplicationFactory<Program> CreateApplication(bool partitioned, FakeAuthentication service) =>
        factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.PostConfigure<AuthenticationOptions>(options => options.RefreshToken.UsePartitionedCookie = partitioned);
            services.RemoveAll<IAuthenticationService>();
            services.AddSingleton<IAuthenticationService>(service);
        }));

    private static HttpRequestMessage Request(string path, string? origin = Origin, string? cookie = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, path)
        {
            Content = JsonContent.Create(new { email = "test@example.invalid", password = "Synthetic-test-only", challengeToken = "test-challenge", code = "123456" })
        };
        if (origin is not null) request.Headers.TryAddWithoutValidation("Origin", origin);
        if (cookie is not null) request.Headers.TryAddWithoutValidation("Cookie", cookie);
        return request;
    }

    [Theory]
    [InlineData(false, "/api/v1/auth/login")]
    [InlineData(true, "/api/v1/auth/login")]
    [InlineData(false, "/api/v1/auth/mfa/challenge")]
    [InlineData(true, "/api/v1/auth/mfa/challenge")]
    [InlineData(false, "/api/v1/auth/external/exchange")]
    [InlineData(true, "/api/v1/auth/external/exchange")]
    public async Task Every_successful_signin_uses_the_selected_secure_cookie(bool partitioned, string path)
    {
        var service = new FakeAuthentication();
        await using var application = CreateApplication(partitioned, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request(path);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var cookie = Assert.Single(response.Headers.GetValues("Set-Cookie")).ToLowerInvariant();
        Assert.StartsWith(partitioned ? "__secure-fp_refresh_partitioned=" : "__secure-fp_refresh=", cookie);
        Assert.Contains("httponly", cookie);
        Assert.Contains("secure", cookie);
        Assert.Contains("path=/api/v1/auth", cookie);
        Assert.Contains("max-age=2592000", cookie);
        Assert.DoesNotContain("domain=", cookie);
        Assert.Contains(partitioned ? "samesite=none" : "samesite=lax", cookie);
        Assert.Equal(partitioned, cookie.Split(';').Any(x => x.Trim() == "partitioned"));
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Theory]
    [InlineData("/api/v1/auth/login", null)]
    [InlineData("/api/v1/auth/login", "https://unrelated.example")]
    [InlineData("/api/v1/auth/mfa/challenge", "null")]
    [InlineData("/api/v1/auth/mfa/challenge", "http://localhost:5173.evil.example")]
    [InlineData("/api/v1/auth/external/exchange", null)]
    [InlineData("/api/v1/auth/external/exchange", "https://unrelated.example")]
    [InlineData("/api/v1/auth/refresh", "https://unrelated.example")]
    [InlineData("/api/v1/auth/logout", "https://unrelated.example")]
    public async Task Cross_site_cookie_operations_require_the_exact_allowed_origin(string path, string? origin)
    {
        var service = new FakeAuthentication();
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request(path, origin, $"{RefreshSessionCookie.PartitionedName}={SyntheticRefresh}");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, service.Calls);
        Assert.False(response.Headers.Contains("Set-Cookie"));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Refresh_reads_only_the_cookie_for_the_configured_mode(bool partitioned)
    {
        var service = new FakeAuthentication();
        await using var application = CreateApplication(partitioned, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        var correctName = partitioned ? RefreshSessionCookie.PartitionedName : RefreshSessionCookie.SameSiteName;
        var wrongName = partitioned ? RefreshSessionCookie.SameSiteName : RefreshSessionCookie.PartitionedName;
        using var wrongRequest = Request("/api/v1/auth/refresh", cookie: $"{wrongName}={SyntheticRefresh}");
        using var wrongResponse = await client.SendAsync(wrongRequest);
        Assert.Equal(HttpStatusCode.Unauthorized, wrongResponse.StatusCode);
        Assert.Equal(0, service.Calls);
        using var request = Request("/api/v1/auth/refresh", cookie: $"{correctName}={SyntheticRefresh}");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(SyntheticRefresh, service.LastRefresh);
        Assert.StartsWith(correctName + "=", Assert.Single(response.Headers.GetValues("Set-Cookie")));
    }

    [Theory]
    [InlineData(RefreshOutcome.Expired)]
    [InlineData(RefreshOutcome.ReplayDetected)]
    [InlineData(RefreshOutcome.SessionInvalidated)]
    public async Task Revoked_or_expired_session_clears_the_same_partition(RefreshOutcome outcome)
    {
        var service = new FakeAuthentication { RefreshOutcome = outcome };
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request("/api/v1/auth/refresh", cookie: $"{RefreshSessionCookie.PartitionedName}={SyntheticRefresh}");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        AssertDeleted(response);
    }

    [Fact]
    public async Task Rotation_conflict_preserves_the_cookie_for_the_existing_single_retry()
    {
        var service = new FakeAuthentication { RefreshOutcome = RefreshOutcome.Conflict };
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request("/api/v1/auth/refresh", cookie: $"{RefreshSessionCookie.PartitionedName}={SyntheticRefresh}");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.False(response.Headers.Contains("Set-Cookie"));
    }

    [Fact]
    public async Task Logout_revokes_and_deletes_the_partitioned_cookie()
    {
        var service = new FakeAuthentication();
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request("/api/v1/auth/logout", cookie: $"{RefreshSessionCookie.PartitionedName}={SyntheticRefresh}");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(SyntheticRefresh, service.LastRefresh);
        AssertDeleted(response);
    }

    [Theory]
    [InlineData(LoginOutcome.MfaRequired)]
    [InlineData(LoginOutcome.MfaSetupRequired)]
    public async Task Password_alone_does_not_issue_a_refresh_cookie_when_MFA_is_required(LoginOutcome outcome)
    {
        var service = new FakeAuthentication { LoginOutcome = outcome };
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request("/api/v1/auth/login");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.False(response.Headers.Contains("Set-Cookie"));
    }

    [Fact]
    public async Task Multiple_origins_cannot_issue_a_cookie()
    {
        var service = new FakeAuthentication();
        await using var application = CreateApplication(true, service);
        using var client = application.CreateClient(new() { HandleCookies = false });
        using var request = Request("/api/v1/auth/login");
        request.Headers.TryAddWithoutValidation("Origin", "https://unrelated.example");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, service.Calls);
        Assert.False(response.Headers.Contains("Set-Cookie"));
    }

    [Fact]
    public void Default_mode_and_administrator_lifetime_are_not_relaxed()
    {
        var options = new AuthenticationOptions();
        Assert.False(options.RefreshToken.UsePartitionedCookie);
        Assert.Equal(60, options.Mfa.AdminSessionMinutes);
        Assert.Equal(15, options.Jwt.AccessTokenMinutes);
        Assert.Equal(Microsoft.AspNetCore.Http.SameSiteMode.Lax, RefreshSessionCookie.CreateOptions(options).SameSite);
    }

    private static void AssertDeleted(HttpResponseMessage response)
    {
        var cookie = Assert.Single(response.Headers.GetValues("Set-Cookie")).ToLowerInvariant();
        Assert.StartsWith("__secure-fp_refresh_partitioned=;", cookie);
        Assert.Contains("expires=thu, 01 jan 1970", cookie);
        Assert.Contains("samesite=none", cookie);
        Assert.Contains("partitioned", cookie);
        Assert.Contains("path=/api/v1/auth", cookie);
        Assert.Contains("httponly", cookie);
        Assert.Contains("secure", cookie);
        Assert.DoesNotContain("max-age=2592000", cookie);
    }

    private sealed class FakeAuthentication : IAuthenticationService
    {
        public int Calls { get; private set; }
        public string? LastRefresh { get; private set; }
        public LoginOutcome LoginOutcome { get; init; } = LoginOutcome.Success;
        public RefreshOutcome RefreshOutcome { get; init; } = RefreshOutcome.Success;
        private static AccessSession Session => new("synthetic-access", DateTime.UtcNow.AddMinutes(15), new AuthenticatedUser(
            Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"), "test@example.invalid", "Synthetic User", "es-CL", ["Admin"], true));
        private Task<LoginResult> Login() { Calls++; return Task.FromResult(new LoginResult(LoginOutcome, Session, SyntheticRefresh)); }
        public Task<LoginResult> LoginAsync(LoginInput input, ClientRequestContext context, CancellationToken token) => Login();
        public Task<LoginResult> CompleteMfaChallengeAsync(MfaChallengeInput input, ClientRequestContext context, CancellationToken token) => Login();
        public Task<LoginResult> ExchangeExternalHandoffAsync(string code, ClientRequestContext context, CancellationToken token) => Login();
        public Task<RefreshResult> RefreshAsync(string refresh, ClientRequestContext context, CancellationToken token)
        { Calls++; LastRefresh = refresh; return Task.FromResult(new RefreshResult(RefreshOutcome, Session, SyntheticRefresh)); }
        public Task LogoutAsync(string refresh, ClientRequestContext context, CancellationToken token)
        { Calls++; LastRefresh = refresh; return Task.CompletedTask; }
        public Task LogoutAllAsync(Guid id, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task<RegistrationResult> RegisterAsync(RegistrationInput input, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task<bool> VerifyEmailAsync(string value, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task ResendVerificationAsync(string value, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task ForgotPasswordAsync(string value, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task<PasswordResetResult> ResetPasswordAsync(ResetPasswordInput input, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task<AuthenticatedUser?> GetCurrentUserAsync(Guid id, CancellationToken token) => throw new NotSupportedException();
        public Task<MfaSetupResult> BeginMfaSetupAsync(Guid id, CancellationToken token) => throw new NotSupportedException();
        public Task<MfaConfirmationResult?> ConfirmMfaSetupAsync(Guid id, string code, CancellationToken token) => throw new NotSupportedException();
        public Task<ExternalIdentityCompletionResult> CompleteExternalIdentityAsync(ExternalIdentityInput input, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
        public Task<ExternalIdentityLinkOutcome> LinkExternalIdentityAsync(Guid id, ExternalIdentityInput input, ClientRequestContext context, CancellationToken token) => throw new NotSupportedException();
    }
}
