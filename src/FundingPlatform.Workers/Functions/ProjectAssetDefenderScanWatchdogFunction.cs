using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class ProjectAssetDefenderScanWatchdogFunction(
    ProjectAssetDefenderScanWatchdogService service,
    IOptions<ProjectAssetDefenderWorkerOptions> options,
    IOptions<ProjectAssetMaintenanceOptions> maintenance,
    ILogger<ProjectAssetDefenderScanWatchdogFunction> logger)
{
    [Function(nameof(ProjectAssetDefenderScanWatchdogFunction))]
    public async Task RunAsync(
        [TimerTrigger("0 */5 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled || !maintenance.Value.AllowSqlPolling) return;
        var timedOut = await service.RunAsync(
            options.Value.WatchdogBatchSize,
            options.Value.PendingScanTimeoutMinutes,
            cancellationToken);
        logger.LogInformation(
            "Project-asset Defender watchdog terminalized {TimedOutCount} overdue assets.",
            timedOut.Count);
    }
}
