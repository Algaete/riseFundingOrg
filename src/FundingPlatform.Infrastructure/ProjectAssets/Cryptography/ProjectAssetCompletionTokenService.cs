using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.ProjectAssets;

namespace FundingPlatform.Infrastructure.ProjectAssets.Cryptography;

public sealed class ProjectAssetCompletionTokenService : IProjectAssetCompletionTokenService
{
    private const int TokenBytes = 32;

    public ProjectAssetCompletionSecret Create()
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(TokenBytes))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
        return new ProjectAssetCompletionSecret(
            token,
            SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    }

    public bool TryHash(string token, out byte[] hash)
    {
        hash = [];
        if (string.IsNullOrWhiteSpace(token) || token.Length is < 40 or > 64 ||
            token.Any(character => !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_'))
            return false;
        hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return true;
    }
}
