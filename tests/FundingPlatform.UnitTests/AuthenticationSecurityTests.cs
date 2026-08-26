using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity;
using FundingPlatform.Infrastructure.Identity.Configuration;
using FundingPlatform.Infrastructure.Identity.Cryptography;
using FundingPlatform.Infrastructure.Identity.Email;
using Microsoft.Extensions.Options;

namespace FundingPlatform.UnitTests;

public sealed class AuthenticationSecurityTests
{
    [Fact]
    public void Entra_configuration_is_optional_but_fail_fast_when_enabled()
    {
        Assert.True(ExternalAuthenticationOptions.IsValid(new ExternalAuthenticationOptions()));
        Assert.False(ExternalAuthenticationOptions.IsValid(new ExternalAuthenticationOptions
        {
            Entra = new EntraAuthenticationOptions { Enabled = true }
        }));
        Assert.True(ExternalAuthenticationOptions.IsValid(new ExternalAuthenticationOptions
        {
            Entra = new EntraAuthenticationOptions
            {
                Enabled = true,
                TenantId = EntraAuthenticationOptions.PublicTenant,
                ClientId = Guid.NewGuid().ToString(),
                ClientSecret = new string('x', 32)
            }
        }));
        Assert.False(ExternalAuthenticationOptions.IsValid(new ExternalAuthenticationOptions
        {
            Entra = new EntraAuthenticationOptions
            {
                Enabled = true,
                TenantId = Guid.NewGuid().ToString(),
                ClientId = Guid.NewGuid().ToString(),
                ClientSecret = new string('x', 32)
            }
        }));
    }

    [Theory]
    [InlineData("https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0")]
    [InlineData("https://login.microsoftonline.com/22222222-2222-2222-2222-222222222222/v2.0")]
    public void Entra_accepts_valid_v2_tenant_issuers(string issuer)
    {
        Assert.True(EntraAuthenticationOptions.IsSupportedTokenIssuer(issuer));
    }

    [Theory]
    [InlineData("https://login.microsoftonline.com/common/v2.0")]
    [InlineData("https://login.microsoftonline.com/not-a-tenant/v2.0")]
    [InlineData("https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111")]
    [InlineData("https://login.microsoftonline.com.evil.test/11111111-1111-1111-1111-111111111111/v2.0")]
    [InlineData("https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0?x=1")]
    public void Entra_rejects_untrusted_issuer_shapes(string issuer)
    {
        Assert.False(EntraAuthenticationOptions.IsSupportedTokenIssuer(issuer));
    }

    [Fact]
    public void Authentication_options_require_strong_bounded_configuration()
    {
        var valid = CreateOptions();

        Assert.True(AuthenticationOptions.IsValid(valid));

        valid.Jwt.SigningKey = Convert.ToBase64String(new byte[63]);
        Assert.False(AuthenticationOptions.IsValid(valid));

        valid = CreateOptions();
        valid.Jwt.Issuer = "http://insecure.example";
        Assert.False(AuthenticationOptions.IsValid(valid));

        valid = CreateOptions();
        valid.Mfa.RecoveryCodeCount = 21;
        Assert.False(AuthenticationOptions.IsValid(valid));

        valid = CreateOptions();
        valid.Mfa.AdminSessionMinutes = 61;
        Assert.False(AuthenticationOptions.IsValid(valid));
    }

    [Fact]
    public void Session_defaults_keep_customer_refresh_long_lived_and_admin_mfa_bounded()
    {
        var options = new AuthenticationOptions();

        Assert.Equal(15, options.Jwt.AccessTokenMinutes);
        Assert.Equal(30, options.RefreshToken.LifetimeDays);
        Assert.Equal(60, options.Mfa.AdminSessionMinutes);
    }

    [Fact]
    public async Task Explicitly_disabled_email_is_valid_and_sender_fails_without_echoing_input()
    {
        var options = new EmailOptions
        {
            Enabled = false,
            FrontendBaseUrl = "https://dev.risefunding.test"
        };
        var sender = new DisabledIdentityEmailSender();

        Assert.True(EmailOptions.IsValid(options));
        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            sender.SendVerificationAsync(
                "private@example.test",
                "Private User",
                "raw-secret-token",
                CancellationToken.None));

        Assert.Equal("identity_email_delivery_disabled", exception.Message);
        Assert.DoesNotContain("private@example.test", exception.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("raw-secret-token", exception.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void Enabled_email_still_requires_provider_and_sender_configuration()
    {
        Assert.False(EmailOptions.IsValid(new EmailOptions
        {
            Enabled = true,
            FrontendBaseUrl = "https://dev.risefunding.test"
        }));
        Assert.True(EmailOptions.IsValid(new EmailOptions
        {
            Enabled = true,
            Endpoint = "https://example.communication.azure.com",
            FromAddress = "noreply@example.test",
            FrontendBaseUrl = "https://dev.risefunding.test"
        }));
    }

    [Fact]
    public void Opaque_tokens_are_url_safe_random_and_sha256_hashed()
    {
        var first = SecureTokenGenerator.GenerateOpaqueToken();
        var second = SecureTokenGenerator.GenerateOpaqueToken();

        Assert.NotEqual(first, second);
        Assert.DoesNotContain("=", first, StringComparison.Ordinal);
        Assert.DoesNotContain("+", first, StringComparison.Ordinal);
        Assert.DoesNotContain("/", first, StringComparison.Ordinal);
        Assert.Equal(32, SecureTokenGenerator.HashOpaqueToken(first).Length);
        Assert.Equal(
            SecureTokenGenerator.HashOpaqueToken(first),
            SecureTokenGenerator.HashOpaqueToken(first));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            SecureTokenGenerator.GenerateOpaqueToken(15));
    }

    [Fact]
    public void Global_role_command_results_do_not_expose_raw_identity_fields()
    {
        var administratorFields = typeof(GlobalAdministratorSummary)
            .GetProperties()
            .Select(property => property.Name)
            .ToArray();
        var grantFields = typeof(GrantSuperAdminResult)
            .GetProperties()
            .Select(property => property.Name)
            .ToArray();

        Assert.Contains(nameof(GlobalAdministratorSummary.MaskedEmail), administratorFields);
        Assert.DoesNotContain("Email", administratorFields);
        Assert.DoesNotContain("DisplayName", administratorFields);
        Assert.DoesNotContain("PublicId", administratorFields);
        Assert.Contains(nameof(GrantSuperAdminResult.MaskedEmail), grantFields);
        Assert.DoesNotContain("Email", grantFields);
        Assert.DoesNotContain("DisplayName", grantFields);
        Assert.DoesNotContain("PublicId", grantFields);
    }

    [Fact]
    public void Context_and_recovery_hashes_are_peppered_and_normalized()
    {
        var generator = new SecureTokenGenerator(Options.Create(CreateOptions()));

        Assert.Null(generator.HashIpAddress(null));
        Assert.Equal(
            generator.HashIpAddress("203.0.113.10"),
            generator.HashIpAddress(" 203.0.113.10 "));
        Assert.NotEqual(
            generator.HashIpAddress("203.0.113.10"),
            generator.HashIpAddress("203.0.113.11"));

        var recoveryCode = generator.GenerateRecoveryCode();
        Assert.Matches("^[0-9A-F]{8}(?:-[0-9A-F]{8}){3}$", recoveryCode);
        Assert.Equal(
            generator.HashRecoveryCode(recoveryCode),
            generator.HashRecoveryCode(recoveryCode.Replace("-", string.Empty).ToLowerInvariant()));
    }

    [Fact]
    public void Jwt_contains_only_the_expected_session_claims_and_expiry()
    {
        var now = new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero);
        var issuer = new JwtTokenIssuer(
            Options.Create(CreateOptions()),
            new FixedTimeProvider(now));
        var publicId = Guid.Parse("f91a0a59-17d0-4ea1-9d95-24fcdb849c9b");
        var jwtId = Guid.Parse("953f47cf-89bc-418a-b175-24db76478afb");
        var user = new PlatformUser
        {
            PublicId = publicId,
            Email = "security@example.test",
            DisplayName = "Security Test",
            SecurityVersion = 7
        };

        var mfaAuthenticatedAtUtc = now.AddMinutes(-7).UtcDateTime;
        var issued = issuer.Issue(
            user,
            ["Admin"],
            jwtId,
            mfaAuthenticated: true,
            authenticationTimeUtc: mfaAuthenticatedAtUtc);
        var token = new JwtSecurityTokenHandler().ReadJwtToken(issued.Token);

        Assert.Equal("https://issuer.fundingplatform.test", token.Issuer);
        Assert.Contains("FundingPlatform.Tests", token.Audiences);
        Assert.Equal(publicId.ToString("D"), token.Subject);
        Assert.Equal(jwtId.ToString("D"), token.Id);
        Assert.Equal("7", token.Claims.Single(claim => claim.Type == "sv").Value);
        Assert.Equal("mfa", token.Claims.Single(claim => claim.Type == "amr").Value);
        Assert.Equal(
            now.AddMinutes(-7).ToUnixTimeSeconds().ToString(),
            token.Claims.Single(claim => claim.Type == "auth_time").Value);
        Assert.Equal("full", token.Claims.Single(claim => claim.Type == "auth_level").Value);
        Assert.Contains(token.Claims, claim => claim.Type == ClaimTypes.Role && claim.Value == "Admin");
        Assert.Equal(now.AddMinutes(10).UtcDateTime, issued.ExpiresAtUtc);
        Assert.DoesNotContain(token.Claims, claim => claim.Type.Contains("password", StringComparison.OrdinalIgnoreCase));
    }

    private static AuthenticationOptions CreateOptions()
    {
        return new AuthenticationOptions
        {
            Jwt = new JwtOptions
            {
                Issuer = "https://issuer.fundingplatform.test",
                Audience = "FundingPlatform.Tests",
                SigningKey = Convert.ToBase64String(Enumerable.Repeat((byte)0xA5, 64).ToArray()),
                AccessTokenMinutes = 10
            },
            SecurityHash = new SecurityHashOptions
            {
                IpHashPepper = Convert.ToBase64String(Enumerable.Repeat((byte)0xB6, 32).ToArray()),
                RecoveryCodePepper = Convert.ToBase64String(Enumerable.Repeat((byte)0xC7, 32).ToArray()),
                RecoveryCodePepperVersion = "test-v1"
            }
        };
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
