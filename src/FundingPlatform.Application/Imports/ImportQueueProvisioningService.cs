namespace FundingPlatform.Application.Imports;

public interface IImportQueueProvisioningClient
{
    Task CreateIfNotExistsAsync(CancellationToken cancellationToken);
    Task<bool> ExistsAsync(CancellationToken cancellationToken);
}

public sealed class ImportQueueProvisioningService(
    IImportQueueProvisioningClient client,
    bool createIfMissing)
{
    public async Task EnsureReadyAsync(CancellationToken cancellationToken)
    {
        if (createIfMissing)
        {
            await client.CreateIfNotExistsAsync(cancellationToken);
            return;
        }

        if (!await client.ExistsAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "The imports queue is not provisioned. Create it through approved infrastructure before starting the worker.");
        }
    }
}
