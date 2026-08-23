using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed record DocumentExtractionQueueStorageSettings(
    string? DevelopmentConnectionString,
    Uri? QueueServiceUri,
    Guid? ManagedIdentityClientId = null,
    Guid? SenderManagedIdentityClientId = null)
{
    public bool UsesManagedIdentity => QueueServiceUri is not null;
}

public static class DocumentExtractionQueueStorageConfiguration
{
    public const string ConnectionName = "DocumentExtractionQueueStorage";

    public static DocumentExtractionQueueStorageSettings Resolve(
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var environment = Normalize(configuration["AZURE_FUNCTIONS_ENVIRONMENT"])
            ?? Normalize(configuration["DOTNET_ENVIRONMENT"]);
        var isDevelopment = string.Equals(
            environment, "Development", StringComparison.OrdinalIgnoreCase);
        var connectionString = Normalize(configuration[ConnectionName]);
        var accountName = Normalize(configuration[$"{ConnectionName}:accountName"]);
        var queueServiceValue = Normalize(configuration[$"{ConnectionName}:queueServiceUri"]);
        var credential = Normalize(configuration[$"{ConnectionName}:credential"]);
        var clientIdValue = Normalize(configuration[$"{ConnectionName}:clientId"]);
        var senderClientIdValue =
            Normalize(configuration[$"{ConnectionName}:senderClientId"]);

        // Local Azurite may use the same emulator bytes under two logical
        // connection names. Production never falls back to host storage.
        if (connectionString is null && accountName is null && queueServiceValue is null &&
            isDevelopment && string.Equals(
                Normalize(configuration[ImportQueueStorageConfiguration.HostStorageKey]),
                "UseDevelopmentStorage=true",
                StringComparison.OrdinalIgnoreCase))
        {
            connectionString = "UseDevelopmentStorage=true";
        }

        if (Convert.ToInt32(connectionString is not null) +
            Convert.ToInt32(accountName is not null) +
            Convert.ToInt32(queueServiceValue is not null) != 1)
        {
            throw new InvalidOperationException(
                "Configure exactly one DocumentExtractionQueueStorage mode: local Azurite, accountName, or queueServiceUri.");
        }

        if (connectionString is not null)
        {
            if (!isDevelopment || !string.Equals(
                    connectionString, "UseDevelopmentStorage=true",
                    StringComparison.OrdinalIgnoreCase) ||
                credential is not null || clientIdValue is not null ||
                senderClientIdValue is not null)
            {
                throw new InvalidOperationException(
                    "DocumentExtractionQueueStorage connection strings are restricted to local Azurite.");
            }
            return new DocumentExtractionQueueStorageSettings(connectionString, null);
        }

        if (!string.Equals(credential, "managedidentity", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "DocumentExtractionQueueStorage identity mode requires credential=managedidentity.");
        }

        Guid? clientId = null;
        if (clientIdValue is not null)
        {
            if (!Guid.TryParseExact(clientIdValue, "D", out var parsed) || parsed == Guid.Empty)
                throw new InvalidOperationException(
                    "DocumentExtractionQueueStorage:clientId must be a canonical non-empty GUID.");
            clientId = parsed;
        }

        Guid? senderClientId = null;
        if (senderClientIdValue is not null)
        {
            if (!Guid.TryParseExact(senderClientIdValue, "D", out var parsed) ||
                parsed == Guid.Empty)
                throw new InvalidOperationException(
                    "DocumentExtractionQueueStorage:senderClientId must be a canonical non-empty GUID.");
            senderClientId = parsed;
        }

        if (!isDevelopment &&
            (clientId is null || senderClientId is null || clientId == senderClientId))
            throw new InvalidOperationException(
                "Hosted document extraction requires distinct user-assigned identities for the queue sender and extraction consumer.");
        if (!isDevelopment)
            EnsureDistinctFromHostIdentity(configuration, clientId!.Value, senderClientId!.Value);

        Uri queueServiceUri;
        if (accountName is not null)
        {
            if (accountName.Length is < 3 or > 24 || accountName.Any(character =>
                    !((character >= 'a' && character <= 'z') ||
                      (character >= '0' && character <= '9'))))
                throw new InvalidOperationException(
                    "DocumentExtractionQueueStorage:accountName is invalid.");
            queueServiceUri = new Uri(
                $"https://{accountName}.queue.core.windows.net", UriKind.Absolute);
        }
        else
        {
            if (!Uri.TryCreate(queueServiceValue, UriKind.Absolute, out var parsed) ||
                parsed.Scheme != Uri.UriSchemeHttps || !parsed.IsDefaultPort ||
                parsed.AbsolutePath != "/" || !string.IsNullOrEmpty(parsed.UserInfo) ||
                !string.IsNullOrEmpty(parsed.Query) || !string.IsNullOrEmpty(parsed.Fragment) ||
                !parsed.Host.EndsWith(".queue.core.windows.net", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    "DocumentExtractionQueueStorage:queueServiceUri must be a credential-free Azure Queue HTTPS endpoint.");
            queueServiceUri = parsed;
        }

        EnsureDistinctFromHost(configuration, queueServiceUri);
        return new DocumentExtractionQueueStorageSettings(
            null, queueServiceUri, clientId, senderClientId);
    }

    public static void EnsureHostStorageIsolatedFromDocumentBlobs(
        ImportQueueStorageSettings hostStorage,
        Uri documentBlobServiceUri,
        string environmentName)
    {
        ArgumentNullException.ThrowIfNull(hostStorage);
        ArgumentNullException.ThrowIfNull(documentBlobServiceUri);
        if (string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase))
            return;
        if (hostStorage.QueueServiceUri is null ||
            !documentBlobServiceUri.Host.EndsWith(
                ".blob.core.windows.net", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(
                AccountLabel(hostStorage.QueueServiceUri),
                AccountLabel(documentBlobServiceUri),
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "The extraction Functions host storage account must be distinct from source-document Blob storage.");
        }
    }

    public static Guid? RequireExtractionManagedIdentity(
        DocumentExtractionQueueStorageSettings settings,
        string environmentName)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase))
            return settings.ManagedIdentityClientId;
        if (!settings.UsesManagedIdentity || settings.ManagedIdentityClientId is null)
            throw new InvalidOperationException(
                "The hosted extraction worker requires one explicit user-assigned managed identity client ID for its queue, trusted Blob reader, and Azure SQL connection.");
        return settings.ManagedIdentityClientId;
    }

    public static Guid? RequireSenderManagedIdentity(
        DocumentExtractionQueueStorageSettings settings,
        string environmentName)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase))
            return settings.SenderManagedIdentityClientId;
        if (!settings.UsesManagedIdentity || settings.ManagedIdentityClientId is null ||
            settings.SenderManagedIdentityClientId is null ||
            settings.ManagedIdentityClientId == settings.SenderManagedIdentityClientId)
            throw new InvalidOperationException(
                "The hosted document-extraction publisher requires a dedicated sender identity distinct from the extraction consumer identity.");
        return settings.SenderManagedIdentityClientId;
    }

    private static void EnsureDistinctFromHost(
        IConfiguration configuration,
        Uri documentQueueServiceUri)
    {
        var hostAccountName = Normalize(
            configuration[$"{ImportQueueStorageConfiguration.HostStorageKey}:accountName"]);
        var hostQueueValue = Normalize(
            configuration[$"{ImportQueueStorageConfiguration.HostStorageKey}:queueServiceUri"]);
        var hostLabel = hostAccountName?.ToLowerInvariant();
        if (hostLabel is null && Uri.TryCreate(hostQueueValue, UriKind.Absolute, out var hostQueue))
            hostLabel = AccountLabel(hostQueue);
        if (hostLabel is not null && string.Equals(
                hostLabel, AccountLabel(documentQueueServiceUri), StringComparison.Ordinal))
            throw new InvalidOperationException(
                "DocumentExtractionQueueStorage must not use the Functions host storage account.");
    }

    private static void EnsureDistinctFromHostIdentity(
        IConfiguration configuration,
        Guid consumerClientId,
        Guid senderClientId)
    {
        var hostClientIdValue = Normalize(
            configuration[$"{ImportQueueStorageConfiguration.HostStorageKey}:clientId"]);
        if (!Guid.TryParseExact(hostClientIdValue, "D", out var hostClientId) ||
            hostClientId == Guid.Empty || hostClientId == consumerClientId ||
            hostClientId == senderClientId)
            throw new InvalidOperationException(
                "The hosted Functions identity, document-extraction sender identity, and extraction-consumer identity must be three distinct user-assigned identities.");
    }

    private static string AccountLabel(Uri serviceUri) =>
        serviceUri.Host[..serviceUri.Host.IndexOf('.', StringComparison.Ordinal)]
            .ToLowerInvariant();

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
