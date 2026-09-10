using System.Text.Json;
using Azure.Identity;
using Azure.Storage.Queues;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;
using FundingPlatform.Infrastructure.Configuration;

namespace FundingPlatform.Infrastructure.Imports;

public sealed class AzureImportRunActivation : IImportRunActivation
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly QueueClient? queue;
    public bool IsEnabled { get; }

    public AzureImportRunActivation(ImportDispatchSettings settings)
    {
        IsEnabled = settings.Enabled;
        if (!IsEnabled) return;
        var options = new QueueClientOptions { MessageEncoding = QueueMessageEncoding.Base64 };
        options.Retry.MaxRetries = 2;
        options.Retry.NetworkTimeout = TimeSpan.FromSeconds(10);
        queue = settings.UseDevelopmentStorage
            ? new QueueClient("UseDevelopmentStorage=true", "imports", options)
            : new QueueClient(settings.QueueUri!,
                new ManagedIdentityCredential(ManagedIdentityId.FromUserAssignedClientId(
                    settings.ManagedIdentityClientId!.Value.ToString("D"))), options);
    }

    public async Task NotifyAsync(Guid runId, CancellationToken cancellationToken)
    {
        if (runId == Guid.Empty) throw new ArgumentException("A run identifier is required.", nameof(runId));
        if (queue is null) throw new ImportQueueActivationException(
            new InvalidOperationException("Import dispatch is disabled."));
        try
        {
            // Sender-only permission: never create/list/read queues or access account keys.
            await queue.SendMessageAsync(JsonSerializer.Serialize(new ImportRunQueueMessage(runId, 1), JsonOptions),
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception) { throw new ImportQueueActivationException(exception); }
    }
}
