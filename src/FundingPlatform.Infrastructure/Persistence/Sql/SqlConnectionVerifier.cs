using Dapper;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Sql;

public sealed class SqlConnectionVerifier(ISqlConnectionFactory connectionFactory)
{
    private const int CommandTimeoutSeconds = 15;

    public async Task<SqlConnectionCheckResult> CheckAsync(
        CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = connectionFactory.CreateConnection();
            var result = await connection.ExecuteScalarAsync<int>(new CommandDefinition(
                "SELECT 1",
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: cancellationToken));

            return result == 1
                ? new SqlConnectionCheckResult(true, "ok")
                : new SqlConnectionCheckResult(false, "unexpected_result");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (SqlException exception)
        {
            return new SqlConnectionCheckResult(
                false,
                "sql_select_one_failed",
                exception.Number);
        }
    }
}
