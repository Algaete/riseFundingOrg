using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Imports;
using FundingPlatform.Application.FundingOpportunities;

namespace FundingPlatform.Application.Imports;

public interface IImportRunService
{
    Task<ImportRunResult<ImportRunAccepted>> CreateManualAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string keyword,
        int maximumResults,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken);

    Task<ImportRunResult<ImportRunPage>> ListAsync(
        Guid adminUserPublicId,
        int? fundingSourceId,
        ImportRunStatus? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken);

    Task<ImportRunResult<ImportRunDetail>> GetAsync(
        Guid adminUserPublicId,
        Guid runId,
        CancellationToken cancellationToken);
}

public interface IImportRunRepository
{
    Task<ImportRunCreateMutation> CreateManualAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string keyword,
        int maximumResults,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        string correlationId,
        CancellationToken cancellationToken);

    Task<ImportRunPage> ListAsync(
        Guid adminUserPublicId,
        int? fundingSourceId,
        ImportRunStatus? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken);

    Task<ImportRunDetail?> GetAsync(
        Guid adminUserPublicId,
        Guid runId,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ScheduledImportRun>> RequeueStrandedAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ScheduledImportRun>> CreateDueScheduledAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken);

    Task<ImportRunClaimMutation> ClaimAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken);

    Task<bool> RenewLeaseAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<PendingImportRunItem>> ListPendingItemsAsync(
        Guid runId,
        Guid leaseId,
        int batchSize,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<ImportObservationRecord> RecordObservationAsync(
        Guid runId,
        Guid leaseId,
        FundingSourceObservation observation,
        byte[] sourceItemKeyHash,
        CancellationToken cancellationToken);

    Task CompleteItemAsync(
        Guid runId,
        Guid leaseId,
        Guid itemId,
        Guid? opportunityId,
        FundingOpportunityUpsertOutcome outcome,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task FailItemAsync(
        Guid runId,
        Guid leaseId,
        Guid itemId,
        string stage,
        string errorCode,
        string safeMessage,
        bool isRetryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);

    Task CompleteRunAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task FailRunAsync(
        Guid runId,
        Guid leaseId,
        string stage,
        string errorCode,
        string safeMessage,
        bool isRetryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);
}

public interface IImportOutboxRepository
{
    Task<IReadOnlyList<ImportOutboxMessage>> ClaimAsync(
        string leaseOwner,
        int batchSize,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task CompleteAsync(
        Guid messageId,
        string leaseOwner,
        DateTimeOffset dispatchedAtUtc,
        CancellationToken cancellationToken);

    Task ReleaseAsync(
        Guid messageId,
        string leaseOwner,
        DateTimeOffset availableAtUtc,
        string errorCode,
        CancellationToken cancellationToken);
}

public interface IImportQueuePublisher
{
    Task PublishAsync(ImportRunQueueMessage message, CancellationToken cancellationToken);
}

public sealed record ImportRunCreateMutation(
    bool Succeeded,
    string Code,
    ImportRunAccepted? Run = null);

public sealed record ImportRunClaimMutation(
    bool Succeeded,
    string Code,
    ImportRunClaim? Claim = null);

public sealed record ImportObservationRecord(
    Guid ItemId,
    Guid RawObservationId,
    bool WasRawReplay,
    bool IsAlreadyCompleted);

public enum ImportRunOutcome
{
    Success,
    Invalid,
    NotFound,
    Forbidden,
    Conflict,
    Unavailable
}

public sealed record ImportRunResult<T>(
    ImportRunOutcome Outcome,
    T? Value = default,
    IReadOnlyDictionary<string, string[]>? Errors = null,
    string? Code = null);

public sealed class ImportRunDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Import data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
