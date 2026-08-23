using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using FundingPlatform.Application.Imports;

namespace FundingPlatform.Workers.Functions;

public sealed class ImportQueueFunction(
    ImportRunProcessingService service,
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
        return service.ProcessAsync(queueMessage.RunId, cancellationToken);
    }
}
