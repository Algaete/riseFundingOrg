using FundingPlatform.Core.Applications;

namespace FundingPlatform.Application.Applications;

public interface IFundingApplicationRepository
{
    Task<FundingApplicationPage> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingApplicationListFilters filters,
        CancellationToken cancellationToken);

    Task<FundingApplicationDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        CancellationToken cancellationToken);

    Task<FundingApplicationMutation> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid fundingOpportunityPublicId,
        FundingApplicationData application,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<FundingApplicationMutation> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        byte[] expectedRowVersion,
        FundingApplicationData application,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<FundingCalendarItem>> ListCalendarAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken);
}

public sealed class FundingApplicationDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Funding application data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
