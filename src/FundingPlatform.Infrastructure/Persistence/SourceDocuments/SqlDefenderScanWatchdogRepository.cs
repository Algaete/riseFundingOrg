using System.Data;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlDefenderScanWatchdogRepository(
    ISqlConnectionFactory connectionFactory) : IDefenderScanWatchdogRepository
{
    public async Task<IReadOnlyList<DefenderScanWatchdogMutation>> TimeoutPendingAsync(
        int batchSize,
        int timeoutSeconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<Row>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout",
                new
                {
                    BatchSize = batchSize,
                    TimeoutSeconds = timeoutSeconds,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(row => new DefenderScanWatchdogMutation(
                row.SourceDocumentPublicId,
                (SourceDocumentStorageStatus)row.StorageStatus,
                (SourceDocumentScanStatus)row.ScanStatus,
                (SourceDocumentScanProvider)row.ScanProvider,
                row.ScanAttemptCount,
                row.RowVersion)).ToArray();
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(
                "timeout pending Defender scans", exception.Number);
        }
    }

    private sealed class Row
    {
        public Guid SourceDocumentPublicId { get; init; }
        public byte StorageStatus { get; init; }
        public byte ScanStatus { get; init; }
        public byte ScanProvider { get; init; }
        public short ScanAttemptCount { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }
}
