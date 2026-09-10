using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed record ImportDispatchSettings(bool Enabled, bool UseDevelopmentStorage = false,
    Uri? QueueUri = null, Guid? ManagedIdentityClientId = null);

public static class ImportDispatchConfiguration
{
    public static ImportDispatchSettings Resolve(IConfiguration configuration, bool isDevelopment)
    {
        if (!configuration.GetValue<bool>("ImportDispatch:Enabled")) return new(false);
        var local = configuration.GetValue<bool>("ImportDispatch:UseDevelopmentStorage");
        var endpoint = configuration["ImportDispatch:QueueServiceUri"];
        var clientId = configuration["ImportDispatch:ManagedIdentityClientId"];
        if (local)
        {
            if (!isDevelopment || !string.IsNullOrWhiteSpace(endpoint) ||
                !string.IsNullOrWhiteSpace(clientId))
                throw new InvalidOperationException("Import dispatch Azurite is local-only and cannot mix identity modes.");
            return new(true, true);
        }
        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || !uri.IsDefaultPort ||
            !uri.Host.EndsWith(".queue.core.windows.net", StringComparison.OrdinalIgnoreCase) ||
            uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) ||
            !Guid.TryParseExact(clientId, "D", out var identity) || identity == Guid.Empty)
            throw new InvalidOperationException("Import dispatch requires a credential-free Azure queue endpoint and explicit managed identity.");
        var account = uri.Host[..^".queue.core.windows.net".Length];
        if (account.Length is < 3 or > 24 || account.Any(c => !char.IsAsciiLetterLower(c) && !char.IsAsciiDigit(c)))
            throw new InvalidOperationException("Invalid import dispatch storage account.");
        return new(true, QueueUri: new Uri(uri, "imports"), ManagedIdentityClientId: identity);
    }
}
