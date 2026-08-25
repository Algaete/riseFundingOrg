using FundingPlatform.Core.Matching;

namespace FundingPlatform.Application.Matching;

public interface IProjectMatchingRepository
{
    Task<ProjectMatchingRunPage> ListRunsAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectMatchingRunListFilters filters,
        CancellationToken cancellationToken);

    Task<ProjectMatchingRunDetails?> GetRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid matchingRunPublicId,
        CancellationToken cancellationToken);

    Task<ProjectMatchingRunMutation> CreateRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);
}

public sealed class ProjectMatchingDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Project matching data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
