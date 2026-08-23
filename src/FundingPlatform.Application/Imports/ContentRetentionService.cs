namespace FundingPlatform.Application.Imports;

public sealed record ContentRetentionEnforcementResult(
    int RunsProcessed,
    int RawRedactedCount,
    int ItemRedactedCount,
    int ResultRedactedCount,
    int EvidenceRedactedCount);

public interface IContentRetentionRepository
{
    Task<ContentRetentionEnforcementResult> EnforceAsync(
        int batchSize,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed class ContentRetentionService(
    IContentRetentionRepository repository,
    TimeProvider timeProvider)
{
    public Task<ContentRetentionEnforcementResult> EnforceAsync(
        int batchSize,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 500)
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        return repository.EnforceAsync(
            batchSize, timeProvider.GetUtcNow(), cancellationToken);
    }
}

public sealed class ContentRetentionDataException(
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Content-retention enforcement failed with database error {databaseErrorNumber}.",
        innerException)
{
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
