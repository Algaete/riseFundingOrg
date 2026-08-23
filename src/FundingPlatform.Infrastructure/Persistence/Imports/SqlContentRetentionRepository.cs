using System.Data;
using Dapper;
using FundingPlatform.Application.Imports;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Imports;

public sealed class SqlContentRetentionRepository(
    ISqlConnectionFactory connectionFactory) : IContentRetentionRepository
{
    public async Task<ContentRetentionEnforcementResult> EnforceAsync(
        int batchSize,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 500)
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        if (nowUtc.Offset != TimeSpan.Zero)
            throw new ArgumentException("The retention timestamp must be UTC.", nameof(nowUtc));

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = (await connection.QueryAsync<RetentionRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ContentRetention_Enforce",
                new { BatchSize = batchSize, NowUtc = nowUtc.UtcDateTime },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 60,
                cancellationToken: cancellationToken))).AsList();

            return new ContentRetentionEnforcementResult(
                rows.Count,
                Sum(rows, static row => row.RawRedactedCount),
                Sum(rows, static row => row.ItemRedactedCount),
                Sum(rows, static row => row.ResultRedactedCount),
                Sum(rows, static row => row.EvidenceRedactedCount));
        }
        catch (SqlException exception)
        {
            throw new ContentRetentionDataException(exception.Number, exception);
        }
    }

    private static int Sum(
        IReadOnlyList<RetentionRow> rows,
        Func<RetentionRow, int> selector) => checked(rows.Sum(selector));

    private sealed class RetentionRow
    {
        public Guid RunPublicId { get; init; }
        public int RawRedactedCount { get; init; }
        public int ItemRedactedCount { get; init; }
        public int ResultRedactedCount { get; init; }
        public int EvidenceRedactedCount { get; init; }
        public DateTime StartedAtUtc { get; init; }
        public DateTime CompletedAtUtc { get; init; }
    }
}
