using FundingPlatform.Application.Imports;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ContentRetentionFunction(
    ContentRetentionService service,
    IOptions<ContentRetentionOptions> options,
    ILogger<ContentRetentionFunction> logger)
{
    [Function(nameof(ContentRetentionFunction))]
    public async Task RunAsync(
        [TimerTrigger("0 */15 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var result = await service.EnforceAsync(
            options.Value.BatchSize, cancellationToken);
        logger.LogInformation(
            "Content retention completed: runs={RunsProcessed}, raw={RawCount}, items={ItemCount}, results={ResultCount}, evidence={EvidenceCount}.",
            result.RunsProcessed,
            result.RawRedactedCount,
            result.ItemRedactedCount,
            result.ResultRedactedCount,
            result.EvidenceRedactedCount);
    }
}
