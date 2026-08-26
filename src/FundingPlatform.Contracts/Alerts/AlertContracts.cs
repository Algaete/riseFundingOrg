namespace FundingPlatform.Contracts.Alerts;

public sealed record SavedSearchWriteRequest(
    string Name,
    string? Query,
    string? Sponsor,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    string? Currency,
    DateOnly? ClosingFrom,
    DateOnly? ClosingTo,
    bool OnlyOpen,
    string? Sort,
    IReadOnlyList<short>? CountryIds,
    IReadOnlyList<int>? RegionIds,
    IReadOnlyList<int>? CategoryIds,
    IReadOnlyList<long>? TagIds,
    IReadOnlyList<int>? BeneficiaryTypeIds,
    IReadOnlyList<int>? ProjectTypeIds,
    IReadOnlyList<short>? FundingTypeIds,
    IReadOnlyList<short>? OrganizationTypeIds,
    IReadOnlyList<Guid>? FunderIds);

public sealed record AlertSubscriptionWriteRequest(
    byte PreferredHourLocal,
    string TimeZoneId);

public sealed record SavedSearchListItemResponse(
    Guid Id,
    string Name,
    string? Query,
    bool OnlyOpen,
    string Sort,
    bool HasActiveAlert,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record SavedSearchListResponse(
    IReadOnlyList<SavedSearchListItemResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record AlertSubscriptionResponse(
    Guid Id,
    byte PreferredHourLocal,
    string TimeZoneId,
    DateTimeOffset NextRunAtUtc,
    DateTimeOffset? LastRunAtUtc,
    bool IsActive,
    string? DisabledReasonCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record SavedSearchDetailResponse(
    Guid Id,
    string Name,
    SavedSearchWriteRequest Filters,
    AlertSubscriptionResponse? Alert,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record NotificationLogListItemResponse(
    Guid Id,
    Guid? AlertSubscriptionId,
    Guid? SavedSearchId,
    string? SavedSearchName,
    string Status,
    int ItemCount,
    bool WasTruncated,
    DateTimeOffset ScheduledForUtc,
    DateTimeOffset? SentAtUtc,
    string? ErrorCode,
    DateTimeOffset CreatedAtUtc);

public sealed record NotificationLogListResponse(
    IReadOnlyList<NotificationLogListItemResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record UnsubscribeAlertRequest(string Token);
