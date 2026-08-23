using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed record EventGridCaller(
    Guid TenantId,
    Guid PrincipalId,
    Guid ApplicationId);

public sealed record DefenderEventGridPolicy(
    string ExpectedTopicResourceId,
    string ExpectedSubscriptionName,
    string StorageAccountResourceId,
    Uri BlobServiceUri,
    string QuarantineContainer,
    string TrustedContainer,
    long MaximumBlobBytes,
    TimeSpan MaximumFutureClockSkew);

public sealed record DefenderReceiptWork(
    bool Succeeded,
    string Code,
    Guid? ReceiptId,
    Guid? SourceDocumentId,
    SourceDocumentScanProvider? ScanProvider,
    ProtectedBlobLocation? QuarantineLocation,
    string? QuarantineETag,
    byte[]? ContentHash,
    long? ContentLength,
    string? MimeType,
    bool WasReplay);

public interface IEventGridBearerTokenValidator
{
    Task<EventGridTokenValidation> ValidateAsync(
        string? authorizationHeader,
        CancellationToken cancellationToken);
}

public enum EventGridTokenValidationOutcome
{
    Valid,
    Invalid,
    Unavailable
}

public sealed record EventGridTokenValidation(
    EventGridTokenValidationOutcome Outcome,
    EventGridCaller? Caller = null);

public interface IDefenderScanReceiptRepository
{
    Task<DefenderReceiptWork> RecordAsync(
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
        CancellationToken cancellationToken);

    Task FinalizeAsync(
        Guid receiptId,
        byte[] payloadHash,
        bool applied,
        string outcomeCode,
        DateTimeOffset finalizedAtUtc,
        CancellationToken cancellationToken);
}

public sealed record DefenderScanWatchdogMutation(
    Guid SourceDocumentId,
    SourceDocumentStorageStatus StorageStatus,
    SourceDocumentScanStatus ScanStatus,
    SourceDocumentScanProvider ScanProvider,
    short ScanAttemptCount,
    byte[] RowVersion);

public interface IDefenderScanWatchdogRepository
{
    Task<IReadOnlyList<DefenderScanWatchdogMutation>> TimeoutPendingAsync(
        int batchSize,
        int timeoutSeconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed class DefenderScanWatchdogService(
    IDefenderScanWatchdogRepository repository,
    TimeProvider timeProvider)
{
    public Task<IReadOnlyList<DefenderScanWatchdogMutation>> RunAsync(
        int batchSize,
        int timeoutMinutes,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(batchSize));
        if (timeoutMinutes is < 180 or > 1_440)
            throw new ArgumentOutOfRangeException(nameof(timeoutMinutes));
        return repository.TimeoutPendingAsync(
            batchSize,
            checked(timeoutMinutes * 60),
            timeProvider.GetUtcNow(),
            cancellationToken);
    }
}

public enum DefenderEventGridOutcome
{
    Applied,
    ValidationHandshake,
    Rejected,
    Retry
}

public sealed record DefenderEventGridResult(
    DefenderEventGridOutcome Outcome,
    string Code,
    string? ValidationCode = null,
    Guid? SourceDocumentId = null);
