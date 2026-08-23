using FundingPlatform.Application.Imports;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace FundingPlatform.Workers.Queue;

public sealed class ImportQueueStartupService(
    ImportQueueProvisioningService provisioning,
    ILogger<ImportQueueStartupService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        await provisioning.EnsureReadyAsync(cancellationToken);
        logger.LogInformation("The durable import queue is ready.");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
