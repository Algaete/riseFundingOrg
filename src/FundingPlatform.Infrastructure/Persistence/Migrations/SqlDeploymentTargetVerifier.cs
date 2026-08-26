using Dapper;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed class SqlDeploymentTargetVerifier
{
    private const int CommandTimeoutSeconds = 30;
    private readonly ISqlConnectionFactory connectionFactory;
    private readonly string expectedDatabaseName;
    private readonly string? expectedServerFqdn;

    public SqlDeploymentTargetVerifier(
        ISqlConnectionFactory connectionFactory,
        string? configuredDatabaseName = null,
        string? configuredServerFqdn = null,
        bool requireExpectedServer = false)
    {
        ArgumentNullException.ThrowIfNull(connectionFactory);
        this.connectionFactory = connectionFactory;
        expectedDatabaseName =
            MigrationSafety.ResolveExpectedDatabaseName(configuredDatabaseName);
        expectedServerFqdn =
            MigrationSafety.ResolveExpectedServerFqdn(configuredServerFqdn);
        if (requireExpectedServer && expectedServerFqdn is null)
        {
            throw new MigrationException("expected_sql_server_fqdn_required");
        }
    }

    public string ExpectedDatabaseName => expectedDatabaseName;

    public string? ExpectedServerFqdn => expectedServerFqdn;

    public async Task<SqlDeploymentTarget> VerifyAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        return await VerifyConnectionAsync(
            connection, transaction: null, cancellationToken);
    }

    internal async Task<SqlDeploymentTarget> VerifyConnectionAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(connection);
        var observed = await connection.QuerySingleAsync<ObservedSqlTarget>(new CommandDefinition(
            """
            SELECT
                CONVERT(nvarchar(128), DB_NAME()) AS DatabaseName,
                CONVERT(nvarchar(256), SERVERPROPERTY(N'ServerName')) AS ServerName;
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        if (!MigrationSafety.IsExpectedDatabase(
            observed.DatabaseName, expectedDatabaseName))
        {
            throw new MigrationException("unexpected_target_database");
        }

        var configuredDataSource = NormalizeDataSource(connection.DataSource);
        if (expectedServerFqdn is not null)
        {
            if (!string.Equals(
                    configuredDataSource,
                    expectedServerFqdn,
                    StringComparison.OrdinalIgnoreCase) ||
                !ServerPropertyMatches(observed.ServerName, expectedServerFqdn))
            {
                throw new MigrationException("unexpected_target_sql_server");
            }
        }

        return new SqlDeploymentTarget(
            observed.DatabaseName,
            configuredDataSource,
            SanitizeServerProperty(observed.ServerName));
    }

    internal static string NormalizeDataSource(string? dataSource)
    {
        if (string.IsNullOrWhiteSpace(dataSource))
        {
            return string.Empty;
        }

        var normalized = dataSource.Trim();
        if (normalized.StartsWith("tcp:", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized[4..];
        }

        var comma = normalized.LastIndexOf(',');
        if (comma >= 0)
        {
            var port = normalized[(comma + 1)..].Trim();
            if (!string.Equals(port, "1433", StringComparison.Ordinal))
            {
                return string.Empty;
            }
            normalized = normalized[..comma].Trim();
        }

        return normalized.ToLowerInvariant();
    }

    internal static bool ServerPropertyMatches(
        string? observedServerName,
        string expectedServerFqdn)
    {
        if (string.IsNullOrWhiteSpace(observedServerName))
        {
            return false;
        }

        var observed = observedServerName.Trim();
        var expectedShortName = expectedServerFqdn.Split('.')[0];
        return string.Equals(observed, expectedServerFqdn, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(observed, expectedShortName, StringComparison.OrdinalIgnoreCase);
    }

    private static string SanitizeServerProperty(string? value) =>
        new((value ?? string.Empty).Where(character =>
                char.IsAsciiLetterOrDigit(character) || character is '-' or '.')
            .Take(253)
            .ToArray());

    private sealed record ObservedSqlTarget(string DatabaseName, string? ServerName);
}

public sealed record SqlDeploymentTarget(
    string DatabaseName,
    string ConfiguredServerFqdn,
    string ObservedServerName);
