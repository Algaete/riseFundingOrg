using System.Security.Claims;
using FundingPlatform.Infrastructure.Identity.Configuration;

namespace FundingPlatform.Api.Configuration;

internal static class EntraExternalIdentityClaims
{
    public const string ValidatedIssuer = "fundingplatform:external:issuer";
    public const string ValidatedSubject = "fundingplatform:external:subject";

    public static bool TryAddValidatedIdentity(
        ClaimsPrincipal? principal,
        string? validatedIssuer)
    {
        if (principal?.Identity is not ClaimsIdentity identity ||
            !EntraAuthenticationOptions.IsSupportedTokenIssuer(validatedIssuer))
        {
            return false;
        }

        var subject = principal.FindFirstValue("sub")
            ?? principal.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrWhiteSpace(subject) || subject.Length > 255)
        {
            return false;
        }

        foreach (var claim in identity.FindAll(ValidatedIssuer)
                     .Concat(identity.FindAll(ValidatedSubject))
                     .ToArray())
        {
            identity.RemoveClaim(claim);
        }

        identity.AddClaim(new Claim(
            ValidatedIssuer,
            validatedIssuer!,
            ClaimValueTypes.String,
            "FundingPlatform"));
        identity.AddClaim(new Claim(
            ValidatedSubject,
            subject,
            ClaimValueTypes.String,
            "FundingPlatform"));
        return true;
    }
}
