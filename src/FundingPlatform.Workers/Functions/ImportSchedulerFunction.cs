using FundingPlatform.Application.Imports;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ImportSchedulerFunction(
    ImportSchedulerService scheduler,
    IOptions<ImportWorkerOptions> options,
    ILogger<ImportSchedulerFunction> logger)
{
    [Function(nameof(ImportSchedulerFunction))]
    public async Task RunAsync(
        [TimerTrigger("0 */5 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var requeued = await scheduler.RequeueStrandedAsync(
            options.Value.SchedulerBatchSize, cancellationToken);
        var runs = await scheduler.ScheduleDueAsync(
            options.Value.SchedulerBatchSize, cancellationToken);
        logger.LogInformation(
            "Import scheduler requeued {RequeuedCount} stranded runs and created or replayed {RunCount} due runs.",
            requeued.Count,
            runs.Count);
    }
}
