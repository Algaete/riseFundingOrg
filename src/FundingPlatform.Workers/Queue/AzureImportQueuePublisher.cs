using System.Text.Json;
using Azure.Storage.Queues;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.Workers.Queue;

public sealed class AzureImportQueuePublisher(QueueClient queueClient) :
    IImportQueuePublisher,
    IImportRetryQueuePublisher,
    IImportQueueProvisioningClient
{
    private static readonly JsonSerializerOptions SerializerOptions =
        new(JsonSerializerDefaults.Web);

    public async Task PublishAsync(
        ImportRunQueueMessage message,
        CancellationToken cancellationToken)
    {
        if (message.RunId == Guid.Empty || message.Version != 1)
        {
            throw new ArgumentException("Import queue message is invalid.", nameof(message));
        }

        var payload = JsonSerializer.Serialize(message, SerializerOptions);
        await queueClient.SendMessageAsync(payload, cancellationToken);
    }

    public async Task CreateIfNotExistsAsync(CancellationToken cancellationToken) =>
        _ = await queueClient.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

    public async Task PublishAfterAsync(ImportRunQueueMessage message, TimeSpan delay,
        CancellationToken cancellationToken)
    {
        if (message.RunId == Guid.Empty || message.Version != 1 || delay < TimeSpan.Zero ||
            delay > TimeSpan.FromHours(1) + TimeSpan.FromSeconds(1))
            throw new ArgumentException("Invalid bounded import retry delivery.", nameof(message));
        await queueClient.SendMessageAsync(JsonSerializer.Serialize(message, SerializerOptions),
            visibilityTimeout: delay, timeToLive: TimeSpan.FromDays(7),
            cancellationToken: cancellationToken);
    }

    public async Task<bool> ExistsAsync(CancellationToken cancellationToken) =>
        (await queueClient.ExistsAsync(cancellationToken)).Value;
}
