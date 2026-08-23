using FundingPlatform.Core.Projects;

namespace FundingPlatform.Application.Projects;

public interface IProjectRepository
{
    Task<IReadOnlyList<ProjectSummary>> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken);

    Task<ProjectDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken);

    Task<PersistedProject> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        string slug,
        ProjectData project,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken);

    Task<PersistedProject> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        ProjectData project,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken);

    Task<ProjectWorkflowMutation> RequestPublicationAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<ProjectWorkflowMutation> ArchiveAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<ProjectReviewQueuePage> ListReviewQueueAsync(
        Guid userPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<ProjectReviewDetails?> GetReviewDetailsAsync(
        Guid userPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken);

    Task<ProjectWorkflowMutation> ReviewAsync(
        Guid userPublicId,
        Guid projectPublicId,
        ProjectReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<PublicProjectDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken);
}

public sealed class ProjectDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Project data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
