using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using FundingPlatform.Application.Imports;
using FundingPlatform.Workers.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ImportQueueFunction(
    ImportRunProcessingService service,
    OnDemandImportQueueService onDemand,
    IOptions<ImportWorkerOptions> options,
    ILogger<ImportQueueFunction> logger)
{
    [Function(nameof(ImportQueueFunction))]
    public Task RunAsync(
        [QueueTrigger("imports", Connection = "AzureWebJobsStorage")] string message,
        CancellationToken cancellationToken)
    {
        if (!ImportQueueMessageParser.TryParse(message, out var queueMessage))
        {
            logger.LogWarning("An invalid import queue message was discarded.");
            return Task.CompletedTask;
        }

        logger.LogInformation("Processing import run {RunId}.", queueMessage.RunId);
        return options.Value.OnDemandOnly
            ? onDemand.ProcessAsync(queueMessage.RunId, service.ProcessAsync, cancellationToken)
            : service.ProcessAsync(queueMessage.RunId, cancellationToken);
    }
}
