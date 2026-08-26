namespace FundingPlatform.Application.Administration;

public sealed record AdminOrganizationQuery(
    string? Search,
    byte? ProfileStatus,
    bool? IsActive,
    int Page,
    int PageSize);

public sealed record AdminOrganizationSummary(
    Guid PublicId,
    string Name,
    string CountryCode,
    string CountryName,
    string OrganizationTypeName,
    byte ProfileStatus,
    decimal ProfileCompleteness,
    bool IsActive,
    long MemberCount,
    long ProjectCount,
    string PlanCode,
    string PlanName,
    byte? SubscriptionStatus,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record AdminOrganizationPage(
    IReadOnlyList<AdminOrganizationSummary> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record AdminOrganizationDetail(
    Guid PublicId,
    string Name,
    string? LegalName,
    string CountryCode,
    string CountryName,
    string OrganizationTypeName,
    string? LegalEntityTypeName,
    string? OrganizationSizeName,
    int? EstablishedYear,
    string? WebsiteUrl,
    string? Description,
    byte ProfileStatus,
    decimal ProfileCompleteness,
    int ProfileVersion,
    bool IsActive,
    long MemberCount,
    long AdminMemberCount,
    long ProjectCount,
    long PublishedProjectCount,
    string PlanCode,
    string PlanName,
    byte? SubscriptionStatus,
    DateTimeOffset? CurrentPeriodEndUtc,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record AdminOperationalErrorQuery(
    string? Search,
    string? Category,
    bool? Retryable,
    int Page,
    int PageSize);

public sealed record AdminOperationalErrorItem(
    string Id,
    string Category,
    byte Severity,
    string Code,
    string Message,
    bool IsRetryable,
    DateTimeOffset OccurredAtUtc,
    Guid? RelatedResourcePublicId,
    string? SourceName);

public sealed record AdminOperationalErrorPage(
    IReadOnlyList<AdminOperationalErrorItem> Items,
    long TotalCount,
    int Page,
    int PageSize);

public interface IAdminOperationsRepository
{
    Task<AdminOrganizationPage> ListOrganizationsAsync(
        Guid adminUserPublicId,
        AdminOrganizationQuery query,
        CancellationToken cancellationToken);

    Task<AdminOrganizationDetail?> GetOrganizationAsync(
        Guid adminUserPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken);

    Task<AdminOperationalErrorPage> ListOperationalErrorsAsync(
        Guid adminUserPublicId,
        AdminOperationalErrorQuery query,
        CancellationToken cancellationToken);
}

public sealed class AdminOperationsService(IAdminOperationsRepository repository)
{
    public Task<AdminOrganizationPage> ListOrganizationsAsync(
        Guid adminUserPublicId,
        AdminOrganizationQuery query,
        CancellationToken cancellationToken) =>
        repository.ListOrganizationsAsync(adminUserPublicId, query, cancellationToken);

    public Task<AdminOrganizationDetail?> GetOrganizationAsync(
        Guid adminUserPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken) =>
        repository.GetOrganizationAsync(adminUserPublicId, organizationPublicId, cancellationToken);

    public Task<AdminOperationalErrorPage> ListOperationalErrorsAsync(
        Guid adminUserPublicId,
        AdminOperationalErrorQuery query,
        CancellationToken cancellationToken) =>
        repository.ListOperationalErrorsAsync(adminUserPublicId, query, cancellationToken);
}

public sealed class AdminOperationsDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Admin operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
