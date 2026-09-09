using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ProjectAssetContentRetentionFunction(
    ProjectAssetContentRetentionService service,
    IOptions<ContentRetentionOptions> options,
    IOptions<ProjectAssetOptions> assets,
    ILogger<ProjectAssetContentRetentionFunction> logger)
{
    [Function(nameof(ProjectAssetContentRetentionFunction))]
    public async Task RunAsync(
        [TimerTrigger("45 */15 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!assets.Value.Enabled) return;
        var result = await service.RunAsync(
            options.Value.ProjectAssetBatchSize,
            TimeSpan.FromSeconds(options.Value.ProjectAssetLeaseSeconds),
            cancellationToken);
        logger.LogInformation(
            "Project-asset retention completed: claimed={ClaimedCount}, completed={CompletedCount}, retryScheduled={RetryScheduledCount}, failed={FailedCount}.",
            result.ClaimedCount, result.CompletedCount,
            result.RetryScheduledCount, result.FailedCount);
    }
}
