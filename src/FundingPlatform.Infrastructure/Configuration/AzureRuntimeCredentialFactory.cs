using Azure.Core;
using Azure.Identity;

namespace FundingPlatform.Infrastructure.Configuration;

/// <summary>
/// Keeps production services on Managed Identity only. Developer credential
/// chains remain available exclusively for local development.
/// </summary>
public static class AzureRuntimeCredentialFactory
{
    public static TokenCredential Create(
        Guid? managedIdentityClientId,
        string environmentName)
    {
        if (string.Equals(
                environmentName, "Development", StringComparison.OrdinalIgnoreCase))
        {
            return new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                ManagedIdentityClientId = managedIdentityClientId?.ToString("D")
            });
        }

        return managedIdentityClientId.HasValue
            ? new ManagedIdentityCredential(
                ManagedIdentityId.FromUserAssignedClientId(
                    managedIdentityClientId.Value.ToString("D")))
            : new ManagedIdentityCredential(ManagedIdentityId.SystemAssigned);
    }
}
