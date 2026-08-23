using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Workers.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class DefenderScanWatchdogFunction(
    DefenderScanWatchdogService service,
    IOptions<DefenderEventGridOptions> options,
    ILogger<DefenderScanWatchdogFunction> logger)
{
    [Function(nameof(DefenderScanWatchdogFunction))]
    public async Task RunAsync(
        [TimerTrigger("0 */5 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        var timedOut = await service.RunAsync(
            options.Value.WatchdogBatchSize,
            options.Value.PendingScanTimeoutMinutes,
            cancellationToken);
        logger.LogInformation(
            "Defender scan watchdog terminalized {TimedOutCount} overdue documents.",
            timedOut.Count);
    }
}
