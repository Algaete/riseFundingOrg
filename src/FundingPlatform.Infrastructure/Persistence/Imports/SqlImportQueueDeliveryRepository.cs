using System.Data;
using Dapper;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Imports;

public sealed class SqlImportQueueDeliveryRepository(ISqlConnectionFactory connectionFactory)
    : IImportQueueDeliveryRepository
{
    public async Task<ImportQueueDeliveryState?> GetAsync(Guid runId, bool confirmReceipt,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<DeliveryRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_QueueDelivery",
                new { RunPublicId = runId, ConfirmReceipt = confirmReceipt },
                commandType: CommandType.StoredProcedure, cancellationToken: cancellationToken));
            return row is null ? null : new((ImportRunStatus)row.Status,
                Utc(row.NextAttemptAtUtc), Utc(row.LeaseUntilUtc));
        }
        catch (SqlException exception)
        {
            throw new ImportRunDataException("read import queue delivery", exception.Number, exception);
        }
    }

    private static DateTimeOffset? Utc(DateTime? value) => value.HasValue
        ? new DateTimeOffset(DateTime.SpecifyKind(value.Value, DateTimeKind.Utc)) : null;
    private sealed record DeliveryRow(byte Status, DateTime? NextAttemptAtUtc, DateTime? LeaseUntilUtc);
}
