using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public interface IFunderRepository
{
    Task<FunderPage> ListAdminAsync(
        Guid adminUserPublicId,
        string? query,
        FundingPublicationStatus? publicationStatus,
        bool includeInactive,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<FunderDetails?> GetAdminAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> CreateAsync(
        Guid adminUserPublicId,
        string slug,
        FunderData data,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> UpdateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        FunderData data,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> ReviewAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        FundingReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> StartCorrectionAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> DeactivateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<PublicFunderPage> ListPublishedAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<PublicFunderDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken);
}

public interface IFundingOpportunityEditorialRepository
{
    Task<FundingOpportunityAdminPage> ListAdminAsync(
        Guid adminUserPublicId,
        string? query,
        FundingPublicationStatus? publicationStatus,
        bool includeInactive,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken);

    Task<FundingOpportunityAdminDetails?> GetAdminAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> CreateAsync(
        Guid adminUserPublicId,
        string slug,
        FundingOpportunityEditorialData data,
        string snapshotJson,
        byte[] contentHash,
        decimal dataQualityScore,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> UpdateAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        FundingOpportunityEditorialData data,
        string snapshotJson,
        byte[] contentHash,
        decimal dataQualityScore,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> ReviewAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        FundingReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> StartCorrectionAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        string reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingEditorialMutation> DeactivateAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);
}

public interface IFundingSourceAdminRepository
{
    Task<IReadOnlyList<FundingSourceAdminOption>> ListAsync(
        Guid adminUserPublicId,
        CancellationToken cancellationToken);
}

public sealed class FundingEditorialDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Funding editorial data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
