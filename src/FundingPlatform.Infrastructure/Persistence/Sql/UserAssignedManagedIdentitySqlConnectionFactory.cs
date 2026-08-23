using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Persistence.Sql;

/// <summary>
/// Creates Azure SQL connections pinned to one user-assigned managed identity.
/// This avoids the credential-chain ambiguity of Active Directory Default in
/// a least-privileged worker host.
/// </summary>
public sealed class UserAssignedManagedIdentitySqlConnectionFactory : ISqlConnectionFactory
{
    private readonly string connectionString;

    public UserAssignedManagedIdentitySqlConnectionFactory(
        IConfiguration configuration,
        Guid managedIdentityClientId)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        if (managedIdentityClientId == Guid.Empty)
            throw new ArgumentException(
                "A non-empty user-assigned managed identity client ID is required.",
                nameof(managedIdentityClientId));

        var configured = configuration.GetConnectionString("DefaultConnection");
        if (string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException(
                $"La configuración '{SqlConnectionFactory.ConfigurationKey}' no está configurada.");

        SqlConnectionStringBuilder builder;
        try
        {
            builder = new SqlConnectionStringBuilder(configured);
        }
        catch (ArgumentException)
        {
            throw new InvalidOperationException(
                $"La configuración '{SqlConnectionFactory.ConfigurationKey}' no es válida.");
        }

        var expectedClientId = managedIdentityClientId.ToString("D");
        if (builder.Authentication is not
                (SqlAuthenticationMethod.ActiveDirectoryDefault or
                 SqlAuthenticationMethod.ActiveDirectoryManagedIdentity) ||
            builder.IntegratedSecurity || !string.IsNullOrEmpty(builder.Password) ||
            builder.TrustServerCertificate ||
            builder.Encrypt.Equals(SqlConnectionEncryptOption.Optional) ||
            !string.IsNullOrWhiteSpace(builder.UserID) &&
                !string.Equals(builder.UserID.Trim(), expectedClientId,
                    StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(
                "The extraction worker SQL connection must use encrypted Microsoft Entra authentication without credentials and must match its configured managed identity.");

        // Setting an empty Password still preserves the keyword, and SqlClient
        // rejects any password keyword with Managed Identity authentication.
        builder.Remove("Password");
        builder.Remove("Pwd");
        builder.Authentication = SqlAuthenticationMethod.ActiveDirectoryManagedIdentity;
        builder.UserID = expectedClientId;
        builder.IntegratedSecurity = false;
        builder.PersistSecurityInfo = false;
        connectionString = builder.ConnectionString;
    }

    public SqlConnection CreateConnection() => new(connectionString);
}
