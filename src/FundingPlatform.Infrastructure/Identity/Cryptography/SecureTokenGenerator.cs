using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Identity.Cryptography;

public sealed class SecureTokenGenerator
{
    private readonly byte[] _ipHashPepper;
    private readonly byte[] _recoveryCodePepper;

    public SecureTokenGenerator(IOptions<AuthenticationOptions> options)
    {
        ArgumentNullException.ThrowIfNull(options);
        _ipHashPepper = Convert.FromBase64String(options.Value.SecurityHash.IpHashPepper);
        _recoveryCodePepper = Convert.FromBase64String(
            options.Value.SecurityHash.RecoveryCodePepper);
    }

    public static string GenerateOpaqueToken(int byteLength = 32)
    {
        if (byteLength < 16)
        {
            throw new ArgumentOutOfRangeException(
                nameof(byteLength),
                "Security tokens must contain at least 128 bits of entropy.");
        }

        return Base64UrlEncode(RandomNumberGenerator.GetBytes(byteLength));
    }

    public static byte[] HashOpaqueToken(string token)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(token);
        return SHA256.HashData(Encoding.UTF8.GetBytes(token));
    }

    public byte[]? HashIpAddress(string? ipAddress)
    {
        if (string.IsNullOrWhiteSpace(ipAddress))
        {
            return null;
        }

        return HMACSHA256.HashData(
            _ipHashPepper,
            Encoding.UTF8.GetBytes(ipAddress.Trim()));
    }

    public string GenerateRecoveryCode()
    {
        var raw = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        return string.Join('-', Enumerable.Range(0, 4).Select(index => raw.Substring(index * 8, 8)));
    }

    public byte[] HashRecoveryCode(string recoveryCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(recoveryCode);
        var normalized = recoveryCode.Replace("-", string.Empty, StringComparison.Ordinal)
            .Trim()
            .ToUpperInvariant();
        return HMACSHA256.HashData(
            _recoveryCodePepper,
            Encoding.UTF8.GetBytes(normalized));
    }

    private static string Base64UrlEncode(ReadOnlySpan<byte> value)
    {
        return Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
