using System.Data;
using Dapper;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Imports;

public sealed class SqlImportOutboxRepository(
    ISqlConnectionFactory connectionFactory) : IImportOutboxRepository
{
    public async Task<IReadOnlyList<ImportOutboxMessage>> ClaimAsync(
        string leaseOwner,
        int batchSize,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<OutboxRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRunOutbox_Claim",
                new
                {
                    LeaseOwner = leaseOwner,
                    BatchSize = batchSize,
                    LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return rows.Select(row => new ImportOutboxMessage(
                row.MessageId, row.MessageType, row.PayloadJson, row.AttemptCount)).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("claim import outbox messages", exception);
        }
    }

    public Task CompleteAsync(
        Guid messageId,
        string leaseOwner,
        DateTimeOffset dispatchedAtUtc,
        CancellationToken cancellationToken) => ExecuteAsync(
            "dbo.FundingPlatform_usp_Outbox_Complete",
            new
            {
                MessageId = messageId,
                LeaseOwner = leaseOwner,
                DispatchedAtUtc = dispatchedAtUtc.UtcDateTime
            },
            "complete import outbox message",
            cancellationToken);

    public Task ReleaseAsync(
        Guid messageId,
        string leaseOwner,
        DateTimeOffset availableAtUtc,
        string errorCode,
        CancellationToken cancellationToken) => ExecuteAsync(
            "dbo.FundingPlatform_usp_Outbox_Release",
            new
            {
                MessageId = messageId,
                LeaseOwner = leaseOwner,
                AvailableAtUtc = availableAtUtc.UtcDateTime,
                ErrorCode = errorCode
            },
            "release import outbox message",
            cancellationToken);

    private async Task ExecuteAsync(
        string procedure,
        object parameters,
        string operation,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static ImportRunDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed record OutboxRow(
        long Id,
        Guid MessageId,
        string MessageType,
        string AggregateType,
        string AggregateId,
        string PayloadJson,
        DateTime OccurredAtUtc,
        short AttemptCount,
        DateTime LeaseUntilUtc);
}
