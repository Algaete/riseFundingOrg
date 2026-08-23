using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.UnitTests;

public sealed class SourceDocumentContentRetentionServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 16, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Requests_exact_quarantine_and_trusted_deletion_before_completing_lease()
    {
        var claim = CreateClaim(includeTrusted: true);
        var repository = new FakeRepository(claim);
        var blobs = new FakeRetentionBlobStore(
            new SourceBlobRetentionDeletion(true),
            new SourceBlobRetentionDeletion(true));
        var service = new SourceDocumentContentRetentionService(
            repository, blobs, new FixedTimeProvider(Now));

        var result = await service.RunAsync(
            25, TimeSpan.FromMinutes(15), CancellationToken.None);

        Assert.Equal(new SourceDocumentContentRetentionRunResult(1, 1, 0, 0), result);
        Assert.Equal(2, blobs.Requests.Count);
        Assert.Equal(claim.QuarantineETag, blobs.Requests[0].ETag);
        Assert.Equal(claim.TrustedETag, blobs.Requests[1].ETag);
        Assert.Equal(claim.ContentHash, blobs.Requests[0].Hash);
        Assert.Single(repository.Completions);
        Assert.Empty(repository.Failures);
    }

    [Fact]
    public async Task Active_version_after_bounded_deletion_schedules_a_retry()
    {
        var claim = CreateClaim(includeTrusted: false);
        var repository = new FakeRepository(claim);
        var blobs = new FakeRetentionBlobStore(new SourceBlobRetentionDeletion(false));
        var service = new SourceDocumentContentRetentionService(
            repository, blobs, new FixedTimeProvider(Now));

        var result = await service.RunAsync(
            10, TimeSpan.FromMinutes(5), CancellationToken.None);

        Assert.Equal(new SourceDocumentContentRetentionRunResult(1, 0, 1, 0), result);
        Assert.Empty(repository.Completions);
        var failure = Assert.Single(repository.Failures);
        Assert.Equal("active-blob-versions-remain", failure.ErrorCode);
        Assert.True(failure.IsRetryable);
    }

    [Fact]
    public async Task Etag_or_content_conflict_is_terminal_and_never_completes_deletion()
    {
        var claim = CreateClaim(includeTrusted: false);
        var repository = new FakeRepository(claim);
        var blobs = new FakeRetentionBlobStore(
            new SourceDocumentStorageException(
                "request-retention-deletion", "content-conflict", 409));
        var service = new SourceDocumentContentRetentionService(
            repository, blobs, new FixedTimeProvider(Now));

        var result = await service.RunAsync(
            10, TimeSpan.FromMinutes(5), CancellationToken.None);

        Assert.Equal(new SourceDocumentContentRetentionRunResult(1, 0, 0, 1), result);
        Assert.Empty(repository.Completions);
        var failure = Assert.Single(repository.Failures);
        Assert.Equal("blob-identity-conflict", failure.ErrorCode);
        Assert.False(failure.IsRetryable);
    }

    [Fact]
    public async Task Transient_storage_failure_preserves_durable_work_for_retry()
    {
        var claim = CreateClaim(includeTrusted: false);
        var repository = new FakeRepository(claim);
        var blobs = new FakeRetentionBlobStore(
            new SourceDocumentStorageException(
                "request-retention-deletion", "storage-unavailable", 503));
        var service = new SourceDocumentContentRetentionService(
            repository, blobs, new FixedTimeProvider(Now));

        var result = await service.RunAsync(
            10, TimeSpan.FromMinutes(5), CancellationToken.None);

        Assert.Equal(new SourceDocumentContentRetentionRunResult(1, 0, 1, 0), result);
        var failure = Assert.Single(repository.Failures);
        Assert.Equal("blob-deletion-unavailable", failure.ErrorCode);
        Assert.True(failure.IsRetryable);
    }

    [Fact]
    public async Task Missing_blobs_and_replayed_completion_are_idempotent_success()
    {
        var claim = CreateClaim(includeTrusted: true);
        var repository = new FakeRepository(claim) { CompletionWasReplay = true };
        var blobs = new FakeRetentionBlobStore(
            new SourceBlobRetentionDeletion(true),
            new SourceBlobRetentionDeletion(true));
        var service = new SourceDocumentContentRetentionService(
            repository, blobs, new FixedTimeProvider(Now));

        var result = await service.RunAsync(
            10, TimeSpan.FromMinutes(5), CancellationToken.None);

        Assert.Equal(new SourceDocumentContentRetentionRunResult(1, 1, 0, 0), result);
        Assert.Single(repository.Completions);
    }

    private static SourceDocumentContentRetentionClaim CreateClaim(bool includeTrusted) => new()
    {
        SourceDocumentId = Guid.NewGuid(),
        FundingSourceId = 7,
        ContentHash = Enumerable.Repeat((byte)0x42, 32).ToArray(),
        ContentLength = 1234,
        QuarantineLocation = new ProtectedBlobLocation(
            "fp-source-quarantine", "documents/a.pdf"),
        QuarantineETag = "\"0xABC\"",
        TrustedLocation = includeTrusted
            ? new ProtectedBlobLocation("fp-source-trusted", "documents/a.pdf")
            : null,
        TrustedETag = includeTrusted ? "\"0xDEF\"" : null,
        RetentionUntilUtc = Now.AddMinutes(-1),
        AttemptCount = 1,
        MaxAttempts = 8,
        LeaseUntilUtc = Now.AddMinutes(15)
    };

    private sealed class FakeRepository(
        params SourceDocumentContentRetentionClaim[] claims)
        : ISourceDocumentContentRetentionRepository
    {
        public bool CompletionWasReplay { get; init; }
        public List<(Guid DocumentId, bool Quarantine, bool Trusted)> Completions { get; } = [];
        public List<(Guid DocumentId, string ErrorCode, bool IsRetryable)> Failures { get; } = [];

        public Task<IReadOnlyList<SourceDocumentContentRetentionClaim>> ClaimAsync(
            int batchSize, Guid leaseId, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<SourceDocumentContentRetentionClaim>>(claims);

        public Task<SourceDocumentContentRetentionMutation> CompleteAsync(
            Guid sourceDocumentId, Guid leaseId, bool quarantineDeletionRequested,
            bool trustedDeletionRequested, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Completions.Add((
                sourceDocumentId, quarantineDeletionRequested, trustedDeletionRequested));
            return Task.FromResult(new SourceDocumentContentRetentionMutation(
                true,
                "completed",
                ContentDeletionRequestedAtUtc: nowUtc,
                WasReplay: CompletionWasReplay));
        }

        public Task<SourceDocumentContentRetentionMutation> FailAsync(
            Guid sourceDocumentId, Guid leaseId, string errorCode,
            bool isRetryable, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Failures.Add((sourceDocumentId, errorCode, isRetryable));
            return Task.FromResult(new SourceDocumentContentRetentionMutation(
                true,
                isRetryable ? "retry-scheduled" : "failed",
                NextAttemptAtUtc: isRetryable ? nowUtc.AddMinutes(1) : null));
        }
    }

    private sealed class FakeRetentionBlobStore(params object[] outcomes)
        : ISourceDocumentRetentionBlobStore
    {
        private int index;
        public List<(ProtectedBlobLocation Location, string ETag, byte[] Hash)> Requests { get; } = [];

        public Task<SourceBlobRetentionDeletion> RequestDeletionAsync(
            ProtectedBlobLocation location,
            string expectedETag,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            Requests.Add((location, expectedETag, [.. expectedContentHash]));
            var outcome = outcomes[index++];
            return outcome is Exception exception
                ? Task.FromException<SourceBlobRetentionDeletion>(exception)
                : Task.FromResult((SourceBlobRetentionDeletion)outcome);
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
