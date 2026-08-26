namespace FundingPlatform.Contracts.Authentication;

public sealed record AdminUserSummaryResponse(
    Guid publicId,
    string email,
    string displayName,
    string preferredLocale,
    string status,
    bool emailConfirmed,
    bool mfaEnabled,
    DateTimeOffset? lastLoginAtUtc,
    DateTimeOffset createdAtUtc,
    IReadOnlyList<string> roles);

public sealed record AdminUserPageResponse(
    IReadOnlyList<AdminUserSummaryResponse> items,
    long totalCount,
    int page,
    int pageSize);
