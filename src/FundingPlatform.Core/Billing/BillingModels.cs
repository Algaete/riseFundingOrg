namespace FundingPlatform.Core.Billing;

public enum BillingInterval : byte
{
    Monthly = 1,
    Annual = 2
}

public enum SubscriptionStatus : byte
{
    Pending = 0,
    Trialing = 1,
    Active = 2,
    PastDue = 3,
    Canceled = 4,
    Expired = 5
}

public enum CheckoutStatus : byte
{
    Creating = 0,
    Pending = 1,
    Completed = 2,
    Failed = 3,
    Expired = 4
}

public sealed record SubscriptionFeature(
    string Code,
    string Name,
    bool IsEnabled,
    decimal? LimitValue,
    string? Unit,
    decimal UsageValue);

public sealed record SubscriptionPlanPrice(
    int Id,
    BillingInterval Interval,
    string Currency,
    decimal Amount,
    bool IsPurchasable,
    string? Provider);

public sealed record SubscriptionPlan(
    short Id,
    string Code,
    string Name,
    string? Description,
    bool IsPurchasable,
    IReadOnlyList<SubscriptionPlanPrice> Prices,
    IReadOnlyList<SubscriptionFeature> Features);

public sealed record CurrentSubscription(
    Guid OrganizationPublicId,
    string PlanCode,
    string PlanName,
    SubscriptionStatus? Status,
    BillingInterval? BillingInterval,
    string? Currency,
    decimal? Amount,
    DateTimeOffset? CurrentPeriodStartUtc,
    DateTimeOffset? CurrentPeriodEndUtc,
    bool CancelAtPeriodEnd,
    DateTimeOffset? GraceUntilUtc,
    bool IsFreeFallback,
    IReadOnlyList<SubscriptionFeature> Features,
    string? ETag);

public sealed record SubscriptionCheckout(
    Guid PublicId,
    Guid OrganizationPublicId,
    int PlanPriceId,
    string PlanName,
    BillingInterval Interval,
    string Currency,
    decimal Amount,
    CheckoutStatus Status,
    string Provider,
    Guid ExternalReference,
    Uri? CheckoutUri,
    DateTimeOffset ExpiresAtUtc,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record SubscriptionUsage(
    string FeatureCode,
    string FeatureName,
    bool IsEnabled,
    decimal? LimitValue,
    decimal UsageValue,
    string? Unit,
    DateTimeOffset PeriodStartUtc,
    DateTimeOffset PeriodEndUtc);

public enum BillingMutationOutcome
{
    Created,
    Replay,
    Updated,
    Accepted,
    NotFound,
    Forbidden,
    ValidationFailed,
    IdempotencyConflict,
    CheckoutAlreadyOpen,
    GatewayDisabled,
    GatewayUnavailable,
    InvalidTransition,
    PreconditionFailed
}

public sealed record BillingMutation(
    BillingMutationOutcome Outcome,
    SubscriptionCheckout? Checkout = null,
    CurrentSubscription? Subscription = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record AdminSubscriptionSummary(
    Guid OrganizationPublicId,
    string OrganizationName,
    string PlanCode,
    string PlanName,
    SubscriptionStatus? Status,
    DateTimeOffset? CurrentPeriodEndUtc,
    bool CancelAtPeriodEnd,
    string? Provider,
    string? ProviderSubscriptionReference,
    DateTimeOffset UpdatedAtUtc);

public sealed record AdminSubscriptionPage(
    IReadOnlyList<AdminSubscriptionSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record AdminBillingDashboard(
    long ActiveOrganizations,
    long ActivePaidSubscriptions,
    long PastDueSubscriptions,
    long PendingCheckouts,
    long FailedWebhookEvents,
    decimal MonthlyRecurringRevenueClp,
    DateTimeOffset GeneratedAtUtc);
