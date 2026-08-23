namespace FundingPlatform.Application.SourceDocuments;

public sealed class SourceDocumentContentRetentionClaim
{
    public required Guid SourceDocumentId { get; init; }
    public required int FundingSourceId { get; init; }
    public required byte[] ContentHash { get; init; }
    public required long ContentLength { get; init; }
    public required ProtectedBlobLocation QuarantineLocation { get; init; }
    public required string QuarantineETag { get; init; }
    public ProtectedBlobLocation? TrustedLocation { get; init; }
    public string? TrustedETag { get; init; }
    public required DateTimeOffset RetentionUntilUtc { get; init; }
    public required short AttemptCount { get; init; }
    public required short MaxAttempts { get; init; }
    public required DateTimeOffset LeaseUntilUtc { get; init; }

    public override string ToString() => "[protected source-document retention claim]";
}

public sealed record SourceDocumentContentRetentionMutation(
    bool Succeeded,
    string Code,
    DateTimeOffset? ContentDeletionRequestedAtUtc = null,
    DateTimeOffset? NextAttemptAtUtc = null,
    short? AttemptCount = null,
    short? MaxAttempts = null,
    bool WasReplay = false);

public interface ISourceDocumentContentRetentionRepository
{
    Task<IReadOnlyList<SourceDocumentContentRetentionClaim>> ClaimAsync(
        int batchSize,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentContentRetentionMutation> CompleteAsync(
        Guid sourceDocumentId,
        Guid leaseId,
        bool quarantineDeletionRequested,
        bool trustedDeletionRequested,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentContentRetentionMutation> FailAsync(
        Guid sourceDocumentId,
        Guid leaseId,
        string errorCode,
        bool isRetryable,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed record SourceBlobRetentionDeletion(bool IsLogicallyUnavailable);

public interface ISourceDocumentRetentionBlobStore
{
    Task<SourceBlobRetentionDeletion> RequestDeletionAsync(
        ProtectedBlobLocation location,
        string expectedETag,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken);
}

public sealed record SourceDocumentContentRetentionRunResult(
    int ClaimedCount,
    int CompletedCount,
    int RetryScheduledCount,
    int FailedCount);

public sealed class SourceDocumentContentRetentionService(
    ISourceDocumentContentRetentionRepository repository,
    ISourceDocumentRetentionBlobStore blobStore,
    TimeProvider timeProvider)
{
    public async Task<SourceDocumentContentRetentionRunResult> RunAsync(
        int batchSize,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        if (leaseDuration < TimeSpan.FromSeconds(30) ||
            leaseDuration > TimeSpan.FromHours(1) ||
            leaseDuration.TotalSeconds != Math.Truncate(leaseDuration.TotalSeconds))
            throw new ArgumentOutOfRangeException(nameof(leaseDuration));

        var leaseId = Guid.NewGuid();
        var claims = await repository.ClaimAsync(
            batchSize,
            leaseId,
            leaseDuration,
            timeProvider.GetUtcNow(),
            cancellationToken);
        var completed = 0;
        var retryScheduled = 0;
        var failed = 0;

        foreach (var claim in claims)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var quarantine = await blobStore.RequestDeletionAsync(
                    claim.QuarantineLocation,
                    claim.QuarantineETag,
                    claim.ContentLength,
                    claim.ContentHash,
                    cancellationToken);
                var trusted = claim.TrustedLocation is null
                    ? new SourceBlobRetentionDeletion(true)
                    : await blobStore.RequestDeletionAsync(
                        claim.TrustedLocation,
                        claim.TrustedETag!,
                        claim.ContentLength,
                        claim.ContentHash,
                        cancellationToken);

                if (!quarantine.IsLogicallyUnavailable || !trusted.IsLogicallyUnavailable)
                {
                    var retry = await FailAsync(
                        claim, leaseId, "active-blob-versions-remain", true,
                        CancellationToken.None);
                    if (retry) retryScheduled++; else failed++;
                    continue;
                }

                var completion = await repository.CompleteAsync(
                    claim.SourceDocumentId,
                    leaseId,
                    quarantineDeletionRequested: true,
                    trustedDeletionRequested: trusted.IsLogicallyUnavailable,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                if (completion.Succeeded && completion.Code == "completed")
                    completed++;
                else
                    failed++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (SourceDocumentStorageException exception)
            {
                var isRetryable = exception.Code is not "content-conflict";
                var errorCode = isRetryable
                    ? "blob-deletion-unavailable"
                    : "blob-identity-conflict";
                var retry = await FailAsync(
                    claim, leaseId, errorCode, isRetryable, CancellationToken.None);
                if (retry) retryScheduled++; else failed++;
            }
        }

        return new SourceDocumentContentRetentionRunResult(
            claims.Count, completed, retryScheduled, failed);
    }

    private async Task<bool> FailAsync(
        SourceDocumentContentRetentionClaim claim,
        Guid leaseId,
        string errorCode,
        bool isRetryable,
        CancellationToken cancellationToken)
    {
        var mutation = await repository.FailAsync(
            claim.SourceDocumentId,
            leaseId,
            errorCode,
            isRetryable,
            timeProvider.GetUtcNow(),
            cancellationToken);
        return mutation.Succeeded && mutation.Code == "retry-scheduled";
    }
}
