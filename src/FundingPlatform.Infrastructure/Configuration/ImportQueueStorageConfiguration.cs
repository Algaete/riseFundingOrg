using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed record ImportQueueStorageSettings(
    string? DevelopmentConnectionString,
    Uri? QueueServiceUri,
    Guid? ManagedIdentityClientId = null)
{
    public bool UsesManagedIdentity => QueueServiceUri is not null;
}

public static class ImportQueueStorageConfiguration
{
    public const string HostStorageKey = "AzureWebJobsStorage";

    public static ImportQueueStorageSettings Resolve(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString = Normalize(configuration[HostStorageKey]);
        var accountName = Normalize(configuration[$"{HostStorageKey}:accountName"]);
        var queueServiceValue = Normalize(configuration[$"{HostStorageKey}:queueServiceUri"]);
        var blobServiceValue = Normalize(configuration[$"{HostStorageKey}:blobServiceUri"]);
        var credential = Normalize(configuration[$"{HostStorageKey}:credential"]);
        var clientIdValue = Normalize(configuration[$"{HostStorageKey}:clientId"]);
        var hasConnectionString = connectionString is not null;
        var hasAccountName = accountName is not null;
        var hasExplicitEndpoints = queueServiceValue is not null || blobServiceValue is not null;

        if (Convert.ToInt32(hasConnectionString) + Convert.ToInt32(hasAccountName) +
            Convert.ToInt32(hasExplicitEndpoints) != 1)
        {
            throw new InvalidOperationException(
                "Configure exactly one AzureWebJobsStorage mode: Azurite, accountName, or the queue/blob service URI pair.");
        }

        if (hasConnectionString)
        {
            if (IsHostedEnvironment(configuration))
            {
                throw new InvalidOperationException(
                    "Azurite host storage is allowed only in the Development environment.");
            }

            if (credential is not null || clientIdValue is not null)
            {
                throw new InvalidOperationException(
                    "Azurite host storage cannot be combined with managed identity settings.");
            }

            if (!string.Equals(
                    connectionString,
                    "UseDevelopmentStorage=true",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "AzureWebJobsStorage connection strings are restricted to Azurite; use identity-based host settings in Azure.");
            }

            return new ImportQueueStorageSettings(connectionString, null);
        }

        if (credential is not null &&
            !string.Equals(credential, "managedidentity", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "AzureWebJobsStorage:credential only supports managedidentity.");
        }

        Guid? managedIdentityClientId = null;
        if (clientIdValue is not null)
        {
            if (!Guid.TryParseExact(clientIdValue, "D", out var parsedClientId) ||
                parsedClientId == Guid.Empty || credential is null)
            {
                throw new InvalidOperationException(
                    "AzureWebJobsStorage:clientId requires a canonical non-empty GUID and credential=managedidentity.");
            }

            managedIdentityClientId = parsedClientId;
        }

        if (IsHostedEnvironment(configuration) &&
            (credential is null || managedIdentityClientId is null))
        {
            throw new InvalidOperationException(
                "Hosted identity-based storage requires credential=managedidentity and an explicit user-assigned AzureWebJobsStorage:clientId.");
        }

        if (hasAccountName)
        {
            if (accountName!.Length is < 3 or > 24 ||
                accountName.Any(character =>
                    (character < 'a' || character > 'z') &&
                    (character < '0' || character > '9')))
            {
                throw new InvalidOperationException(
                    "AzureWebJobsStorage:accountName is not a valid Azure Storage account name.");
            }

            return new ImportQueueStorageSettings(
                null,
                new Uri($"https://{accountName}.queue.core.windows.net", UriKind.Absolute),
                managedIdentityClientId);
        }

        if (queueServiceValue is null || blobServiceValue is null)
        {
            throw new InvalidOperationException(
                "Identity-based explicit host storage requires both AzureWebJobsStorage:queueServiceUri and AzureWebJobsStorage:blobServiceUri.");
        }

        var queueServiceUri = ValidateServiceUri(queueServiceValue, "queue");
        var blobServiceUri = ValidateServiceUri(blobServiceValue, "blob");
        if (!string.Equals(
                GetAccountLabel(queueServiceUri),
                GetAccountLabel(blobServiceUri),
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "AzureWebJobsStorage queue and blob endpoints must belong to the same Storage account.");
        }

        return new ImportQueueStorageSettings(
            null, queueServiceUri, managedIdentityClientId);
    }

    private static Uri ValidateServiceUri(string value, string service)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps ||
            !uri.IsDefaultPort ||
            !uri.Host.EndsWith($".{service}.core.windows.net", StringComparison.OrdinalIgnoreCase) ||
            uri.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment))
        {
            throw new InvalidOperationException(
                $"AzureWebJobsStorage:{service}ServiceUri must be a credential-free HTTPS Azure Storage {service} endpoint.");
        }

        return uri;
    }

    private static string GetAccountLabel(Uri uri) =>
        uri.Host[..uri.Host.IndexOf('.', StringComparison.Ordinal)].ToLowerInvariant();

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static bool IsHostedEnvironment(IConfiguration configuration)
    {
        var environment = Normalize(configuration["AZURE_FUNCTIONS_ENVIRONMENT"])
            ?? Normalize(configuration["DOTNET_ENVIRONMENT"]);
        return !string.Equals(environment, "Development", StringComparison.OrdinalIgnoreCase);
    }
}
