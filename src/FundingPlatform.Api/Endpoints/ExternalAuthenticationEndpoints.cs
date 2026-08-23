using System.Security.Claims;
using FundingPlatform.Api.Configuration;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Contracts.Authentication;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Extensions.Options;
using Microsoft.AspNetCore.DataProtection;
using System.Globalization;
using ApplicationAuthenticationService = FundingPlatform.Application.Authentication.IAuthenticationService;
using PlatformAuthenticationOptions = FundingPlatform.Infrastructure.Identity.Configuration.AuthenticationOptions;

namespace FundingPlatform.Api.Endpoints;

public static class ExternalAuthenticationEndpoints
{
    public const string ExternalCookieScheme = "FundingPlatform.External";
    public const string EntraScheme = "FundingPlatform.Entra";

    public static IEndpointRouteBuilder MapExternalAuthenticationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var auth = endpoints.MapGroup("/api/v1/auth/external").WithTags("External authentication");
        auth.MapGet("/providers", GetProviders);
        auth.MapGet("/entra/start", StartSignIn)
            .AllowAnonymous().RequireRateLimiting("auth-login");
        auth.MapGet("/complete", CompleteAsync)
            .AllowAnonymous().RequireRateLimiting("auth-login");
        auth.MapPost("/exchange", ExchangeAsync)
            .AllowAnonymous().RequireRateLimiting("auth-token");

        endpoints.MapPost("/api/v1/me/external/entra/link-intents", CreateLinkIntent)
            .WithTags("Account")
            .RequireAuthorization("full-session")
            .RequireRateLimiting("auth-token");
        auth.MapGet("/entra/link", StartLink)
            .AllowAnonymous().RequireRateLimiting("auth-token");
        return endpoints;
    }

    private static IResult GetProviders(IOptions<PlatformAuthenticationOptions> options) =>
        Results.Ok(new[]
        {
            new ExternalProviderResponse("entra", "Microsoft", options.Value.External.Entra.Enabled)
        });

    private static IResult StartSignIn(
        string? returnUrl,
        IOptions<PlatformAuthenticationOptions> options)
    {
        if (!options.Value.External.Entra.Enabled) return ProviderUnavailable();
        var properties = NewProperties("login", NormalizeReturnUrl(returnUrl));
        return Results.Challenge(properties, [EntraScheme]);
    }

    private static IResult CreateLinkIntent(
        ClaimsPrincipal principal,
        HttpContext context,
        IOptions<PlatformAuthenticationOptions> options,
        IDataProtectionProvider dataProtectionProvider,
        TimeProvider timeProvider)
    {
        if (!options.Value.External.Entra.Enabled) return ProviderUnavailable();
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        var expiry = timeProvider.GetUtcNow().AddMinutes(3).ToUnixTimeSeconds();
        var protector = dataProtectionProvider.CreateProtector("FundingPlatform.ExternalLinkIntent.v1");
        var token = protector.Protect($"{userId:D}|{expiry.ToString(CultureInfo.InvariantCulture)}|{Guid.NewGuid():N}");
        context.Response.Cookies.Append(
            "__Host-fp_sso_link",
            token,
            CreateLinkIntentCookieOptions(TimeSpan.FromMinutes(3)));
        return Results.Ok(new ExternalLinkIntentResponse("/api/v1/auth/external/entra/link"));
    }

    private static IResult StartLink(
        HttpContext context,
        IOptions<PlatformAuthenticationOptions> options,
        IOptions<WebOptions> webOptions,
        IDataProtectionProvider dataProtectionProvider,
        TimeProvider timeProvider)
    {
        if (!options.Value.External.Entra.Enabled) return ProviderUnavailable();
        if (!context.Request.Cookies.TryGetValue("__Host-fp_sso_link", out var protectedIntent))
            return Redirect(webOptions.Value.FrontendBaseUrl, "/account?sso=link_failed");
        context.Response.Cookies.Delete(
            "__Host-fp_sso_link",
            CreateLinkIntentCookieOptions());

        Guid userId;
        try
        {
            var value = dataProtectionProvider.CreateProtector("FundingPlatform.ExternalLinkIntent.v1")
                .Unprotect(protectedIntent).Split('|');
            if (value.Length != 3 || !Guid.TryParse(value[0], out userId) ||
                !long.TryParse(value[1], CultureInfo.InvariantCulture, out var expiry) ||
                expiry <= timeProvider.GetUtcNow().ToUnixTimeSeconds())
                return Redirect(webOptions.Value.FrontendBaseUrl, "/account?sso=link_failed");
        }
        catch (System.Security.Cryptography.CryptographicException)
        {
            return Redirect(webOptions.Value.FrontendBaseUrl, "/account?sso=link_failed");
        }

        var properties = NewProperties("link", "/account");
        properties.Items["user_public_id"] = userId.ToString("D");
        return Results.Challenge(properties, [EntraScheme]);
    }

    private static async Task<IResult> CompleteAsync(
        HttpContext context,
        ApplicationAuthenticationService service,
        IOptions<WebOptions> webOptions,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var authentication = await context.AuthenticateAsync(ExternalCookieScheme);
        if (!authentication.Succeeded || authentication.Principal is null)
            return Redirect(webOptions.Value.FrontendBaseUrl, "/login?sso=failed");

        try
        {
            var identity = ReadIdentity(authentication.Principal);
            if (identity is null)
            {
                var claims = authentication.Principal;
                loggerFactory.CreateLogger("FundingPlatform.ExternalAuthentication").LogWarning(
                    "Validated Microsoft identity is incomplete. HasIssuer={HasIssuer}, " +
                    "HasSubject={HasSubject}, HasEmail={HasEmail}, HasName={HasName}",
                    claims.HasClaim(claim => claim.Type == EntraExternalIdentityClaims.ValidatedIssuer),
                    claims.HasClaim(claim => claim.Type == EntraExternalIdentityClaims.ValidatedSubject),
                    claims.HasClaim(claim => claim.Type is "email" or "preferred_username" or "upn" ||
                                             claim.Type == ClaimTypes.Email || claim.Type == ClaimTypes.Upn),
                    claims.HasClaim(claim => claim.Type == "name" || claim.Type == ClaimTypes.Name));
                return Redirect(webOptions.Value.FrontendBaseUrl, "/login?sso=invalid_identity");
            }

            var mode = GetItem(authentication.Properties, "mode") ?? "login";
            var returnUrl = NormalizeReturnUrl(GetItem(authentication.Properties, "return_url"));
            if (mode == "link")
            {
                if (!Guid.TryParse(GetItem(authentication.Properties, "user_public_id"), out var userId))
                    return Redirect(webOptions.Value.FrontendBaseUrl, "/account?sso=link_failed");
                var outcome = await service.LinkExternalIdentityAsync(
                    userId, identity, CreateClientContext(context), cancellationToken);
                return Redirect(webOptions.Value.FrontendBaseUrl, outcome switch
                {
                    ExternalIdentityLinkOutcome.Success => "/account?sso=linked",
                    ExternalIdentityLinkOutcome.AlreadyLinkedToCurrentAccount =>
                        "/account?sso=already_linked",
                    _ => "/account?sso=link_failed"
                });
            }

            var completion = await service.CompleteExternalIdentityAsync(
                identity, CreateClientContext(context), cancellationToken);
            return completion.Outcome switch
            {
                ExternalIdentityCompletionOutcome.Success when completion.HandoffCode is not null =>
                    Redirect(webOptions.Value.FrontendBaseUrl,
                        $"/auth/external/callback?code={Uri.EscapeDataString(completion.HandoffCode)}&returnUrl={Uri.EscapeDataString(returnUrl)}"),
                ExternalIdentityCompletionOutcome.AccountLinkRequired =>
                    Redirect(webOptions.Value.FrontendBaseUrl, "/login?sso=account_link_required"),
                _ => Redirect(webOptions.Value.FrontendBaseUrl, "/login?sso=failed")
            };
        }
        finally
        {
            await context.SignOutAsync(ExternalCookieScheme);
        }
    }

    private static async Task<IResult> ExchangeAsync(
        ExternalHandoffExchangeRequest request,
        HttpContext context,
        ApplicationAuthenticationService service,
        IOptions<PlatformAuthenticationOptions> options,
        CancellationToken cancellationToken)
    {
        var result = await service.ExchangeExternalHandoffAsync(
            request.Code, CreateClientContext(context), cancellationToken);
        if (result.Outcome == LoginOutcome.Success && result.Session is not null && result.RefreshToken is not null)
        {
            SetRefreshCookie(context.Response, result.RefreshToken, options.Value);
            return Results.Ok(MapAuthenticationResponse(result));
        }

        if (result.Outcome is LoginOutcome.MfaRequired or LoginOutcome.MfaSetupRequired)
            return Results.Json(MapAuthenticationResponse(result), statusCode: StatusCodes.Status202Accepted);

        return Results.Problem(statusCode: 401, title: "Inicio SSO inválido",
            detail: "Inicia el acceso con Microsoft nuevamente.",
            type: "https://fundingplatform.local/problems/invalid-external-handoff");
    }

    internal static OpenIdConnectChallengeProperties NewProperties(string mode, string returnUrl)
    {
        var properties = new OpenIdConnectChallengeProperties
        {
            RedirectUri = "/api/v1/auth/external/complete",
            IsPersistent = false,
            AllowRefresh = false,
            Prompt = "select_account"
        };
        properties.Items["mode"] = mode;
        properties.Items["return_url"] = returnUrl;
        return properties;
    }

    internal static ExternalIdentityInput? ReadIdentity(ClaimsPrincipal principal)
    {
        var issuer = principal.FindFirstValue(EntraExternalIdentityClaims.ValidatedIssuer);
        var subject = principal.FindFirstValue(EntraExternalIdentityClaims.ValidatedSubject);
        var email = principal.FindFirstValue("email")
            ?? principal.FindFirstValue(ClaimTypes.Email)
            ?? principal.FindFirstValue("preferred_username")
            ?? principal.FindFirstValue("upn")
            ?? principal.FindFirstValue(ClaimTypes.Upn);
        var name = principal.FindFirstValue(ClaimTypes.Name)
            ?? principal.FindFirstValue("name")
            ?? email;
        return string.IsNullOrWhiteSpace(issuer) || string.IsNullOrWhiteSpace(subject) ||
               string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(name)
            ? null
            : new ExternalIdentityInput("entra", issuer, subject, email, name);
    }

    private static AuthenticationResponse MapAuthenticationResponse(LoginResult result) => new(
        result.Outcome switch
        {
            LoginOutcome.Success => "authenticated",
            LoginOutcome.MfaRequired => "mfa_required",
            LoginOutcome.MfaSetupRequired => "mfa_setup_required",
            _ => "authentication_failed"
        },
        result.Session?.AccessToken,
        result.Session?.ExpiresAtUtc,
        result.Session is null ? null : new AuthenticatedUserResponse(
            result.Session.User.PublicId, result.Session.User.Email, result.Session.User.DisplayName,
            result.Session.User.PreferredLocale, result.Session.User.Roles, result.Session.User.MfaEnabled),
        result.MfaChallengeToken, result.MfaChallengeExpiresAtUtc, result.MfaSetupToken);

    private static void SetRefreshCookie(HttpResponse response, string token, PlatformAuthenticationOptions options) =>
        response.Cookies.Append(AuthenticationEndpoints.RefreshCookieName, token, new CookieOptions
        {
            HttpOnly = true, Secure = true, SameSite = SameSiteMode.Lax,
            Path = "/api/v1/auth", IsEssential = true,
            MaxAge = TimeSpan.FromDays(options.RefreshToken.LifetimeDays)
        });

    private static string NormalizeReturnUrl(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.StartsWith('/') && !value.StartsWith("//", StringComparison.Ordinal)
            ? value : "/dashboard";
    private static string? GetItem(AuthenticationProperties? properties, string key) =>
        properties is not null && properties.Items.TryGetValue(key, out var value) ? value : null;
    private static IResult Redirect(string baseUrl, string path) =>
        new ExternalAuthenticationRedirect(baseUrl.TrimEnd('/') + path);
    private static bool TryGetPublicUserId(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);
    private static ClientRequestContext CreateClientContext(HttpContext context) => new(
        context.Connection.RemoteIpAddress?.ToString(), context.Request.Headers.UserAgent.ToString(), context.TraceIdentifier);
    internal static CookieOptions CreateLinkIntentCookieOptions(TimeSpan? maxAge = null) => new()
    {
        HttpOnly = true,
        Secure = true,
        SameSite = SameSiteMode.Lax,
        IsEssential = true,
        Path = "/",
        MaxAge = maxAge
    };
    private static IResult ProviderUnavailable() => Results.Problem(statusCode: 404,
        title: "SSO no configurado", detail: "Microsoft SSO todavía no está habilitado.",
        type: "https://fundingplatform.local/problems/external-provider-unavailable");
    private static IResult InvalidSession() => Results.Problem(statusCode: 401,
        title: "Sesión inválida", detail: "Inicia sesión nuevamente.",
        type: "https://fundingplatform.local/problems/invalid-session");

    private sealed class ExternalAuthenticationRedirect(string location) : IResult
    {
        public Task ExecuteAsync(HttpContext httpContext)
        {
            httpContext.Response.StatusCode = StatusCodes.Status302Found;
            httpContext.Response.Headers.Location = location;
            return Task.CompletedTask;
        }
    }
}
