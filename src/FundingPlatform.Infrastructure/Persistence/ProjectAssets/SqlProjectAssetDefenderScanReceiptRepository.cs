using System.Data;
using Dapper;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.ProjectAssets;

public sealed class SqlProjectAssetDefenderScanReceiptRepository(
    ISqlConnectionFactory connectionFactory) : IProjectAssetDefenderScanReceiptRepository
{
    public async Task<ProjectAssetDefenderReceiptWork> RecordAsync(
        string eventGridEventId,
        byte[] payloadHash,
        EventGridCaller caller,
        string eventSubscriptionName,
        string topicResourceId,
        string storageAccountResourceId,
        string blobHost,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        string blobETag,
        byte[]? reportedContentHash,
        ProjectAssetScanStatus status,
        string resultCode,
        DateTimeOffset occurredAtUtc,
        DateTimeOffset receivedAtUtc,
        CancellationToken cancellationToken)
    {
        var row = await QueryAsync<RecordRow>(
            "dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record",
            "record project asset Defender receipt",
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
            },
            cancellationToken);
        return new ProjectAssetDefenderReceiptWork(
            row.Succeeded,
            row.Code,
            row.ReceiptPublicId,
            row.ProjectAssetPublicId,
            row.Kind.HasValue ? (ProjectAssetKind)row.Kind.Value : null,
            row.ScanProvider.HasValue
                ? (ProjectAssetScanProvider)row.ScanProvider.Value : null,
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
            "dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize",
            "finalize project asset Defender receipt",
            new
            {
                ReceiptPublicId = receiptId,
                PayloadHash = payloadHash,
                Applied = applied,
                OutcomeCode = outcomeCode,
                FinalizedAtUtc = finalizedAtUtc.UtcDateTime
            },
            cancellationToken);
        if (!row.Succeeded)
        {
            throw new ProjectAssetDataException(
                "finalize project asset Defender receipt", -1,
                new InvalidOperationException("Receipt finalization was rejected."));
        }
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
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new ProjectAssetDataException(operation, exception.Number, exception);
        }
    }

    private static ProtectedProjectAssetBlobLocation? Location(
        string? container,
        string? objectName) =>
        string.IsNullOrWhiteSpace(container) || string.IsNullOrWhiteSpace(objectName)
            ? null
            : new ProtectedProjectAssetBlobLocation(container, objectName);

    private class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
    }

    private sealed class RecordRow : MutationRow
    {
        public Guid? ReceiptPublicId { get; init; }
        public Guid? ProjectAssetPublicId { get; init; }
        public byte? Kind { get; init; }
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
