using FundingPlatform.Application.Alerts;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class AlertScheduleFunction(
    AlertProcessingService service,
    IOptions<AlertOptions> options,
    ILogger<AlertScheduleFunction> logger)
{
    [Function(nameof(AlertScheduleFunction))]
    public async Task RunAsync(
        [TimerTrigger("15 */5 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        await service.ProcessSchedulesAsync(cancellationToken);
        logger.LogInformation("Saved-search alert scheduling cycle completed.");
    }
}

public sealed class AlertDeliveryFunction(
    AlertProcessingService service,
    IOptions<AlertOptions> options,
    ILogger<AlertDeliveryFunction> logger)
{
    [Function(nameof(AlertDeliveryFunction))]
    public async Task RunAsync(
        [TimerTrigger("35 */1 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        await service.ProcessDeliveriesAsync(cancellationToken);
        logger.LogInformation("Saved-search alert delivery cycle completed.");
    }
}
