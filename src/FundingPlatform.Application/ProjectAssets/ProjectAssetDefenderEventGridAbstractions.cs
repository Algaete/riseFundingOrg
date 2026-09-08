using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Application.ProjectAssets;

public sealed record ProjectAssetDefenderEventGridPolicy(
    string ExpectedTopicResourceId,
    string ExpectedSubscriptionName,
    string StorageAccountResourceId,
    Uri BlobServiceUri,
    string QuarantineContainer,
    string TrustedContainer,
    long MaxImageBytes,
    long MaxDocumentBytes,
    TimeSpan MaximumFutureClockSkew);

public sealed record ProjectAssetDefenderReceiptWork(
    bool Succeeded,
    string Code,
    Guid? ReceiptId,
    Guid? ProjectAssetId,
    ProjectAssetKind? Kind,
    ProjectAssetScanProvider? ScanProvider,
    ProtectedProjectAssetBlobLocation? QuarantineLocation,
    string? QuarantineETag,
    byte[]? ContentHash,
    long? ContentLength,
    string? MimeType,
    bool WasReplay);

public interface IProjectAssetDefenderScanReceiptRepository
{
    Task<ProjectAssetDefenderReceiptWork> RecordAsync(
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
        CancellationToken cancellationToken);

    Task FinalizeAsync(
        Guid receiptId,
        byte[] payloadHash,
        bool applied,
        string outcomeCode,
        DateTimeOffset finalizedAtUtc,
        CancellationToken cancellationToken);
}

public sealed record ProjectAssetDefenderScanWatchdogMutation(
    Guid ProjectAssetId,
    ProjectAssetStorageStatus StorageStatus,
    ProjectAssetScanStatus ScanStatus,
    ProjectAssetScanProvider ScanProvider,
    byte[] AssetRowVersion,
    byte[] ProjectRowVersion);

public interface IProjectAssetDefenderScanWatchdogRepository
{
    Task<IReadOnlyList<ProjectAssetDefenderScanWatchdogMutation>> TimeoutPendingAsync(
        int batchSize,
        int timeoutSeconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed class ProjectAssetDefenderScanWatchdogService(
    IProjectAssetDefenderScanWatchdogRepository repository,
    TimeProvider timeProvider)
{
    public Task<IReadOnlyList<ProjectAssetDefenderScanWatchdogMutation>> RunAsync(
        int batchSize,
        int timeoutMinutes,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        if (timeoutMinutes is < 180 or > 1_440)
            throw new ArgumentOutOfRangeException(nameof(timeoutMinutes));
        return repository.TimeoutPendingAsync(
            batchSize,
            checked(timeoutMinutes * 60),
            timeProvider.GetUtcNow(),
            cancellationToken);
    }
}

public sealed record ProjectAssetTrustedContentPromotion(
    bool Succeeded,
    string Code,
    ProjectAssetBlobReceipt? Receipt = null);

public interface IProjectAssetTrustedContentPromoter
{
    Task<ProjectAssetTrustedContentPromotion> PromoteAsync(
        ProjectAssetKind kind,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        string quarantineETag,
        ProtectedProjectAssetBlobLocation trustedLocation,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken);
}

public enum ProjectAssetDefenderEventGridOutcome
{
    Applied,
    ValidationHandshake,
    Rejected,
    Retry
}

public sealed record ProjectAssetDefenderEventGridResult(
    ProjectAssetDefenderEventGridOutcome Outcome,
    string Code,
    string? ValidationCode = null,
    Guid? ProjectAssetId = null);
