using System.Data;
using Dapper;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.ProjectAssets;

public sealed class SqlProjectAssetDefenderScanWatchdogRepository(
    ISqlConnectionFactory connectionFactory) : IProjectAssetDefenderScanWatchdogRepository
{
    public async Task<IReadOnlyList<ProjectAssetDefenderScanWatchdogMutation>> TimeoutPendingAsync(
        int batchSize,
        int timeoutSeconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<Row>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout",
                new
                {
                    BatchSize = batchSize,
                    TimeoutSeconds = timeoutSeconds,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(row => new ProjectAssetDefenderScanWatchdogMutation(
                row.ProjectAssetPublicId,
                (ProjectAssetStorageStatus)row.StorageStatus,
                (ProjectAssetScanStatus)row.ScanStatus,
                (ProjectAssetScanProvider)row.ScanProvider,
                row.AssetRowVersion,
                row.ProjectRowVersion)).ToArray();
        }
        catch (SqlException exception)
        {
            throw new ProjectAssetDataException(
                "timeout pending project asset Defender scans",
                exception.Number,
                exception);
        }
    }

    private sealed class Row
    {
        public Guid ProjectAssetPublicId { get; init; }
        public byte StorageStatus { get; init; }
        public byte ScanStatus { get; init; }
        public byte ScanProvider { get; init; }
        public byte[] AssetRowVersion { get; init; } = [];
        public byte[] ProjectRowVersion { get; init; } = [];
    }
}
