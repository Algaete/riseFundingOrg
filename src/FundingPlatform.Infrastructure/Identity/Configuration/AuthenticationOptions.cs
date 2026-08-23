namespace FundingPlatform.Infrastructure.Identity.Configuration;

public sealed class AuthenticationOptions
{
    public const string SectionName = "Authentication";

    public JwtOptions Jwt { get; set; } = new();

    public RefreshTokenOptions RefreshToken { get; set; } = new();

    public SecurityTokenOptions SecurityToken { get; set; } = new();

    public MfaOptions Mfa { get; set; } = new();

    public SecurityHashOptions SecurityHash { get; set; } = new();

    public ExternalAuthenticationOptions External { get; set; } = new();

    public static bool IsValid(AuthenticationOptions options)
    {
        return Uri.TryCreate(options.Jwt.Issuer, UriKind.Absolute, out var issuer) &&
               issuer.Scheme == Uri.UriSchemeHttps &&
               !string.IsNullOrWhiteSpace(options.Jwt.Audience) &&
               options.Jwt.Audience.Length <= 200 &&
               TryDecodeAtLeast(options.Jwt.SigningKey, 64) &&
               options.Jwt.AccessTokenMinutes is >= 5 and <= 15 &&
               options.RefreshToken.LifetimeDays is >= 1 and <= 90 &&
               options.RefreshToken.RotationGraceSeconds is >= 1 and <= 30 &&
               options.SecurityToken.VerificationHours is >= 1 and <= 72 &&
               options.SecurityToken.PasswordResetMinutes is >= 5 and <= 60 &&
               options.Mfa.ChallengeMinutes is >= 1 and <= 10 &&
               options.Mfa.MaxAttempts is >= 3 and <= 10 &&
               options.Mfa.RecoveryCodeCount is >= 5 and <= 20 &&
               options.Mfa.AdminSessionMinutes is >= 5 and <= 60 &&
               TryDecodeAtLeast(options.SecurityHash.IpHashPepper, 32) &&
               TryDecodeAtLeast(options.SecurityHash.RecoveryCodePepper, 32) &&
               !string.IsNullOrWhiteSpace(options.SecurityHash.RecoveryCodePepperVersion) &&
               ExternalAuthenticationOptions.IsValid(options.External);
    }

    private static bool TryDecodeAtLeast(string? value, int minimumBytes)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        try
        {
            return Convert.FromBase64String(value).Length >= minimumBytes;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}

public sealed class ExternalAuthenticationOptions
{
    public EntraAuthenticationOptions Entra { get; set; } = new();

    public int HandoffMinutes { get; set; } = 3;

    public static bool IsValid(ExternalAuthenticationOptions options) =>
        options.HandoffMinutes is >= 1 and <= 10 &&
        (!options.Entra.Enabled ||
         string.Equals(options.Entra.TenantId, EntraAuthenticationOptions.PublicTenant, StringComparison.OrdinalIgnoreCase) &&
         Guid.TryParse(options.Entra.ClientId, out _) &&
         !string.IsNullOrWhiteSpace(options.Entra.ClientSecret) &&
         options.Entra.ClientSecret.Length >= 16 &&
         options.Entra.CallbackPath.StartsWith('/') &&
         !options.Entra.CallbackPath.StartsWith("//", StringComparison.Ordinal) &&
         !options.Entra.CallbackPath.Contains("?", StringComparison.Ordinal) &&
         !options.Entra.CallbackPath.Contains("#", StringComparison.Ordinal));
}

public sealed class EntraAuthenticationOptions
{
    public const string PublicTenant = "common";

    public bool Enabled { get; set; }

    public string TenantId { get; set; } = PublicTenant;

    public string ClientId { get; set; } = string.Empty;

    public string ClientSecret { get; set; } = string.Empty;

    public string CallbackPath { get; set; } = "/api/v1/auth/external/entra/callback";

    public static bool IsSupportedTokenIssuer(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var issuer) ||
            issuer.Scheme != Uri.UriSchemeHttps ||
            !issuer.Host.Equals("login.microsoftonline.com", StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(issuer.Query) ||
            !string.IsNullOrEmpty(issuer.Fragment))
        {
            return false;
        }

        var segments = issuer.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        return segments.Length == 2 &&
               Guid.TryParse(segments[0], out _) &&
               segments[1].Equals("v2.0", StringComparison.OrdinalIgnoreCase);
    }
}

public sealed class JwtOptions
{
    public string Issuer { get; set; } = string.Empty;

    public string Audience { get; set; } = string.Empty;

    public string SigningKey { get; set; } = string.Empty;

    public int AccessTokenMinutes { get; set; } = 15;
}

public sealed class RefreshTokenOptions
{
    public int LifetimeDays { get; set; } = 30;

    public int RotationGraceSeconds { get; set; } = 10;
}

public sealed class SecurityTokenOptions
{
    public int VerificationHours { get; set; } = 24;

    public int PasswordResetMinutes { get; set; } = 30;
}

public sealed class MfaOptions
{
    public int ChallengeMinutes { get; set; } = 5;

    public int MaxAttempts { get; set; } = 5;

    public int RecoveryCodeCount { get; set; } = 10;

    public int AdminSessionMinutes { get; set; } = 60;
}

public sealed class SecurityHashOptions
{
    public string IpHashPepper { get; set; } = string.Empty;

    public string RecoveryCodePepper { get; set; } = string.Empty;

    public string RecoveryCodePepperVersion { get; set; } = "v1";
}
