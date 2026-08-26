namespace FundingPlatform.Contracts.Billing;

public sealed record SubscriptionFeatureResponse(
    string code, string name, bool enabled, decimal? limitValue, string? unit, decimal usageValue);

public sealed record SubscriptionPlanPriceResponse(
    int id, string interval, string currency, decimal amount, bool purchasable, string? provider);

public sealed record SubscriptionPlanResponse(
    short id, string code, string name, string? description, bool purchasable,
    IReadOnlyList<SubscriptionPlanPriceResponse> prices,
    IReadOnlyList<SubscriptionFeatureResponse> features);

public sealed record CurrentSubscriptionResponse(
    Guid organizationId, string planCode, string planName, string status,
    string? billingInterval, string? currency, decimal? amount,
    DateTimeOffset? currentPeriodStartUtc, DateTimeOffset? currentPeriodEndUtc,
    bool cancelAtPeriodEnd, DateTimeOffset? graceUntilUtc, bool freeFallback,
    IReadOnlyList<SubscriptionFeatureResponse> features, string? eTag);

public sealed record CreateSubscriptionCheckoutRequest(int planPriceId);

public sealed record SubscriptionCheckoutResponse(
    Guid id, Guid organizationId, int planPriceId, string planName,
    string interval, string currency, decimal amount, string status,
    string provider, string? checkoutUrl, DateTimeOffset expiresAtUtc,
    DateTimeOffset createdAtUtc, DateTimeOffset updatedAtUtc, bool replayed);

public sealed record SubscriptionUsageResponse(
    string featureCode, string featureName, bool enabled, decimal? limitValue,
    decimal usageValue, string? unit, DateTimeOffset periodStartUtc,
    DateTimeOffset periodEndUtc);

public sealed record AdminSubscriptionSummaryResponse(
    Guid organizationId, string organizationName, string planCode, string planName,
    string status, DateTimeOffset? currentPeriodEndUtc, bool cancelAtPeriodEnd,
    string? provider, string? providerSubscriptionReference, DateTimeOffset updatedAtUtc);

public sealed record AdminSubscriptionPageResponse(
    IReadOnlyList<AdminSubscriptionSummaryResponse> items,
    long totalCount, int page, int pageSize);

public sealed record AdminBillingDashboardResponse(
    long activeOrganizations, long activePaidSubscriptions, long pastDueSubscriptions,
    long pendingCheckouts, long failedWebhookEvents,
    decimal monthlyRecurringRevenueClp, DateTimeOffset generatedAtUtc);
