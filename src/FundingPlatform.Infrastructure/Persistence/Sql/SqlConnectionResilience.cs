using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Sql;

/// <summary>
/// Gives a paused Azure SQL database time to resume. This provider is assigned
/// only to SqlConnection: SQL commands and transactions must never be replayed.
/// </summary>
public static class SqlConnectionResilience
{
    private static readonly int[] TransientErrors =
        [-2, 40197, 40501, 40613, 10928, 10929, 49918, 49919, 49920];

    public static SqlRetryLogicBaseProvider CreateProvider() =>
        SqlConfigurableRetryFactory.CreateExponentialRetryProvider(new SqlRetryLogicOption
        {
            NumberOfTries = 4,
            DeltaTime = TimeSpan.FromSeconds(5),
            MinTimeInterval = TimeSpan.FromSeconds(5),
            MaxTimeInterval = TimeSpan.FromSeconds(15),
            TransientErrors = TransientErrors,
            AuthorizedSqlCondition = _ => false
        });

    // Repositories may wrap SqlException, and SqlClient aggregates exhausted
    // connection attempts. A mixed aggregate must not hide a permanent failure.
    public static bool IsTemporarilyUnavailable(Exception exception) =>
        IsTemporarilyUnavailable(exception, 0);

    private static bool IsTemporarilyUnavailable(Exception exception, int depth)
    {
        if (depth >= 16 || exception is OperationCanceledException) return false;
        return exception switch
        {
            SqlException sql => sql.Errors.Count > 0 && sql.Errors.Cast<SqlError>()
                .All(error => TransientErrors.Contains(error.Number)),
            AggregateException aggregate => aggregate.InnerExceptions.Count > 0 &&
                aggregate.InnerExceptions.All(inner => IsTemporarilyUnavailable(inner, depth + 1)),
            { InnerException: { } inner } => IsTemporarilyUnavailable(inner, depth + 1),
            _ => false
        };
    }
}
