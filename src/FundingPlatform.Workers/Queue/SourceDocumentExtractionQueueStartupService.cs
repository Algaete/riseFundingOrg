using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace FundingPlatform.Workers.Queue;

public sealed class SourceDocumentExtractionQueueStartupService(
    AzureSourceDocumentExtractionQueuePublisher publisher,
    DocumentExtractionQueueStorageSettings storage,
    ILogger<SourceDocumentExtractionQueueStartupService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (storage.UsesManagedIdentity)
        {
            // The production identity is intentionally sender-only. Queue
            // existence/read is an infrastructure concern and is not granted to
            // this host; SendMessage failures remain durable through the outbox.
            logger.LogInformation(
                "The durable document extraction queue is expected to be provisioned by infrastructure.");
        }
        else
        {
            await publisher.CreateIfNotExistsAsync(cancellationToken);
        }

        logger.LogInformation("The durable document extraction queue is ready.");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
