using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.Infrastructure.SourceDocuments.Cryptography;

public sealed class SourceDocumentCompletionTokenService : ISourceDocumentCompletionTokenService
{
    private const int TokenByteLength = 32;
    private const int EncodedTokenLength = 43;

    public SourceDocumentCompletionSecret Create()
    {
        var token = Base64UrlEncode(RandomNumberGenerator.GetBytes(TokenByteLength));
        return new SourceDocumentCompletionSecret(
            token,
            SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    }

    public bool TryHash(string token, out byte[] hash)
    {
        hash = [];
        if (token.Length != EncodedTokenLength || !TryDecode(token, out var bytes) ||
            bytes.Length != TokenByteLength)
            return false;
        CryptographicOperations.ZeroMemory(bytes);
        hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return true;
    }

    private static string Base64UrlEncode(byte[] value) =>
        Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private static bool TryDecode(string value, out byte[] bytes)
    {
        bytes = [];
        try
        {
            var normalized = value.Replace('-', '+').Replace('_', '/');
            normalized += new string('=', (4 - normalized.Length % 4) % 4);
            bytes = Convert.FromBase64String(normalized);
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
