using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class SourceDocumentContentRetentionFunction(
    SourceDocumentContentRetentionService service,
    IOptions<ContentRetentionOptions> options,
    ILogger<SourceDocumentContentRetentionFunction> logger)
{
    [Function(nameof(SourceDocumentContentRetentionFunction))]
    public async Task RunAsync(
        [TimerTrigger("30 */15 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var settings = options.Value;
        var result = await service.RunAsync(
            settings.SourceDocumentBatchSize,
            TimeSpan.FromSeconds(settings.SourceDocumentLeaseSeconds),
            cancellationToken);
        logger.LogInformation(
            "Source-document retention completed: claimed={ClaimedCount}, completed={CompletedCount}, retryScheduled={RetryScheduledCount}, failed={FailedCount}.",
            result.ClaimedCount,
            result.CompletedCount,
            result.RetryScheduledCount,
            result.FailedCount);
    }
}
