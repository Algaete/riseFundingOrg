using FundingPlatform.Api.Endpoints;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Validators;

namespace FundingPlatform.Api.Configuration;

internal static class EntraOpenIdConnectConfiguration
{
    public static void Configure(OpenIdConnectOptions options, EntraAuthenticationOptions entra)
    {
        var authority = $"https://login.microsoftonline.com/{entra.TenantId}/v2.0";
        var aadIssuerValidator = AadIssuerValidator.GetAadIssuerValidator(authority);

        options.SignInScheme = ExternalAuthenticationEndpoints.ExternalCookieScheme;
        options.Authority = authority;
        options.ClientId = entra.ClientId;
        options.ClientSecret = entra.ClientSecret;
        options.CallbackPath = entra.CallbackPath;
        options.ResponseType = "code";
        options.UsePkce = true;
        options.MapInboundClaims = false;
        options.SaveTokens = false;
        options.GetClaimsFromUserInfoEndpoint = false;
        options.Scope.Clear();
        options.Scope.Add("openid");
        options.Scope.Add("profile");
        options.Scope.Add("email");
        options.CorrelationCookie.SameSite = SameSiteMode.None;
        options.CorrelationCookie.SecurePolicy = CookieSecurePolicy.Always;
        options.NonceCookie.SameSite = SameSiteMode.None;
        options.NonceCookie.SecurePolicy = CookieSecurePolicy.Always;
        options.TokenValidationParameters.ValidateIssuer = true;
        options.TokenValidationParameters.IssuerValidator = aadIssuerValidator.Validate;
        options.TokenValidationParameters.ValidateAudience = true;
        options.TokenValidationParameters.ValidAudience = entra.ClientId;
        options.TokenValidationParameters.NameClaimType = "name";
        options.Events = new OpenIdConnectEvents
        {
            OnTokenValidated = context =>
            {
                if (!EntraExternalIdentityClaims.TryAddValidatedIdentity(
                        context.Principal,
                        context.SecurityToken.Issuer))
                {
                    context.Fail("The validated Microsoft identity is incomplete.");
                }

                return Task.CompletedTask;
            },
            OnRemoteFailure = context =>
            {
                context.HandleResponse();
                var logger = context.HttpContext.RequestServices
                    .GetRequiredService<ILoggerFactory>()
                    .CreateLogger("FundingPlatform.ExternalAuthentication");
                logger.LogWarning(
                    "Microsoft OIDC failed. FailureType={FailureType}",
                    context.Failure?.GetType().Name ?? "unknown");
                var frontend = context.HttpContext.RequestServices
                    .GetRequiredService<IOptions<WebOptions>>().Value.FrontendBaseUrl.TrimEnd('/');
                context.Response.Redirect($"{frontend}/login?sso=failed");
                return Task.CompletedTask;
            }
        };
    }
}
