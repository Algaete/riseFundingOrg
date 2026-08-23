using System.Data;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlSourceDocumentRepository(
    ISqlConnectionFactory connectionFactory) : ISourceDocumentRepository
{
    public Task<SourceDocumentMutation> CreateUploadIntentAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string originalFileName,
        string declaredMimeType,
        long expectedContentLength,
        long maxContentLength,
        ProtectedBlobLocation incomingLocation,
        ProtectedBlobLocation quarantineLocation,
        byte[] completionTokenHash,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Create",
            "create upload intent",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                FundingSourceId = fundingSourceId,
                OriginalFileName = originalFileName,
                DeclaredMimeType = declaredMimeType,
                ExpectedContentLength = expectedContentLength,
                MaxContentLength = maxContentLength,
                BlobContainer = incomingLocation.Container,
                BlobObjectName = incomingLocation.ObjectName,
                QuarantineBlobContainer = quarantineLocation.Container,
                QuarantineBlobObjectName = quarantineLocation.ObjectName,
                CompletionTokenHash = completionTokenHash,
                ExpiresAtUtc = expiresAtUtc.UtcDateTime
            },
            cancellationToken);

    public async Task<SourceDocumentFinalizeWork> AcquireFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        byte[] completionTokenHash,
        Guid leaseId,
        DateTimeOffset leaseUntilUtc,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<FinalizeWorkRow>(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize",
            "acquire upload finalization",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                IntentPublicId = intentPublicId,
                CompletionTokenHash = completionTokenHash,
                LeaseId = leaseId,
                LeaseUntilUtc = leaseUntilUtc.UtcDateTime
            },
            cancellationToken);
        return new SourceDocumentFinalizeWork
        {
            Succeeded = row.Succeeded,
            Code = row.Code,
            IntentPublicId = row.IntentPublicId,
            FundingSourceId = row.FundingSourceId,
            OriginalFileName = row.OriginalFileName,
            IncomingLocation = Location(row.IncomingBlobContainer, row.IncomingBlobObjectName),
            QuarantineLocation = Location(
                row.QuarantineBlobContainer, row.QuarantineBlobObjectName),
            DeclaredMimeType = row.DeclaredMimeType,
            VerifiedMimeType = row.VerifiedMimeType,
            ExpectedContentLength = row.ExpectedContentLength,
            MaxContentLength = row.MaxContentLength,
            ActualContentLength = row.ActualContentLength,
            ContentHash = row.ContentHash,
            BlobETag = row.BlobETag,
            BlobVersionId = row.BlobVersionId,
            IntentStatus = EnumValue<SourceDocumentUploadIntentStatus>(row.Status),
            ExpiresAtUtc = ToUtc(row.ExpiresAtUtc),
            SourceDocumentPublicId = row.SourceDocumentPublicId,
            StorageStatus = EnumValue<SourceDocumentStorageStatus>(row.StorageStatus),
            ScanStatus = EnumValue<SourceDocumentScanStatus>(row.ScanStatus),
            ScanProvider = EnumValue<SourceDocumentScanProvider>(row.ScanProvider),
            FinalizeLeaseId = row.FinalizeLeaseId,
            RowVersion = row.RowVersion,
            WasReplay = row.WasReplay
        };
    }

    public Task<SourceDocumentMutation> ReleaseFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize",
            "release upload finalization",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                IntentPublicId = intentPublicId,
                LeaseId = leaseId,
                ErrorCode = errorCode
            },
            cancellationToken);

    public Task<SourceDocumentMutation> RejectFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize",
            "reject upload finalization",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                IntentPublicId = intentPublicId,
                LeaseId = leaseId,
                ErrorCode = errorCode
            },
            cancellationToken);

    public Task<SourceDocumentMutation> CompleteUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        long actualContentLength,
        byte[] contentHash,
        SourceDocumentScanProvider scanProvider,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Complete",
            "complete upload intent",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                IntentPublicId = intentPublicId,
                LeaseId = leaseId,
                VerifiedMimeType = "application/pdf",
                ActualContentLength = actualContentLength,
                ContentHash = contentHash,
                ScanProvider = (byte)scanProvider
            },
            cancellationToken,
            inferCompletedIntent: true);

    public Task<SourceDocumentMutation> MarkQuarantinedAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        SourceBlobReceipt receipt,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocument_MarkQuarantined",
            "mark source document quarantined",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                SourceDocumentPublicId = sourceDocumentPublicId,
                BlobETag = receipt.ETag,
                BlobVersionId = receipt.VersionId
            },
            cancellationToken);

    public Task<SourceDocumentMutation> ApplyScanResultAsync(
        Guid sourceDocumentPublicId,
        SourceDocumentScanProvider scanProvider,
        string providerEventId,
        byte[] payloadHash,
        string quarantineETag,
        byte[]? reportedContentHash,
        SourceDocumentScanStatus status,
        string resultCode,
        ProtectedBlobLocation? trustedLocation,
        SourceBlobReceipt? trustedReceipt,
        DateTimeOffset occurredAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult",
            "apply source document scan result",
            new
            {
                SourceDocumentPublicId = sourceDocumentPublicId,
                ScanProvider = (byte)scanProvider,
                ProviderEventId = providerEventId,
                PayloadHash = payloadHash,
                BlobETag = quarantineETag,
                ReportedContentHash = reportedContentHash,
                ToStatus = (byte)status,
                ResultCode = resultCode,
                TrustedBlobContainer = trustedLocation?.Container,
                TrustedBlobObjectName = trustedLocation?.ObjectName,
                TrustedBlobETag = trustedReceipt?.ETag,
                OccurredAtUtc = occurredAtUtc.UtcDateTime
            },
            cancellationToken);

    public async Task<SourceDocumentRetryMutation> RetryScanAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<RetryRow>(
            "dbo.FundingPlatform_usp_SourceDocument_RetryScan",
            "retry source document scan",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                SourceDocumentPublicId = sourceDocumentPublicId,
                ExpectedRowVersion = expectedRowVersion,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash
            },
            cancellationToken);
        return new SourceDocumentRetryMutation(
            row.Succeeded,
            row.Code,
            row.SourceDocumentPublicId ?? sourceDocumentPublicId,
            EnumValue<SourceDocumentStorageStatus>(row.StorageStatus),
            EnumValue<SourceDocumentScanStatus>(row.ScanStatus),
            EnumValue<SourceDocumentScanProvider>(row.ScanProvider),
            row.ScanAttemptCount,
            row.RowVersion,
            row.WasReplay);
    }

    public async Task<SourceDocumentScanWork> AcquireScanWorkAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        byte[] expectedRowVersion,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<ScanWorkRow>(
            "dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork",
            "acquire source document scan work",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                SourceDocumentPublicId = sourceDocumentPublicId,
                ExpectedRowVersion = expectedRowVersion
            },
            cancellationToken);
        return new SourceDocumentScanWork
        {
            Succeeded = row.Succeeded,
            Code = row.Code,
            SourceDocumentPublicId = row.SourceDocumentPublicId ?? sourceDocumentPublicId,
            QuarantineLocation = Location(
                row.QuarantineBlobContainer, row.QuarantineBlobObjectName),
            ContentLength = row.ContentLength,
            ContentHash = row.ContentHash,
            BlobETag = row.BlobETag,
            BlobVersionId = row.BlobVersionId,
            ScanProvider = EnumValue<SourceDocumentScanProvider>(row.ScanProvider),
            ScanAttemptCount = row.ScanAttemptCount,
            ScanStartedAtUtc = ToUtc(row.ScanStartedAtUtc),
            CreatedAtUtc = ToUtc(row.CreatedAtUtc),
            RowVersion = row.RowVersion
        };
    }

    public async Task<SourceDocumentUploadIntent?> GetUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleOrDefaultAsync<IntentRow>(
            "dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Get",
            "get upload intent",
            new { AdminUserPublicId = adminUserPublicId, IntentPublicId = intentPublicId },
            cancellationToken);
        if (row is null) return null;
        return new SourceDocumentUploadIntent(
            row.IntentPublicId,
            row.FundingSourceId,
            row.FundingSourceName,
            row.OriginalFileName,
            row.DeclaredMimeType,
            row.ExpectedContentLength,
            row.MaxContentLength,
            (SourceDocumentUploadIntentStatus)row.Status,
            Utc(row.ExpiresAtUtc),
            row.SourceDocumentPublicId,
            EnumValue<SourceDocumentStorageStatus>(row.StorageStatus),
            EnumValue<SourceDocumentScanStatus>(row.ScanStatus),
            EnumValue<SourceDocumentScanProvider>(row.ScanProvider),
            row.ScanResultCode,
            Utc(row.CreatedAtUtc),
            ToUtc(row.CompletedAtUtc),
            Utc(row.UpdatedAtUtc),
            row.RowVersion);
    }

    public async Task<SourceDocument?> GetSourceDocumentAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleOrDefaultAsync<DocumentRow>(
            "dbo.FundingPlatform_usp_SourceDocument_Get",
            "get source document",
            new
            {
                AdminUserPublicId = adminUserPublicId,
                SourceDocumentPublicId = sourceDocumentPublicId
            },
            cancellationToken);
        if (row is null) return null;
        return new SourceDocument(
            row.SourceDocumentPublicId,
            row.FundingSourceId,
            row.FundingSourceName,
            row.OriginalFileName,
            row.MimeType,
            row.ContentLength,
            (SourceDocumentStorageStatus)row.StorageStatus,
            (SourceDocumentScanStatus)row.ScanStatus,
            (SourceDocumentScanProvider)row.ScanProvider,
            row.IsProductionScan,
            row.ScanAttemptCount,
            row.ScanResultCode,
            ToUtc(row.ScanStartedAtUtc),
            ToUtc(row.ScanCompletedAtUtc),
            row.ExtractionStatus,
            row.UploadedByUserPublicId,
            Utc(row.CreatedAtUtc),
            Utc(row.UpdatedAtUtc),
            row.RowVersion,
            ContentRetentionStatus:
                (SourceDocumentContentRetentionStatus)
                    row.ContentRetentionStatus,
            RetentionUntilUtc: ToUtc(row.RetentionUntilUtc),
            ContentDeletionRequestedAtUtc:
                ToUtc(row.ContentDeletionRequestedAtUtc),
            ContentRetentionLastErrorCode:
                row.ContentRetentionLastErrorCode);
    }

    private async Task<SourceDocumentMutation> ExecuteMutationAsync(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken,
        bool inferCompletedIntent = false)
    {
        var row = await QuerySingleAsync<MutationRow>(
            procedure, operation, parameters, cancellationToken);
        return new SourceDocumentMutation(
            row.Succeeded,
            row.Code,
            row.IntentPublicId,
            row.Status.HasValue
                ? (SourceDocumentUploadIntentStatus)row.Status.Value
                : inferCompletedIntent && row.Succeeded
                    ? SourceDocumentUploadIntentStatus.Completed
                    : null,
            row.SourceDocumentPublicId,
            EnumValue<SourceDocumentStorageStatus>(row.StorageStatus),
            EnumValue<SourceDocumentScanStatus>(row.ScanStatus),
            EnumValue<SourceDocumentScanProvider>(row.ScanProvider),
            row.RowVersion,
            row.WasReplay,
            ToUtc(row.ExpiresAtUtc),
            Location(
                row.RevokedTrustedBlobContainer,
                row.RevokedTrustedBlobObjectName),
            row.RevokedTrustedBlobETag);
    }

    private async Task<T> QuerySingleAsync<T>(
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
                commandTimeout: 15,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(operation, exception.Number);
        }
    }

    private async Task<T?> QuerySingleOrDefaultAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken) where T : class
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleOrDefaultAsync<T>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
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

    private static TEnum? EnumValue<TEnum>(byte? value) where TEnum : struct, Enum =>
        value.HasValue ? (TEnum)Enum.ToObject(typeof(TEnum), value.Value) : null;

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) => value.HasValue ? Utc(value.Value) : null;

    private class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? IntentPublicId { get; init; }
        public byte? Status { get; init; }
        public Guid? SourceDocumentPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
        public string? RevokedTrustedBlobContainer { get; init; }
        public string? RevokedTrustedBlobObjectName { get; init; }
        public string? RevokedTrustedBlobETag { get; init; }
        public DateTime? ExpiresAtUtc { get; init; }
    }

    private sealed class FinalizeWorkRow : MutationRow
    {
        public int? FundingSourceId { get; init; }
        public string? OriginalFileName { get; init; }
        public string? IncomingBlobContainer { get; init; }
        public string? IncomingBlobObjectName { get; init; }
        public string? QuarantineBlobContainer { get; init; }
        public string? QuarantineBlobObjectName { get; init; }
        public string? DeclaredMimeType { get; init; }
        public string? VerifiedMimeType { get; init; }
        public long? ExpectedContentLength { get; init; }
        public long? MaxContentLength { get; init; }
        public long? ActualContentLength { get; init; }
        public byte[]? ContentHash { get; init; }
        public string? BlobETag { get; init; }
        public string? BlobVersionId { get; init; }
        public Guid? FinalizeLeaseId { get; init; }
    }

    private sealed class RetryRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? SourceDocumentPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public short? ScanAttemptCount { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
    }

    private sealed class ScanWorkRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? SourceDocumentPublicId { get; init; }
        public string? QuarantineBlobContainer { get; init; }
        public string? QuarantineBlobObjectName { get; init; }
        public long? ContentLength { get; init; }
        public byte[]? ContentHash { get; init; }
        public string? BlobETag { get; init; }
        public string? BlobVersionId { get; init; }
        public byte? ScanProvider { get; init; }
        public short? ScanAttemptCount { get; init; }
        public DateTime? ScanStartedAtUtc { get; init; }
        public DateTime? CreatedAtUtc { get; init; }
        public byte[]? RowVersion { get; init; }
    }

    private sealed class IntentRow
    {
        public Guid IntentPublicId { get; init; }
        public int FundingSourceId { get; init; }
        public string FundingSourceName { get; init; } = string.Empty;
        public string OriginalFileName { get; init; } = string.Empty;
        public string DeclaredMimeType { get; init; } = string.Empty;
        public long ExpectedContentLength { get; init; }
        public long MaxContentLength { get; init; }
        public byte Status { get; init; }
        public DateTime ExpiresAtUtc { get; init; }
        public Guid? SourceDocumentPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public string? ScanResultCode { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? CompletedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class DocumentRow
    {
        public Guid SourceDocumentPublicId { get; init; }
        public int FundingSourceId { get; init; }
        public string FundingSourceName { get; init; } = string.Empty;
        public string OriginalFileName { get; init; } = string.Empty;
        public string MimeType { get; init; } = string.Empty;
        public long ContentLength { get; init; }
        public byte StorageStatus { get; init; }
        public byte ScanStatus { get; init; }
        public byte ScanProvider { get; init; }
        public bool IsProductionScan { get; init; }
        public short ScanAttemptCount { get; init; }
        public string? ScanResultCode { get; init; }
        public DateTime? ScanStartedAtUtc { get; init; }
        public DateTime? ScanCompletedAtUtc { get; init; }
        public byte ExtractionStatus { get; init; }
        public byte ContentRetentionStatus { get; init; }
        public DateTime? RetentionUntilUtc { get; init; }
        public DateTime? ContentDeletionRequestedAtUtc { get; init; }
        public string? ContentRetentionLastErrorCode { get; init; }
        public Guid UploadedByUserPublicId { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }
}
