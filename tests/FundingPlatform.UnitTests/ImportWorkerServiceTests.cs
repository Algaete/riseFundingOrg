using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.UnitTests;

public sealed class ImportWorkerServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 16, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Dispatcher_publishes_identifier_only_message_and_completes_outbox()
    {
        var runId = Guid.NewGuid();
        var messageId = Guid.NewGuid();
        var outbox = new FakeOutbox(new ImportOutboxMessage(
            messageId,
            "ImportRunRequested",
            $"{{\"runId\":\"{runId:D}\",\"version\":1}}",
            1));
        var queue = new FakeQueue();
        var service = new ImportOutboxDispatcherService(
            outbox, queue, new FixedTimeProvider(Now), "worker-test", TimeSpan.FromMinutes(5));

        var dispatched = await service.DispatchAsync(10, CancellationToken.None);

        Assert.Equal(1, dispatched);
        Assert.Equal(runId, Assert.Single(queue.Messages).RunId);
        Assert.Equal(messageId, Assert.Single(outbox.Completed));
        Assert.Empty(outbox.Released);
    }

    [Fact]
    public async Task Dispatcher_releases_malformed_message_without_publishing_it()
    {
        var messageId = Guid.NewGuid();
        var outbox = new FakeOutbox(new ImportOutboxMessage(
            messageId, "ImportRunRequested", "{not-json", 1));
        var queue = new FakeQueue();
        var service = new ImportOutboxDispatcherService(
            outbox, queue, new FixedTimeProvider(Now), "worker-test", TimeSpan.FromMinutes(5));

        var dispatched = await service.DispatchAsync(10, CancellationToken.None);

        Assert.Equal(0, dispatched);
        Assert.Empty(queue.Messages);
        var released = Assert.Single(outbox.Released);
        Assert.Equal(messageId, released.MessageId);
        Assert.Equal("invalid-import-outbox-message", released.Code);
    }

    [Fact]
    public async Task Dispatcher_releases_transient_queue_failure_with_backoff()
    {
        var runId = Guid.NewGuid();
        var messageId = Guid.NewGuid();
        var outbox = new FakeOutbox(new ImportOutboxMessage(
            messageId,
            "ImportRunRequested",
            $"{{\"runId\":\"{runId:D}\",\"version\":1}}",
            2));
        var queue = new FakeQueue { Failure = new InvalidOperationException("secret transport") };
        var service = new ImportOutboxDispatcherService(
            outbox, queue, new FixedTimeProvider(Now), "worker-test", TimeSpan.FromMinutes(5));

        var dispatched = await service.DispatchAsync(10, CancellationToken.None);

        Assert.Equal(0, dispatched);
        Assert.Empty(outbox.Completed);
        var released = Assert.Single(outbox.Released);
        Assert.Equal("queue-publish-failed", released.Code);
        Assert.True(released.AvailableAtUtc > Now);
    }

    [Fact]
    public async Task Scheduler_uses_database_due_state_and_current_utc_time()
    {
        var repository = new FakeImportRunRepository();
        var service = new ImportSchedulerService(repository, new FixedTimeProvider(Now));

        var requeued = await service.RequeueStrandedAsync(5, CancellationToken.None);
        var runs = await service.ScheduleDueAsync(7, CancellationToken.None);

        Assert.Empty(requeued);
        Assert.Empty(runs);
        Assert.Equal(Now, repository.RequeuedAtUtc);
        Assert.Equal(5, repository.RequeuedBatchSize);
        Assert.Equal(Now, repository.ScheduledAtUtc);
        Assert.Equal(7, repository.ScheduledBatchSize);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(101)]
    public async Task Scheduler_rejects_unbounded_recovery_batches(int batchSize)
    {
        var repository = new FakeImportRunRepository();
        var service = new ImportSchedulerService(repository, new FixedTimeProvider(Now));

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() =>
            service.RequeueStrandedAsync(batchSize, CancellationToken.None));

        Assert.Null(repository.RequeuedAtUtc);
    }

    [Fact]
    public async Task Queue_provisioning_creates_only_in_the_explicit_local_mode()
    {
        var client = new FakeQueueProvisioningClient();
        var service = new ImportQueueProvisioningService(client, createIfMissing: true);

        await service.EnsureReadyAsync(CancellationToken.None);

        Assert.Equal(1, client.CreateCalls);
        Assert.Equal(0, client.ExistsCalls);
    }

    [Fact]
    public async Task Queue_provisioning_requires_precreated_Azure_queue()
    {
        var readyClient = new FakeQueueProvisioningClient { Exists = true };
        await new ImportQueueProvisioningService(readyClient, createIfMissing: false)
            .EnsureReadyAsync(CancellationToken.None);
        Assert.Equal(0, readyClient.CreateCalls);
        Assert.Equal(1, readyClient.ExistsCalls);

        var missingClient = new FakeQueueProvisioningClient();
        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            new ImportQueueProvisioningService(missingClient, createIfMissing: false)
                .EnsureReadyAsync(CancellationToken.None));
        Assert.Contains("imports queue", exception.Message, StringComparison.Ordinal);
        Assert.Equal(0, missingClient.CreateCalls);
    }

    private sealed class FakeOutbox(params ImportOutboxMessage[] messages)
        : IImportOutboxRepository
    {
        public List<Guid> Completed { get; } = [];
        public List<(Guid MessageId, DateTimeOffset AvailableAtUtc, string Code)> Released { get; } = [];

        public Task<IReadOnlyList<ImportOutboxMessage>> ClaimAsync(
            string leaseOwner,
            int batchSize,
            TimeSpan leaseDuration,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<ImportOutboxMessage>>(messages);

        public Task CompleteAsync(
            Guid messageId,
            string leaseOwner,
            DateTimeOffset dispatchedAtUtc,
            CancellationToken cancellationToken)
        {
            Completed.Add(messageId);
            return Task.CompletedTask;
        }

        public Task ReleaseAsync(
            Guid messageId,
            string leaseOwner,
            DateTimeOffset availableAtUtc,
            string errorCode,
            CancellationToken cancellationToken)
        {
            Released.Add((messageId, availableAtUtc, errorCode));
            return Task.CompletedTask;
        }
    }

    private sealed class FakeQueue : IImportQueuePublisher
    {
        public List<ImportRunQueueMessage> Messages { get; } = [];
        public Exception? Failure { get; init; }

        public Task PublishAsync(
            ImportRunQueueMessage message,
            CancellationToken cancellationToken)
        {
            if (Failure is not null)
            {
                return Task.FromException(Failure);
            }

            Messages.Add(message);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeQueueProvisioningClient : IImportQueueProvisioningClient
    {
        public bool Exists { get; init; }
        public int CreateCalls { get; private set; }
        public int ExistsCalls { get; private set; }

        public Task CreateIfNotExistsAsync(CancellationToken cancellationToken)
        {
            CreateCalls++;
            return Task.CompletedTask;
        }

        public Task<bool> ExistsAsync(CancellationToken cancellationToken)
        {
            ExistsCalls++;
            return Task.FromResult(Exists);
        }
    }

    private sealed class FakeImportRunRepository : IImportRunRepository
    {
        public DateTimeOffset? RequeuedAtUtc { get; private set; }
        public int RequeuedBatchSize { get; private set; }
        public DateTimeOffset? ScheduledAtUtc { get; private set; }
        public int ScheduledBatchSize { get; private set; }

        public Task<IReadOnlyList<ScheduledImportRun>> RequeueStrandedAsync(
            DateTimeOffset nowUtc,
            int batchSize,
            CancellationToken cancellationToken)
        {
            RequeuedAtUtc = nowUtc;
            RequeuedBatchSize = batchSize;
            return Task.FromResult<IReadOnlyList<ScheduledImportRun>>([]);
        }

        public Task<IReadOnlyList<ScheduledImportRun>> CreateDueScheduledAsync(
            DateTimeOffset nowUtc,
            int batchSize,
            CancellationToken cancellationToken)
        {
            ScheduledAtUtc = nowUtc;
            ScheduledBatchSize = batchSize;
            return Task.FromResult<IReadOnlyList<ScheduledImportRun>>([]);
        }

        public Task<ImportRunCreateMutation> CreateManualAsync(
            Guid adminUserPublicId, int fundingSourceId, string keyword, int maximumResults,
            byte[] idempotencyKeyHash, byte[] requestHash, string correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<ImportRunPage> ListAsync(
            Guid adminUserPublicId, int? fundingSourceId, ImportRunStatus? status,
            int page, int pageSize, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<ImportRunDetail?> GetAsync(
            Guid adminUserPublicId, Guid runId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<ImportRunClaimMutation> ClaimAsync(
            Guid runId, Guid leaseId, DateTimeOffset nowUtc, TimeSpan leaseDuration,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> RenewLeaseAsync(
            Guid runId, Guid leaseId, DateTimeOffset nowUtc, TimeSpan leaseDuration,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<PendingImportRunItem>> ListPendingItemsAsync(
            Guid runId, Guid leaseId, int batchSize, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<ImportObservationRecord> RecordObservationAsync(
            Guid runId, Guid leaseId,
            FundingPlatform.Core.FundingOpportunities.FundingSourceObservation observation,
            byte[] sourceItemKeyHash, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task CompleteItemAsync(
            Guid runId, Guid leaseId, Guid itemId, Guid? opportunityId,
            FundingPlatform.Application.FundingOpportunities.FundingOpportunityUpsertOutcome outcome,
            DateTimeOffset completedAtUtc, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task FailItemAsync(
            Guid runId, Guid leaseId, Guid itemId, string stage, string errorCode,
            string safeMessage, bool isRetryable, DateTimeOffset failedAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task CompleteRunAsync(
            Guid runId, Guid leaseId, DateTimeOffset completedAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task FailRunAsync(
            Guid runId, Guid leaseId, string stage, string errorCode, string safeMessage,
            bool isRetryable, DateTimeOffset failedAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
