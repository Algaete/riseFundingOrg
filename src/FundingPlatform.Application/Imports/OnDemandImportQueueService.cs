using FundingPlatform.Core.Imports;

namespace FundingPlatform.Application.Imports;

public sealed record ImportQueueDeliveryState(
    ImportRunStatus Status, DateTimeOffset? NextAttemptAtUtc, DateTimeOffset? LeaseUntilUtc);

public interface IImportQueueDeliveryRepository
{
    Task<ImportQueueDeliveryState?> GetAsync(Guid runId, bool confirmReceipt,
        CancellationToken cancellationToken);
}

public interface IImportRetryQueuePublisher
{
    Task PublishAfterAsync(ImportRunQueueMessage message, TimeSpan delay,
        CancellationToken cancellationToken);
}

/// <summary>
/// Called only for a delivered Storage Queue message. SQL remains authoritative
/// for attempts, leases, policy and terminal states. Delayed queue messages replace
/// the periodic SQL retry/watchdog scan; no timer, sleep loop or in-memory task.
/// </summary>
public sealed class OnDemandImportQueueService(
    IImportQueueDeliveryRepository deliveries,
    IImportRetryQueuePublisher queue,
    TimeProvider timeProvider)
{
    public async Task ProcessAsync(Guid runId,
        Func<Guid, CancellationToken, Task<ImportRunProcessingResult>> process,
        CancellationToken cancellationToken)
    {
        if (runId == Guid.Empty) return;
        var received = await deliveries.GetAsync(runId, true, cancellationToken);
        if (received is null || IsTerminal(received.Status)) return;

        // Unhandled failures/cancellation abandon the current delivery. The host's
        // durable visibility timeout remains the crash-recovery backstop.
        await process(runId, cancellationToken);

        var next = await deliveries.GetAsync(runId, false, cancellationToken);
        if (next is null || IsTerminal(next.Status)) return;
        var now = timeProvider.GetUtcNow();
        var due = next.Status == ImportRunStatus.Running
            ? next.LeaseUntilUtc ?? throw new InvalidOperationException("A running import requires a lease.")
            : next.NextAttemptAtUtc ?? now;
        var delay = due - now + TimeSpan.FromSeconds(1);
        if (delay < TimeSpan.FromSeconds(1)) delay = TimeSpan.FromSeconds(1);
        if (delay > TimeSpan.FromHours(1) + TimeSpan.FromSeconds(1))
            throw new InvalidOperationException("The import retry delay exceeds the bounded policy.");

        // Publish BEFORE acknowledging this delivery. If sending fails, the host
        // retries this message. Duplicates are fenced by the existing SQL lease.
        await queue.PublishAfterAsync(new(runId, 1), delay, cancellationToken);
    }

    private static bool IsTerminal(ImportRunStatus status) =>
        status is ImportRunStatus.Completed or ImportRunStatus.Partial or
            ImportRunStatus.Failed or ImportRunStatus.Canceled;
}
