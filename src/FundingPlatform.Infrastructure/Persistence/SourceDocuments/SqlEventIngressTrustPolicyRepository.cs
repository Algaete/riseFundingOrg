using System.Data;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlEventIngressTrustPolicyRepository(
    ISqlConnectionFactory connectionFactory) : IEventIngressTrustPolicyRepository
{
    public async Task<EventIngressTrustPolicyMutation> UpsertAsync(
        EventIngressTrustPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<Row>(new CommandDefinition(
                "dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert",
                new
                {
                    SuperAdminUserPublicId = command.SuperAdminUserId,
                    PolicyPublicId = command.PolicyId,
                    command.ExpectedRowVersion,
                    command.TenantId,
                    command.PrincipalObjectId,
                    command.ApplicationClientId,
                    ExpectedTopicResourceId = command.TopicResourceId,
                    command.EventSubscriptionName,
                    command.StorageAccountResourceId,
                    command.StorageAccountHost,
                    QuarantineBlobContainer = command.QuarantineContainer,
                    command.IsEnabled,
                    ValidFromUtc = command.ValidFromUtc.UtcDateTime,
                    ExpiresAtUtc = command.ExpiresAtUtc?.UtcDateTime,
                    command.Reason,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    command.CorrelationId,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new EventIngressTrustPolicyMutation(
                row.Succeeded,
                row.Code,
                row.PolicyPublicId,
                row.IsEnabled,
                row.RowVersion,
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(
                "configure Defender Event Grid trust policy", exception.Number);
        }
    }

    private sealed class Row
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? PolicyPublicId { get; init; }
        public bool? IsEnabled { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
    }
}
