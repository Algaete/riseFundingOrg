using FundingPlatform.Application.Imports;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.ExtractionWorkers.Functions;

public sealed class SourceDocumentExtractionQueueFunction(
    SourceDocumentExtractionProcessingService service,
    ILogger<SourceDocumentExtractionQueueFunction> logger)
{
    [Function(nameof(SourceDocumentExtractionQueueFunction))]
    public async Task RunAsync(
        [QueueTrigger("document-extractions", Connection = "DocumentExtractionQueueStorage")]
        string message,
        CancellationToken cancellationToken)
    {
        if (!SourceDocumentExtractionQueueMessageParser.TryParse(message, out var work))
        {
            logger.LogWarning("An invalid document extraction queue message was discarded.");
            return;
        }

        var outcome = await service.ProcessAsync(work.JobId, cancellationToken);
        logger.LogInformation(
            "Document extraction job {JobId} finished with {OutcomeCode}.",
            work.JobId,
            outcome);
    }
}

public sealed class SourceDocumentExtractionWatchdogFunction(
    SourceDocumentExtractionWatchdogService service,
    IOptions<SourceDocumentExtractionOptions> options,
    ILogger<SourceDocumentExtractionWatchdogFunction> logger)
{
    [Function(nameof(SourceDocumentExtractionWatchdogFunction))]
    public async Task RunAsync(
        [TimerTrigger("30 */5 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var count = await service.RequeueStrandedAsync(
            options.Value.WatchdogBatchSize, cancellationToken);
        logger.LogInformation(
            "Document extraction watchdog requeued {RequeuedCount} stranded jobs.", count);
    }
}
