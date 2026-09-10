using FundingPlatform.Core.Imports;

namespace FundingPlatform.Application.Imports;

public interface IImportRunActivation
{
    bool IsEnabled { get; }
    Task NotifyAsync(Guid runId, CancellationToken cancellationToken);
}

public sealed class ImportQueueActivationException(Exception innerException)
    : Exception("The import queue could not accept the notification.", innerException);

public interface IImportRunDispatchService
{
    Task<ImportRunResult<ImportRunAccepted>> DispatchAsync(
        Guid adminUserPublicId, Guid runId, CancellationToken cancellationToken);
}

/// <summary>
/// Persist first, then notify the durable queue. A failed send is NOT a 202:
/// the same idempotency key can safely replay the write and retry notification.
/// Reads never activate workers. Recovery is an explicit authenticated command.
/// </summary>
public sealed class OnDemandImportRunService(
    IImportRunService durableRuns,
    IImportRunActivation activation) : IImportRunService, IImportRunDispatchService
{
    public async Task<ImportRunResult<ImportRunAccepted>> CreateManualAsync(
        Guid adminUserPublicId, int fundingSourceId, string keyword, int maximumResults,
        string idempotencyKey, string correlationId, CancellationToken cancellationToken)
    {
        if (!activation.IsEnabled) return Unavailable("queue-disabled");
        var result = await durableRuns.CreateManualAsync(adminUserPublicId, fundingSourceId,
            keyword, maximumResults, idempotencyKey, correlationId, cancellationToken);
        return result.Outcome == ImportRunOutcome.Success && result.Value is not null
            ? await NotifyAsync(result, cancellationToken)
            : result;
    }

    public async Task<ImportRunResult<ImportRunAccepted>> DispatchAsync(
        Guid adminUserPublicId, Guid runId, CancellationToken cancellationToken)
    {
        // SQL rechecks the admin actor; possession of a run identifier is insufficient.
        var result = await durableRuns.GetAsync(adminUserPublicId, runId, cancellationToken);
        if (result.Outcome != ImportRunOutcome.Success || result.Value is null)
            return new(result.Outcome, Errors: result.Errors, Code: result.Code);
        if (!activation.IsEnabled) return Unavailable("queue-disabled");
        var run = result.Value;
        return await NotifyAsync(new(ImportRunOutcome.Success,
            new ImportRunAccepted(run.RunId, run.FundingSourceId, run.SourceName,
                run.Status, run.CreatedAtUtc, true), Code: "replayed"), cancellationToken);
    }

    private async Task<ImportRunResult<ImportRunAccepted>> NotifyAsync(
        ImportRunResult<ImportRunAccepted> result, CancellationToken cancellationToken)
    {
        if (result.Value!.Status is not (ImportRunStatus.Queued or ImportRunStatus.Running))
            return result;
        try
        {
            await activation.NotifyAsync(result.Value.RunId, cancellationToken);
            return result;
        }
        catch (ImportQueueActivationException)
        {
            // Preserve the committed run/outbox for replay or explicit recovery.
            return new(ImportRunOutcome.Unavailable, result.Value, Code: "queue-unavailable");
        }
    }

    private static ImportRunResult<ImportRunAccepted> Unavailable(string code) =>
        new(ImportRunOutcome.Unavailable, Code: code);

    public Task<ImportRunResult<ImportRunPage>> ListAsync(Guid adminUserPublicId,
        int? fundingSourceId, ImportRunStatus? status, int page, int pageSize,
        CancellationToken cancellationToken) => durableRuns.ListAsync(adminUserPublicId,
            fundingSourceId, status, page, pageSize, cancellationToken);

    public Task<ImportRunResult<ImportRunDetail>> GetAsync(Guid adminUserPublicId,
        Guid runId, CancellationToken cancellationToken) =>
        durableRuns.GetAsync(adminUserPublicId, runId, cancellationToken);
}
