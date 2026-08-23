using System.Globalization;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.Infrastructure.Identity.Cryptography;

public sealed class JwtTokenIssuer
{
    private readonly JwtOptions _options;
    private readonly TimeProvider _timeProvider;
    private readonly SigningCredentials _signingCredentials;

    public JwtTokenIssuer(
        IOptions<AuthenticationOptions> options,
        TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(options);
        _options = options.Value.Jwt;
        _timeProvider = timeProvider;
        _signingCredentials = new SigningCredentials(
            new SymmetricSecurityKey(Convert.FromBase64String(_options.SigningKey)),
            SecurityAlgorithms.HmacSha512);
    }

    public IssuedAccessToken Issue(
        PlatformUser user,
        IReadOnlyCollection<string> roles,
        Guid jwtId,
        bool mfaAuthenticated,
        string authorizationLevel = "full",
        DateTime? authenticationTimeUtc = null)
    {
        ArgumentNullException.ThrowIfNull(user);
        ArgumentNullException.ThrowIfNull(roles);

        var now = _timeProvider.GetUtcNow();
        var authenticationTime = authenticationTimeUtc.HasValue
            ? new DateTimeOffset(
                DateTime.SpecifyKind(authenticationTimeUtc.Value, DateTimeKind.Utc))
            : now;
        var expires = now.AddMinutes(_options.AccessTokenMinutes);
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.PublicId.ToString("D")),
            new(JwtRegisteredClaimNames.Jti, jwtId.ToString("D")),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new(ClaimTypes.NameIdentifier, user.PublicId.ToString("D")),
            new(ClaimTypes.Name, user.DisplayName),
            new("sv", user.SecurityVersion.ToString(CultureInfo.InvariantCulture)),
            new("auth_level", authorizationLevel),
            new("amr", mfaAuthenticated ? "mfa" : "pwd"),
            new("auth_time", authenticationTime.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture))
        };

        claims.AddRange(roles.Select(role => new Claim(ClaimTypes.Role, role)));

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: claims,
            notBefore: now.UtcDateTime,
            expires: expires.UtcDateTime,
            signingCredentials: _signingCredentials);

        return new IssuedAccessToken(
            new JwtSecurityTokenHandler().WriteToken(token),
            expires.UtcDateTime,
            jwtId);
    }
}

public sealed record IssuedAccessToken(
    string Token,
    DateTime ExpiresAtUtc,
    Guid JwtId);
