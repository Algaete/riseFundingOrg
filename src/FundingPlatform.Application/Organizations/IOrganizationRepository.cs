using FundingPlatform.Core.Organizations;

namespace FundingPlatform.Application.Organizations;

public interface IOrganizationRepository
{
    Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<OrganizationSummary>> ListForUserAsync(
        Guid userPublicId,
        CancellationToken cancellationToken);

    Task<PersistedOrganization> CreateAsync(
        Guid userPublicId,
        OrganizationProfileData profile,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken);

    Task<OrganizationProfile?> GetProfileAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken);

    Task<PersistedOrganization> UpdateProfileAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        byte[] expectedRowVersion,
        OrganizationProfileData profile,
        byte profileStatus,
        decimal profileCompleteness,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken);
}

public sealed class OrganizationDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Organization data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;

    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
