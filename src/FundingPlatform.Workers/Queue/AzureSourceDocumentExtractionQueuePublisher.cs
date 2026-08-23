using System.Text.Json;
using Azure.Storage.Queues;
using FundingPlatform.Application.Imports;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Workers.Queue;

public sealed class AzureSourceDocumentExtractionQueuePublisher(QueueClient queueClient) :
    ISourceDocumentExtractionQueuePublisher
{
    private static readonly JsonSerializerOptions SerializerOptions =
        new(JsonSerializerDefaults.Web);

    public async Task PublishAsync(
        SourceDocumentExtractionQueueMessage message,
        CancellationToken cancellationToken)
    {
        if (message.JobId == Guid.Empty || message.Version != 1)
            throw new ArgumentException("Document extraction queue message is invalid.", nameof(message));
        await queueClient.SendMessageAsync(
            JsonSerializer.Serialize(message, SerializerOptions), cancellationToken);
    }

    public async Task CreateIfNotExistsAsync(CancellationToken cancellationToken) =>
        _ = await queueClient.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

}
