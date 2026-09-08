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
    int MaxImagePixels,
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

public enum ProjectAssetTrustedPromotionOutcome
{
    Promoted,
    Rejected,
    Retry
}

public sealed record ProjectAssetTrustedContentManifest(
    string MimeType,
    long ContentLength,
    byte[] ContentHash,
    int? PixelWidth,
    int? PixelHeight,
    string ProcessingVersion);

public sealed record ProjectAssetTrustedContentRequest(
    ProjectAssetKind Kind,
    ProtectedProjectAssetBlobLocation QuarantineLocation,
    string QuarantineETag,
    ProtectedProjectAssetBlobLocation TrustedLocation,
    string SourceMimeType,
    long SourceContentLength,
    byte[] SourceContentHash,
    long MaximumOutputLength,
    int MaximumImagePixels);

public sealed record ProjectAssetTrustedBlob(
    ProtectedProjectAssetBlobLocation Location,
    ProjectAssetBlobReceipt Receipt,
    ProjectAssetTrustedContentManifest Manifest);

public sealed record ProjectAssetTrustedContentPromotion(
    ProjectAssetTrustedPromotionOutcome Outcome,
    string Code,
    ProjectAssetTrustedBlob? Content = null)
{
    public bool Succeeded => Outcome == ProjectAssetTrustedPromotionOutcome.Promoted;
    public bool IsRetryable => Outcome == ProjectAssetTrustedPromotionOutcome.Retry;
}

public interface IProjectAssetTrustedContentPromoter
{
    Task<ProjectAssetTrustedContentPromotion> PromoteAsync(
        ProjectAssetTrustedContentRequest request,
        CancellationToken cancellationToken);
}

public interface IProjectAssetImageSanitizationProbe
{
    bool IsAvailable();
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
