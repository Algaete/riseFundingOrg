using FundingPlatform.Application.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class AiExplanationProcessingFunction(
    AiExplanationProcessingService service,
    IOptions<AiExplanationOptions> options,
    ILogger<AiExplanationProcessingFunction> logger)
{
    [Function(nameof(AiExplanationProcessingFunction))]
    public async Task RunAsync(
        [TimerTrigger("45 */1 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        var result = await service.ProcessAsync(cancellationToken);
        logger.LogInformation(
            "Structured explanation shadow cycle completed: claimed={Claimed}, completed={Completed}, failed={Failed}, deferred={Deferred}, skipped={Skipped}.",
            result.ClaimedCount,
            result.CompletedCount,
            result.FailedCount,
            result.DeferredCount,
            result.SkippedCount);
    }
}
