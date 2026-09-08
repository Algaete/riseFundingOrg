using System.Data;
using Dapper;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.ProjectAssets;

public sealed class SqlProjectAssetRepository(
    ISqlConnectionFactory connectionFactory) : IProjectAssetRepository
{
    public Task<ProjectAssetMutation> CreateUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        ProjectAssetKind kind,
        string originalFileName,
        string declaredMimeType,
        long expectedContentLength,
        long maxContentLength,
        ProtectedProjectAssetBlobLocation incomingLocation,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        ProtectedProjectAssetBlobLocation trustedLocation,
        byte[] completionTokenHash,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create",
        "create project asset upload intent",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            ExpectedProjectRowVersion = expectedProjectRowVersion,
            Kind = (byte)kind,
            OriginalFileName = originalFileName,
            DeclaredMimeType = declaredMimeType,
            ExpectedContentLength = expectedContentLength,
            MaxContentLength = maxContentLength,
            IncomingBlobContainer = incomingLocation.Container,
            IncomingBlobObjectName = incomingLocation.ObjectName,
            QuarantineBlobContainer = quarantineLocation.Container,
            QuarantineBlobObjectName = quarantineLocation.ObjectName,
            TrustedBlobContainer = trustedLocation.Container,
            TrustedBlobObjectName = trustedLocation.ObjectName,
            CompletionTokenHash = completionTokenHash,
            ExpiresAtUtc = expiresAtUtc.UtcDateTime
        },
        cancellationToken);

    public async Task<ProjectAssetFinalizeWork> AcquireFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        byte[] completionTokenHash,
        Guid leaseId,
        DateTimeOffset leaseUntilUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<FinalizeRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize",
                new
                {
                    OrganizationPublicId = organizationPublicId,
                    ProjectPublicId = projectPublicId,
                    UserPublicId = userPublicId,
                    IntentPublicId = intentPublicId,
                    CompletionTokenHash = completionTokenHash,
                    LeaseId = leaseId,
                    LeaseUntilUtc = leaseUntilUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new ProjectAssetFinalizeWork
            {
                Succeeded = row.Succeeded,
                Code = row.Code,
                IntentPublicId = row.IntentPublicId ?? intentPublicId,
                IntentStatus = row.Status.HasValue
                    ? (ProjectAssetUploadIntentStatus)row.Status.Value
                    : ProjectAssetUploadIntentStatus.Pending,
                AssetPublicId = row.AssetPublicId,
                Kind = row.Kind.HasValue ? (ProjectAssetKind)row.Kind.Value : ProjectAssetKind.Image,
                OriginalFileName = row.OriginalFileName ?? string.Empty,
                DeclaredMimeType = row.DeclaredMimeType ?? string.Empty,
                ExpectedContentLength = row.ExpectedContentLength,
                MaxContentLength = row.MaxContentLength,
                IncomingLocation = Location(row.IncomingBlobContainer, row.IncomingBlobObjectName),
                QuarantineLocation = Location(
                    row.QuarantineBlobContainer, row.QuarantineBlobObjectName),
                TrustedLocation = Location(row.TrustedBlobContainer, row.TrustedBlobObjectName),
                FinalizeLeaseId = row.FinalizeLeaseId,
                FinalizeLeaseUntilUtc = ToUtc(row.FinalizeLeaseUntilUtc),
                ActualContentLength = row.ActualContentLength,
                ContentHash = row.ContentHash,
                VerifiedMimeType = row.VerifiedMimeType,
                QuarantineBlobETag = row.QuarantineBlobETag,
                QuarantineBlobVersionId = row.QuarantineBlobVersionId,
                StorageStatus = row.StorageStatus.HasValue
                    ? (ProjectAssetStorageStatus)row.StorageStatus.Value : null,
                ScanStatus = row.ScanStatus.HasValue
                    ? (ProjectAssetScanStatus)row.ScanStatus.Value : null,
                ScanProvider = row.ScanProvider.HasValue
                    ? (ProjectAssetScanProvider)row.ScanProvider.Value : null,
                AssetRowVersion = row.AssetRowVersion,
                IntentRowVersion = row.RowVersion,
                ProjectRowVersion = row.ProjectRowVersion,
                WasReplay = row.WasReplay
            };
        }
        catch (SqlException exception)
        {
            throw Wrap("acquire project asset finalize", exception);
        }
    }

    public Task<ProjectAssetMutation> ReleaseFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_ReleaseFinalize",
        "release project asset finalize",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            IntentPublicId = intentPublicId,
            LeaseId = leaseId,
            ErrorCode = errorCode
        },
        cancellationToken);

    public Task<ProjectAssetMutation> RejectFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_RejectFinalize",
        "reject project asset finalize",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            IntentPublicId = intentPublicId,
            LeaseId = leaseId,
            ErrorCode = errorCode
        },
        cancellationToken);

    public Task<ProjectAssetMutation> CompleteUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        byte[] expectedProjectRowVersion,
        string verifiedMimeType,
        long actualContentLength,
        byte[] contentHash,
        int? pixelWidth,
        int? pixelHeight,
        ProjectAssetScanProvider scanProvider,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete",
        "complete project asset upload intent",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            IntentPublicId = intentPublicId,
            LeaseId = leaseId,
            ExpectedProjectRowVersion = expectedProjectRowVersion,
            VerifiedMimeType = verifiedMimeType,
            ActualContentLength = actualContentLength,
            ContentHash = contentHash,
            ScanProvider = (byte)scanProvider,
            PixelWidth = pixelWidth,
            PixelHeight = pixelHeight
        },
        cancellationToken);

    public Task<ProjectAssetMutation> MarkQuarantinedAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        ProjectAssetBlobReceipt receipt,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAsset_MarkQuarantined",
        "mark project asset quarantined",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            AssetPublicId = assetPublicId,
            ExpectedAssetRowVersion = expectedAssetRowVersion,
            QuarantineBlobETag = receipt.ETag,
            QuarantineBlobVersionId = receipt.VersionId
        },
        cancellationToken);

    public Task<ProjectAssetMutation> ApplyScanResultAsync(
        Guid assetPublicId,
        ProjectAssetScanProvider scanProvider,
        string providerEventId,
        byte[] payloadHash,
        string quarantineETag,
        byte[]? reportedContentHash,
        ProjectAssetScanStatus status,
        string resultCode,
        ProjectAssetTrustedBlob? trustedContent,
        DateTimeOffset occurredAtUtc,
        CancellationToken cancellationToken,
        ProjectAssetScanStatus? providerObservedStatus = null,
        string? providerResultCode = null) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult",
        "apply project asset scan result",
        new
        {
            AssetPublicId = assetPublicId,
            ScanProvider = (byte)scanProvider,
            ProviderEventId = providerEventId,
            PayloadHash = payloadHash,
            QuarantineBlobETag = quarantineETag,
            ReportedContentHash = reportedContentHash,
            ToStatus = (byte)status,
            ResultCode = resultCode,
            ProviderObservedStatus = (byte)(providerObservedStatus ?? status),
            ProviderResultCode = providerResultCode ?? resultCode,
            OccurredAtUtc = occurredAtUtc.UtcDateTime,
            TrustedBlobContainer = trustedContent?.Location.Container,
            TrustedBlobObjectName = trustedContent?.Location.ObjectName,
            TrustedBlobETag = trustedContent?.Receipt.ETag,
            TrustedBlobVersionId = trustedContent?.Receipt.VersionId,
            TrustedMimeType = trustedContent?.Manifest.MimeType,
            TrustedContentLength = trustedContent?.Manifest.ContentLength,
            TrustedContentHash = trustedContent?.Manifest.ContentHash,
            TrustedPixelWidth = trustedContent?.Manifest.PixelWidth,
            TrustedPixelHeight = trustedContent?.Manifest.PixelHeight,
            TrustedProcessingVersion = trustedContent?.Manifest.ProcessingVersion
        },
        cancellationToken);

    public async Task<ProjectAssetCollection> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAsset_List",
                new
                {
                    OrganizationPublicId = organizationPublicId,
                    ProjectPublicId = projectPublicId,
                    UserPublicId = userPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var envelope = await reader.ReadSingleAsync<CollectionRow>();
            var assets = (await reader.ReadAsync<AssetRow>()).Select(MapAsset).ToArray();
            return new ProjectAssetCollection(
                envelope.ProjectPublicId,
                envelope.PublicationStatus,
                envelope.ProjectRowVersion,
                assets);
        }
        catch (SqlException exception)
        {
            throw Wrap("list project assets", exception);
        }
    }

    public async Task<ProjectAssetUploadIntent?> GetUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<IntentRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Get",
                new
                {
                    OrganizationPublicId = organizationPublicId,
                    ProjectPublicId = projectPublicId,
                    UserPublicId = userPublicId,
                    IntentPublicId = intentPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return row is null ? null : new ProjectAssetUploadIntent(
                row.IntentPublicId,
                row.ProjectPublicId,
                (ProjectAssetKind)row.Kind,
                row.OriginalFileName,
                row.DeclaredMimeType,
                row.ExpectedContentLength,
                row.MaxContentLength,
                (ProjectAssetUploadIntentStatus)row.Status,
                ToUtc(row.ExpiresAtUtc),
                row.AssetPublicId,
                row.StorageStatus.HasValue
                    ? (ProjectAssetStorageStatus)row.StorageStatus.Value : null,
                row.ScanStatus.HasValue ? (ProjectAssetScanStatus)row.ScanStatus.Value : null,
                row.ScanProvider.HasValue
                    ? (ProjectAssetScanProvider)row.ScanProvider.Value : null,
                ToUtc(row.CreatedAtUtc),
                ToUtc(row.UpdatedAtUtc),
                row.RowVersion);
        }
        catch (SqlException exception)
        {
            throw Wrap("read project asset upload intent", exception);
        }
    }

    public async Task<ProjectAssetTrustedContent?> GetTrustedContentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<TrustedContentRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent",
                new
                {
                    OrganizationPublicId = organizationPublicId,
                    ProjectPublicId = projectPublicId,
                    UserPublicId = userPublicId,
                    AssetPublicId = assetPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            if (!row.Succeeded || string.IsNullOrWhiteSpace(row.TrustedBlobContainer) ||
                string.IsNullOrWhiteSpace(row.TrustedBlobObjectName) ||
                string.IsNullOrWhiteSpace(row.TrustedBlobETag) ||
                row.TrustedContentHash is not { Length: 32 } ||
                string.IsNullOrWhiteSpace(row.TrustedMimeType) ||
                string.IsNullOrWhiteSpace(row.TrustedProcessingVersion) ||
                string.IsNullOrWhiteSpace(row.OriginalFileName) ||
                row.TrustedContentLength is null || row.TrustedCreatedAtUtc is null)
                return null;
            return new ProjectAssetTrustedContent(
                row.AssetPublicId,
                (ProjectAssetKind)(row.Kind ?? 0),
                row.OriginalFileName,
                row.TrustedMimeType,
                row.TrustedContentLength.Value,
                row.TrustedContentHash,
                row.TrustedPixelWidth,
                row.TrustedPixelHeight,
                row.TrustedProcessingVersion,
                ToUtc(row.TrustedCreatedAtUtc.Value),
                new ProtectedProjectAssetBlobLocation(
                    row.TrustedBlobContainer, row.TrustedBlobObjectName),
                row.TrustedBlobETag,
                row.TrustedBlobVersionId);
        }
        catch (SqlException exception)
        {
            throw Wrap("read trusted project asset content", exception);
        }
    }

    public Task<ProjectAssetMutation> UpdateMetadataAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        ProjectAssetMetadata metadata,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata",
        "update project asset metadata",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            AssetPublicId = assetPublicId,
            ExpectedAssetRowVersion = expectedAssetRowVersion,
            ExpectedProjectRowVersion = expectedProjectRowVersion,
            metadata.DisplayName,
            metadata.AltText,
            metadata.Caption,
            metadata.IsCover
        },
        cancellationToken);

    public async Task<ProjectAssetMutation> ReorderAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        IReadOnlyList<ProjectAssetOrderItem> items,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("OrganizationPublicId", organizationPublicId);
        parameters.Add("ProjectPublicId", projectPublicId);
        parameters.Add("UserPublicId", userPublicId);
        parameters.Add("ExpectedProjectRowVersion", expectedProjectRowVersion);
        parameters.Add("Items", ToOrderTable(items).AsTableValuedParameter(
            "dbo.FundingPlatform_ProjectAssetOrderList"));
        return await ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_ProjectAsset_Reorder",
            "reorder project assets",
            parameters,
            cancellationToken);
    }

    public Task<ProjectAssetMutation> DeleteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
        "dbo.FundingPlatform_usp_ProjectAsset_Delete",
        "delete project asset",
        new
        {
            OrganizationPublicId = organizationPublicId,
            ProjectPublicId = projectPublicId,
            UserPublicId = userPublicId,
            AssetPublicId = assetPublicId,
            ExpectedAssetRowVersion = expectedAssetRowVersion,
            ExpectedProjectRowVersion = expectedProjectRowVersion
        },
        cancellationToken);

    private async Task<ProjectAssetMutation> ExecuteMutationAsync(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new ProjectAssetMutation(
                Succeeded: row.Succeeded,
                Code: row.Code,
                IntentPublicId: row.IntentPublicId,
                IntentStatus: row.Status.HasValue
                    ? (ProjectAssetUploadIntentStatus)row.Status.Value : null,
                AssetPublicId: row.AssetPublicId,
                StorageStatus: row.StorageStatus.HasValue
                    ? (ProjectAssetStorageStatus)row.StorageStatus.Value : null,
                ScanStatus: row.ScanStatus.HasValue
                    ? (ProjectAssetScanStatus)row.ScanStatus.Value : null,
                ScanProvider: row.ScanProvider.HasValue
                    ? (ProjectAssetScanProvider)row.ScanProvider.Value : null,
                IntentRowVersion: row.RowVersion,
                AssetRowVersion: row.AssetRowVersion,
                ProjectRowVersion: row.ProjectRowVersion,
                ExpiresAtUtc: ToUtc(row.ExpiresAtUtc),
                WasReplay: row.WasReplay,
                RevokedTrustedBlobContainer: row.RevokedTrustedBlobContainer,
                RevokedTrustedBlobObjectName: row.RevokedTrustedBlobObjectName,
                RevokedTrustedBlobETag: row.RevokedTrustedBlobETag,
                RevokedTrustedBlobVersionId: row.RevokedTrustedBlobVersionId,
                RevokedTrustedMimeType: row.RevokedTrustedMimeType,
                RevokedTrustedContentLength: row.RevokedTrustedContentLength,
                RevokedTrustedContentHash: row.RevokedTrustedContentHash,
                RevokedTrustedPixelWidth: row.RevokedTrustedPixelWidth,
                RevokedTrustedPixelHeight: row.RevokedTrustedPixelHeight,
                RevokedTrustedProcessingVersion: row.RevokedTrustedProcessingVersion,
                RevokedTrustedCreatedAtUtc: ToUtc(row.RevokedTrustedCreatedAtUtc));
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static ProjectAsset MapAsset(AssetRow row) => new(
        row.AssetPublicId,
        (ProjectAssetKind)row.Kind,
        row.OriginalFileName,
        row.DisplayName ?? row.OriginalFileName,
        row.VerifiedMimeType,
        row.ContentLength,
        row.PixelWidth,
        row.PixelHeight,
        (ProjectAssetStorageStatus)row.StorageStatus,
        (ProjectAssetScanStatus)row.ScanStatus,
        (ProjectAssetScanProvider)row.ScanProvider,
        row.ScanResultCode,
        row.SortOrder,
        row.IsCover,
        row.AltText,
        row.Caption,
        ToUtc(row.CreatedAtUtc),
        ToUtc(row.UpdatedAtUtc),
        row.RowVersion);

    private static ProtectedProjectAssetBlobLocation? Location(
        string? container,
        string? objectName) =>
        string.IsNullOrWhiteSpace(container) || string.IsNullOrWhiteSpace(objectName)
            ? null
            : new ProtectedProjectAssetBlobLocation(container, objectName);

    private static DataTable ToOrderTable(IEnumerable<ProjectAssetOrderItem> items)
    {
        var table = new DataTable();
        table.Columns.Add("AssetPublicId", typeof(Guid));
        table.Columns.Add("ExpectedRowVersion", typeof(byte[]));
        table.Columns.Add("SortOrder", typeof(short));
        foreach (var item in items)
            table.Rows.Add(item.AssetPublicId, item.ExpectedRowVersion, item.SortOrder);
        return table;
    }

    private static DateTimeOffset ToUtc(DateTime value) => new(
        DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static ProjectAssetDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? IntentPublicId { get; init; }
        public byte? Status { get; init; }
        public Guid? AssetPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public byte[]? RowVersion { get; init; }
        public byte[]? AssetRowVersion { get; init; }
        public byte[]? ProjectRowVersion { get; init; }
        public DateTime? ExpiresAtUtc { get; init; }
        public bool WasReplay { get; init; }
        public string? RevokedTrustedBlobContainer { get; init; }
        public string? RevokedTrustedBlobObjectName { get; init; }
        public string? RevokedTrustedBlobETag { get; init; }
        public string? RevokedTrustedBlobVersionId { get; init; }
        public string? RevokedTrustedMimeType { get; init; }
        public long? RevokedTrustedContentLength { get; init; }
        public byte[]? RevokedTrustedContentHash { get; init; }
        public int? RevokedTrustedPixelWidth { get; init; }
        public int? RevokedTrustedPixelHeight { get; init; }
        public string? RevokedTrustedProcessingVersion { get; init; }
        public DateTime? RevokedTrustedCreatedAtUtc { get; init; }
    }

    private sealed class FinalizeRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? IntentPublicId { get; init; }
        public byte? Status { get; init; }
        public byte? Kind { get; init; }
        public string? OriginalFileName { get; init; }
        public string? DeclaredMimeType { get; init; }
        public string? VerifiedMimeType { get; init; }
        public long? ExpectedContentLength { get; init; }
        public long? MaxContentLength { get; init; }
        public long? ActualContentLength { get; init; }
        public byte[]? ContentHash { get; init; }
        public string? IncomingBlobContainer { get; init; }
        public string? IncomingBlobObjectName { get; init; }
        public string? QuarantineBlobContainer { get; init; }
        public string? QuarantineBlobObjectName { get; init; }
        public string? TrustedBlobContainer { get; init; }
        public string? TrustedBlobObjectName { get; init; }
        public string? QuarantineBlobETag { get; init; }
        public string? QuarantineBlobVersionId { get; init; }
        public Guid? AssetPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public Guid? FinalizeLeaseId { get; init; }
        public DateTime? FinalizeLeaseUntilUtc { get; init; }
        public byte[]? RowVersion { get; init; }
        public byte[]? AssetRowVersion { get; init; }
        public byte[]? ProjectRowVersion { get; init; }
        public bool WasReplay { get; init; }
    }

    private sealed class CollectionRow
    {
        public Guid ProjectPublicId { get; init; }
        public byte PublicationStatus { get; init; }
        public byte[] ProjectRowVersion { get; init; } = [];
    }

    private sealed class AssetRow
    {
        public Guid AssetPublicId { get; init; }
        public byte Kind { get; init; }
        public string OriginalFileName { get; init; } = string.Empty;
        public string? DisplayName { get; init; }
        public string VerifiedMimeType { get; init; } = string.Empty;
        public long ContentLength { get; init; }
        public int? PixelWidth { get; init; }
        public int? PixelHeight { get; init; }
        public byte StorageStatus { get; init; }
        public byte ScanStatus { get; init; }
        public byte ScanProvider { get; init; }
        public string? ScanResultCode { get; init; }
        public string? AltText { get; init; }
        public string? Caption { get; init; }
        public short SortOrder { get; init; }
        public bool IsCover { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class IntentRow
    {
        public Guid IntentPublicId { get; init; }
        public Guid ProjectPublicId { get; init; }
        public byte Kind { get; init; }
        public string OriginalFileName { get; init; } = string.Empty;
        public string DeclaredMimeType { get; init; } = string.Empty;
        public long ExpectedContentLength { get; init; }
        public long MaxContentLength { get; init; }
        public byte Status { get; init; }
        public DateTime ExpiresAtUtc { get; init; }
        public Guid? AssetPublicId { get; init; }
        public byte? StorageStatus { get; init; }
        public byte? ScanStatus { get; init; }
        public byte? ScanProvider { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class TrustedContentRow
    {
        public bool Succeeded { get; init; }
        public Guid AssetPublicId { get; init; }
        public byte? Kind { get; init; }
        public string? TrustedBlobContainer { get; init; }
        public string? TrustedBlobObjectName { get; init; }
        public string? TrustedBlobETag { get; init; }
        public string? TrustedBlobVersionId { get; init; }
        public byte[]? TrustedContentHash { get; init; }
        public string? TrustedMimeType { get; init; }
        public long? TrustedContentLength { get; init; }
        public int? TrustedPixelWidth { get; init; }
        public int? TrustedPixelHeight { get; init; }
        public string? TrustedProcessingVersion { get; init; }
        public DateTime? TrustedCreatedAtUtc { get; init; }
        public string? OriginalFileName { get; init; }
    }
}
