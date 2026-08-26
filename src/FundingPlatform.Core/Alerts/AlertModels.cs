using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Core.Alerts;

public sealed record SavedSearchSummary(
    Guid PublicId,
    string Name,
    string? Query,
    bool OnlyOpen,
    FundingOpportunitySearchSort Sort,
    bool HasActiveAlert,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record SavedSearchDetails(
    Guid PublicId,
    string Name,
    FundingOpportunitySearchFilters Filters,
    AlertSubscriptionDetails? Alert,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record SavedSearchPage(
    IReadOnlyList<SavedSearchSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record AlertSubscriptionDetails(
    Guid PublicId,
    byte PreferredHourLocal,
    string TimeZoneId,
    DateTimeOffset NextRunAtUtc,
    DateTimeOffset? LastRunAtUtc,
    bool IsActive,
    string? DisabledReasonCode,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public enum SavedSearchMutationOutcome
{
    Created,
    Updated,
    Deleted,
    Unchanged,
    Replay,
    NotFound,
    PreconditionFailed,
    IdempotencyConflict,
    Invalid
}

public sealed record SavedSearchMutation(
    SavedSearchMutationOutcome Outcome,
    SavedSearchDetails? SavedSearch = null);

public enum AlertSubscriptionMutationOutcome
{
    Created,
    Updated,
    Deleted,
    Unchanged,
    NotFound,
    PreconditionFailed,
    Disabled
}

public sealed record AlertSubscriptionMutation(
    AlertSubscriptionMutationOutcome Outcome,
    AlertSubscriptionDetails? Alert = null);

public enum NotificationDeliveryStatus : byte
{
    Pending = 0,
    Processing = 1,
    Sent = 2,
    RetryScheduled = 3,
    Unknown = 4,
    PermanentFailed = 5,
    Skipped = 6
}

public sealed record NotificationLogSummary(
    Guid PublicId,
    Guid? AlertSubscriptionPublicId,
    Guid? SavedSearchPublicId,
    string? SavedSearchName,
    NotificationDeliveryStatus Status,
    int ItemCount,
    bool WasTruncated,
    DateTimeOffset ScheduledForUtc,
    DateTimeOffset? SentAtUtc,
    string? ErrorCode,
    DateTimeOffset CreatedAtUtc);

public sealed record NotificationLogPage(
    IReadOnlyList<NotificationLogSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record AlertScheduleLease(
    Guid AlertSubscriptionPublicId,
    Guid LeaseId,
    DateTimeOffset LeaseUntilUtc,
    DateTimeOffset ScheduledForUtc,
    byte PreferredHourLocal,
    string TimeZoneId);

public sealed record AlertScheduleMaterialization(
    bool Succeeded,
    string Code,
    Guid NotificationLogPublicId,
    int ItemCount,
    bool WasTruncated);

public sealed record AlertDeliveryLease(
    Guid NotificationLogPublicId,
    Guid AlertSubscriptionPublicId,
    Guid LeaseId,
    DateTimeOffset LeaseUntilUtc,
    string RecipientEmail,
    string RecipientDisplayName,
    string Locale,
    Guid UnsubscribeNonce,
    string SavedSearchName,
    DateTimeOffset ScheduledForUtc,
    int AttemptCount,
    IReadOnlyList<AlertDeliveryItem> Items);

public sealed record AlertDeliveryItem(
    Guid FundingOpportunityPublicId,
    string Slug,
    string Title,
    string SponsorName,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    FundingDeadlineType DeadlineType,
    FundingDeadlinePrecision DeadlinePrecision);

public sealed record AlertEmailMessage(
    Guid NotificationLogPublicId,
    string RecipientEmail,
    string RecipientDisplayName,
    string Locale,
    string SavedSearchName,
    string UnsubscribeToken,
    IReadOnlyList<AlertDeliveryItem> Items);

public sealed record AlertEmailDeliveryResult(
    string ProviderMessageId);
