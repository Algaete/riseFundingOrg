using System.Data;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlDefenderScanReceiptRepository(
    ISqlConnectionFactory connectionFactory) : IDefenderScanReceiptRepository
{
    public async Task<DefenderReceiptWork> RecordAsync(
        string eventGridEventId,
        byte[] payloadHash,
        EventGridCaller caller,
        string eventSubscriptionName,
        string topicResourceId,
        string storageAccountResourceId,
        string blobHost,
        ProtectedBlobLocation quarantineLocation,
        string blobETag,
        byte[]? reportedContentHash,
        SourceDocumentScanStatus status,
        string resultCode,
        DateTimeOffset occurredAtUtc,
        DateTimeOffset receivedAtUtc,
        CancellationToken cancellationToken)
    {
        var row = await QueryAsync<RecordRow>(
            "dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record",
            "record Defender receipt",
            new
            {
                ProviderEventId = eventGridEventId,
                PayloadHash = payloadHash,
                AuthenticatedTenantId = caller.TenantId,
                AuthenticatedPrincipalId = caller.PrincipalId,
                ApplicationClientId = caller.ApplicationId,
                EventSubscriptionName = eventSubscriptionName,
                TopicResourceId = topicResourceId,
                StorageAccountResourceId = storageAccountResourceId,
                BlobHost = blobHost,
                BlobContainer = quarantineLocation.Container,
                BlobObjectName = quarantineLocation.ObjectName,
                BlobETag = blobETag,
                ReportedContentHash = reportedContentHash,
                ToStatus = (byte)status,
                ResultCode = resultCode,
                OccurredAtUtc = occurredAtUtc.UtcDateTime,
                ReceivedAtUtc = receivedAtUtc.UtcDateTime
            }, cancellationToken);
        return new DefenderReceiptWork(
            row.Succeeded,
            row.Code,
            row.ReceiptPublicId,
            row.SourceDocumentPublicId,
            row.ScanProvider.HasValue
                ? (SourceDocumentScanProvider)row.ScanProvider.Value
                : null,
            Location(row.QuarantineBlobContainer, row.QuarantineBlobObjectName),
            row.QuarantineBlobETag,
            row.ContentHash,
            row.ContentLength,
            row.MimeType,
            row.WasReplay);
    }

    public async Task FinalizeAsync(
        Guid receiptId,
        byte[] payloadHash,
        bool applied,
        string outcomeCode,
        DateTimeOffset finalizedAtUtc,
        CancellationToken cancellationToken)
    {
        var row = await QueryAsync<MutationRow>(
            "dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize",
            "finalize Defender receipt",
            new
            {
                ReceiptPublicId = receiptId,
                PayloadHash = payloadHash,
                Applied = applied,
                OutcomeCode = outcomeCode,
                FinalizedAtUtc = finalizedAtUtc.UtcDateTime
            }, cancellationToken);
        if (!row.Succeeded)
            throw new SourceDocumentDataException("finalize Defender receipt", -1);
    }

    private async Task<T> QueryAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(operation, exception.Number);
        }
    }

    private static ProtectedBlobLocation? Location(string? container, string? objectName) =>
        string.IsNullOrWhiteSpace(container) || string.IsNullOrWhiteSpace(objectName)
            ? null
            : new ProtectedBlobLocation(container, objectName);

    private class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
    }

    private sealed class RecordRow : MutationRow
    {
        public Guid? ReceiptPublicId { get; init; }
        public Guid? SourceDocumentPublicId { get; init; }
        public byte? ScanProvider { get; init; }
        public string? QuarantineBlobContainer { get; init; }
        public string? QuarantineBlobObjectName { get; init; }
        public string? QuarantineBlobETag { get; init; }
        public byte[]? ContentHash { get; init; }
        public long? ContentLength { get; init; }
        public string? MimeType { get; init; }
        public bool WasReplay { get; init; }
    }
}
