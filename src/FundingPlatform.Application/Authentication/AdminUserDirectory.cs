using FundingPlatform.Core.Identity;

namespace FundingPlatform.Application.Authentication;

public sealed record AdminUserDirectoryQuery(
    string? Search,
    UserStatus? Status,
    string? Role,
    int Page,
    int PageSize);

public sealed record AdminUserDirectoryItem(
    Guid PublicId,
    string Email,
    string DisplayName,
    string PreferredLocale,
    UserStatus Status,
    bool EmailConfirmed,
    bool TwoFactorEnabled,
    DateTimeOffset? LastLoginAtUtc,
    DateTimeOffset CreatedAtUtc,
    IReadOnlyList<string> Roles);

public sealed record AdminUserDirectoryPage(
    IReadOnlyList<AdminUserDirectoryItem> Items,
    long TotalCount,
    int Page,
    int PageSize);

public interface IAdminUserDirectoryRepository
{
    Task<AdminUserDirectoryPage> ListAsync(
        AdminUserDirectoryQuery query,
        CancellationToken cancellationToken);
}

public sealed class AdminUserDirectoryService(IAdminUserDirectoryRepository repository)
{
    public Task<AdminUserDirectoryPage> ListAsync(
        AdminUserDirectoryQuery query,
        CancellationToken cancellationToken) =>
        repository.ListAsync(query, cancellationToken);
}
