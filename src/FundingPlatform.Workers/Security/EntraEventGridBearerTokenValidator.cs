using System.Security.Claims;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Workers.Configuration;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.Workers.Security;

public sealed class EntraEventGridBearerTokenValidator : IEventGridBearerTokenValidator
{
    private readonly DefenderEventGridOptions options;
    private readonly IConfigurationManager<OpenIdConnectConfiguration>? metadata;
    private readonly JsonWebTokenHandler handler;

    public EntraEventGridBearerTokenValidator(IOptions<DefenderEventGridOptions> options)
        : this(options, CreateMetadata(options.Value), new JsonWebTokenHandler())
    {
    }

    internal EntraEventGridBearerTokenValidator(
        IOptions<DefenderEventGridOptions> options,
        IConfigurationManager<OpenIdConnectConfiguration>? metadata,
        JsonWebTokenHandler handler)
    {
        this.options = options.Value;
        this.metadata = metadata;
        this.handler = handler;
    }

    private static IConfigurationManager<OpenIdConnectConfiguration>? CreateMetadata(
        DefenderEventGridOptions options)
    {
        if (!options.Enabled) return null;
        var authority = $"https://login.microsoftonline.com/{options.TenantId}/v2.0";
        return new ConfigurationManager<OpenIdConnectConfiguration>(
            $"{authority}/.well-known/openid-configuration",
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever { RequireHttps = true });
    }

    public async Task<EventGridTokenValidation> ValidateAsync(
        string? authorizationHeader,
        CancellationToken cancellationToken)
    {
        if (!options.Enabled || metadata is null ||
            string.IsNullOrWhiteSpace(authorizationHeader) ||
            !authorizationHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return Invalid();
        }

        var token = authorizationHeader[7..].Trim();
        if (token.Length is < 100 or > 16_384 || token.Contains('\r') || token.Contains('\n'))
            return Invalid();

        OpenIdConnectConfiguration configuration;
        try
        {
            configuration = await metadata.GetConfigurationAsync(cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // Discovery/JWKS is a dependency. A 401 would cause Event Grid to stop
            // retrying a valid delivery, so surface dependency failure as 503.
            return Unavailable();
        }

        try
        {
            var canonicalTenant = Guid.Parse(options.TenantId).ToString("D");
            var result = await handler.ValidateTokenAsync(token, new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuers =
                [
                    $"https://login.microsoftonline.com/{canonicalTenant}/v2.0",
                    $"https://sts.windows.net/{canonicalTenant}/"
                ],
                ValidateAudience = true,
                ValidAudience = options.Audience,
                ValidateIssuerSigningKey = true,
                IssuerSigningKeys = configuration.SigningKeys,
                ValidateLifetime = true,
                RequireExpirationTime = true,
                RequireSignedTokens = true,
                ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
                ClockSkew = TimeSpan.FromMinutes(2),
                NameClaimType = ClaimTypes.NameIdentifier
            });
            if (!result.IsValid || result.ClaimsIdentity is null)
            {
                if (result.Exception is SecurityTokenSignatureKeyNotFoundException)
                {
                    metadata.RequestRefresh();
                    return Unavailable();
                }
                return Invalid();
            }

            var tenant = Find(result.ClaimsIdentity, "tid");
            var application = Find(result.ClaimsIdentity, "azp") ??
                              Find(result.ClaimsIdentity, "appid");
            var principal = Find(result.ClaimsIdentity, "oid");
            if (!Guid.TryParse(tenant, out var tenantId) ||
                !Guid.TryParse(application, out var applicationId) ||
                !Guid.TryParse(principal, out var principalId) ||
                !FixedGuid(tenantId, options.TenantId) ||
                !FixedGuid(applicationId, options.AllowedCallerApplicationId) ||
                !FixedGuid(principalId, options.AllowedCallerObjectId))
            {
                return Invalid();
            }

            return new EventGridTokenValidation(
                EventGridTokenValidationOutcome.Valid,
                new EventGridCaller(tenantId, principalId, applicationId));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return Invalid();
        }
    }

    private static EventGridTokenValidation Invalid() =>
        new(EventGridTokenValidationOutcome.Invalid);

    private static EventGridTokenValidation Unavailable() =>
        new(EventGridTokenValidationOutcome.Unavailable);

    private static string? Find(ClaimsIdentity identity, string type) =>
        identity.FindFirst(type)?.Value;

    private static bool FixedGuid(Guid value, string expected) =>
        Guid.TryParse(expected, out var expectedGuid) && value == expectedGuid;
}
