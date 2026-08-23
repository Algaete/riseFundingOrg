using FundingPlatform.Application.Imports;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ImportOutboxDispatcherFunction(
    ImportOutboxDispatcherService dispatcher,
    IOptions<ImportWorkerOptions> options,
    ILogger<ImportOutboxDispatcherFunction> logger)
{
    [Function(nameof(ImportOutboxDispatcherFunction))]
    public async Task RunAsync(
        [TimerTrigger("0 * * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var count = await dispatcher.DispatchAsync(
            options.Value.OutboxBatchSize, cancellationToken);
        logger.LogInformation("Dispatched {MessageCount} import messages.", count);
    }
}
