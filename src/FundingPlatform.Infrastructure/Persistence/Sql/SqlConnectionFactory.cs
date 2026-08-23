using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Persistence.Sql;

public sealed class SqlConnectionFactory : ISqlConnectionFactory
{
    public const string ConfigurationKey = "ConnectionStrings:DefaultConnection";

    private readonly string connectionString;

    public SqlConnectionFactory(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        connectionString = configuration.GetConnectionString("DefaultConnection") ?? string.Empty;
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                $"La configuración '{ConfigurationKey}' no está configurada.");
        }

        try
        {
            _ = new SqlConnectionStringBuilder(connectionString);
        }
        catch (ArgumentException)
        {
            throw new InvalidOperationException(
                $"La configuración '{ConfigurationKey}' no es válida.");
        }
    }

    public SqlConnection CreateConnection() => new(connectionString);
}
