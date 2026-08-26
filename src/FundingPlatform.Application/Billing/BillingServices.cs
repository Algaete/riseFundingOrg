using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Billing;

namespace FundingPlatform.Application.Billing;

public sealed record CheckoutPreparation(
    BillingMutationOutcome Outcome,
    SubscriptionCheckout? Checkout = null,
    string? PayerEmail = null,
    string? ProviderPriceId = null);

public sealed record PaymentCheckoutRequest(
    Guid CheckoutPublicId,
    Guid ExternalReference,
    string PlanName,
    BillingInterval Interval,
    string Currency,
    decimal Amount,
    string PayerEmail,
    string? ProviderPriceId,
    Uri ReturnUri,
    Uri NotificationUri);

public sealed record PaymentCheckoutResult(
    string ProviderCheckoutId,
    Uri CheckoutUri,
    DateTimeOffset ProviderUpdatedAtUtc);

public sealed record PaymentProviderSubscriptionSnapshot(
    string ProviderSubscriptionId,
    string? ProviderCustomerId,
    string StatusCode,
    DateTimeOffset? CurrentPeriodStartUtc,
    DateTimeOffset? CurrentPeriodEndUtc,
    bool CancelAtPeriodEnd,
    DateTimeOffset ProviderUpdatedAtUtc,
    string? ProviderPaymentId = null,
    string? ProviderInvoiceId = null,
    string? PaymentStatusCode = null,
    decimal? PaymentAmount = null,
    string? PaymentCurrency = null,
    DateTimeOffset? PaidAtUtc = null,
    string? FailureCode = null,
    bool LiveMode = false);

public sealed record VerifiedPaymentWebhook(
    string ProviderEventId,
    string ProviderRequestId,
    string EventType,
    string? ResourceType,
    string ProviderResourceId,
    string? Action,
    DateTimeOffset? OccurredAtUtc,
    byte[] PayloadHash,
    bool LiveMode);

public sealed record PaymentWebhookLease(long Id, string EventType,
    string ProviderResourceId, Guid LeaseId, DateTimeOffset LeaseUntilUtc);

public sealed record SubscriptionReconciliationItem(string ProviderSubscriptionId);

public interface IPaymentGateway
{
    string ProviderCode { get; }
    Task<PaymentCheckoutResult> CreateOrRecoverCheckoutAsync(
        PaymentCheckoutRequest request, CancellationToken cancellationToken);
    Task<PaymentProviderSubscriptionSnapshot?> GetSubscriptionAsync(
        string providerSubscriptionId, CancellationToken cancellationToken);
    Task<PaymentProviderSubscriptionSnapshot?> FindSubscriptionAsync(
        Guid externalReference, CancellationToken cancellationToken);
    Task<PaymentProviderSubscriptionSnapshot?> GetWebhookSnapshotAsync(
        string eventType, string providerResourceId, CancellationToken cancellationToken);
    Task<PaymentProviderSubscriptionSnapshot> CancelAsync(
        string providerSubscriptionId, CancellationToken cancellationToken);
    Task<PaymentProviderSubscriptionSnapshot> ResumeAsync(
        string providerSubscriptionId, CancellationToken cancellationToken);
}

public interface IPaymentWebhookVerifier
{
    VerifiedPaymentWebhook Verify(
        string signature, string requestId, string dataId, ReadOnlySpan<byte> payload,
        DateTimeOffset nowUtc);
}

public interface IBillingRepository
{
    Task<IReadOnlyList<SubscriptionPlan>> ListPlansAsync(CancellationToken cancellationToken);
    Task<CurrentSubscription?> GetCurrentAsync(Guid userPublicId, Guid organizationPublicId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<IReadOnlyList<SubscriptionUsage>?> GetUsageAsync(Guid userPublicId,
        Guid organizationPublicId, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<CheckoutPreparation> BeginCheckoutAsync(Guid userPublicId, Guid organizationPublicId,
        int planPriceId, byte[] idempotencyKeyHash, byte[] requestHash,
        DateTimeOffset nowUtc, DateTimeOffset expiresAtUtc, CancellationToken cancellationToken);
    Task<BillingMutationOutcome> RecordCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, Guid checkoutPublicId, string providerCheckoutId,
        Uri checkoutUri, DateTimeOffset providerUpdatedAtUtc, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
    Task<SubscriptionCheckout?> GetCheckoutAsync(Guid userPublicId, Guid organizationPublicId,
        Guid checkoutPublicId, CancellationToken cancellationToken);
    Task<(BillingMutationOutcome Outcome, string? ProviderSubscriptionId)> BeginLifecycleAsync(
        Guid userPublicId, Guid organizationPublicId, bool resume, byte[]? expectedRowVersion,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<BillingMutationOutcome> ApplyProviderSnapshotAsync(Guid? userPublicId,
        Guid? organizationPublicId, PaymentProviderSubscriptionSnapshot snapshot,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<bool> ReceiveWebhookAsync(VerifiedPaymentWebhook webhook,
        DateTimeOffset receivedAtUtc, CancellationToken cancellationToken);
    Task<IReadOnlyList<PaymentWebhookLease>> ClaimWebhooksAsync(int batchSize,
        int leaseSeconds, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<bool> CompleteWebhookAsync(long id, Guid leaseId, bool succeeded,
        bool retryable, string? errorCode, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<SubscriptionReconciliationItem>> ListReconciliationAsync(
        int batchSize, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<AdminSubscriptionPage> ListAdminSubscriptionsAsync(Guid adminUserPublicId,
        string? query, SubscriptionStatus? status, int pageNumber, int pageSize,
        CancellationToken cancellationToken);
    Task<AdminBillingDashboard> GetAdminDashboardAsync(Guid adminUserPublicId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);
}

public sealed record BillingPolicy(
    bool Enabled,
    bool SandboxOnly,
    int CheckoutExpiryMinutes,
    Uri FrontendBaseUri,
    Uri WebhookUri)
{
    public void EnsureValid()
    {
        if (!SandboxOnly || CheckoutExpiryMinutes is < 5 or > 60 ||
            !SafeWebUri(FrontendBaseUri) || !SafeWebUri(WebhookUri))
            throw new InvalidOperationException("Billing policy is invalid or not sandbox-only.");
    }

    private static bool SafeWebUri(Uri value) =>
        value.IsAbsoluteUri && (value.Scheme == Uri.UriSchemeHttps ||
            (value.Scheme == Uri.UriSchemeHttp && value.IsLoopback));
}

public sealed class BillingService(
    IBillingRepository repository,
    IPaymentGateway gateway,
    BillingPolicy policy,
    TimeProvider timeProvider)
{
    public Task<IReadOnlyList<SubscriptionPlan>> ListPlansAsync(
        CancellationToken cancellationToken) => repository.ListPlansAsync(cancellationToken);

    public Task<CurrentSubscription?> GetCurrentAsync(Guid userPublicId,
        Guid organizationPublicId, CancellationToken cancellationToken) =>
        ValidIdentity(userPublicId, organizationPublicId)
            ? repository.GetCurrentAsync(userPublicId, organizationPublicId,
                timeProvider.GetUtcNow(), cancellationToken)
            : Task.FromResult<CurrentSubscription?>(null);

    public Task<IReadOnlyList<SubscriptionUsage>?> GetUsageAsync(Guid userPublicId,
        Guid organizationPublicId, CancellationToken cancellationToken) =>
        ValidIdentity(userPublicId, organizationPublicId)
            ? repository.GetUsageAsync(userPublicId, organizationPublicId,
                timeProvider.GetUtcNow(), cancellationToken)
            : Task.FromResult<IReadOnlyList<SubscriptionUsage>?>(null);

    public async Task<BillingMutation> CreateCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, int planPriceId, string? idempotencyKey,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled)
            return new BillingMutation(BillingMutationOutcome.GatewayDisabled);
        if (!ValidIdentity(userPublicId, organizationPublicId) || planPriceId <= 0 ||
            !ValidIdempotencyKey(idempotencyKey))
            return Invalid("checkout", "El precio o la Idempotency-Key no son válidos.");

        var now = timeProvider.GetUtcNow();
        var preparation = await repository.BeginCheckoutAsync(userPublicId,
            organizationPublicId, planPriceId, Hash(idempotencyKey!),
            Hash($"SubscriptionCheckout/v1|{organizationPublicId:D}|{planPriceId}"), now,
            now.AddMinutes(policy.CheckoutExpiryMinutes), cancellationToken);
        if (preparation.Outcome == BillingMutationOutcome.Replay)
            return new BillingMutation(BillingMutationOutcome.Replay, preparation.Checkout);
        if (preparation.Outcome != BillingMutationOutcome.Created ||
            preparation.Checkout is null || string.IsNullOrWhiteSpace(preparation.PayerEmail))
            return new BillingMutation(preparation.Outcome, preparation.Checkout);

        try
        {
            var checkout = preparation.Checkout;
            var created = await gateway.CreateOrRecoverCheckoutAsync(new PaymentCheckoutRequest(
                checkout.PublicId, checkout.ExternalReference, checkout.PlanName,
                checkout.Interval, checkout.Currency, checkout.Amount,
                preparation.PayerEmail, preparation.ProviderPriceId,
                new Uri(policy.FrontendBaseUri, $"/subscription?checkout={checkout.PublicId:D}"),
                policy.WebhookUri), cancellationToken);
            var outcome = await repository.RecordCheckoutAsync(userPublicId,
                organizationPublicId, checkout.PublicId, created.ProviderCheckoutId,
                created.CheckoutUri, created.ProviderUpdatedAtUtc, now, cancellationToken);
            var persisted = await repository.GetCheckoutAsync(userPublicId,
                organizationPublicId, checkout.PublicId, cancellationToken);
            return new BillingMutation(outcome, persisted);
        }
        catch (PaymentGatewayException)
        {
            return new BillingMutation(BillingMutationOutcome.GatewayUnavailable,
                preparation.Checkout);
        }
    }

    public Task<SubscriptionCheckout?> GetCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, Guid checkoutPublicId,
        CancellationToken cancellationToken) =>
        ValidIdentity(userPublicId, organizationPublicId) && checkoutPublicId != Guid.Empty
            ? repository.GetCheckoutAsync(userPublicId, organizationPublicId,
                checkoutPublicId, cancellationToken)
            : Task.FromResult<SubscriptionCheckout?>(null);

    public async Task<BillingMutation> ChangeRenewalAsync(Guid userPublicId,
        Guid organizationPublicId, bool resume, byte[]? expectedRowVersion,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled)
            return new BillingMutation(BillingMutationOutcome.GatewayDisabled);
        if (!ValidIdentity(userPublicId, organizationPublicId) || expectedRowVersion?.Length != 8)
            return new BillingMutation(BillingMutationOutcome.PreconditionFailed);
        var now = timeProvider.GetUtcNow();
        var prepared = await repository.BeginLifecycleAsync(userPublicId,
            organizationPublicId, resume, expectedRowVersion, now, cancellationToken);
        if (prepared.Outcome != BillingMutationOutcome.Accepted ||
            string.IsNullOrWhiteSpace(prepared.ProviderSubscriptionId))
            return new BillingMutation(prepared.Outcome);
        try
        {
            var snapshot = resume
                ? await gateway.ResumeAsync(prepared.ProviderSubscriptionId, cancellationToken)
                : await gateway.CancelAsync(prepared.ProviderSubscriptionId, cancellationToken);
            var outcome = await repository.ApplyProviderSnapshotAsync(userPublicId,
                organizationPublicId, snapshot, now, cancellationToken);
            return new BillingMutation(outcome,
                Subscription: await GetCurrentAsync(userPublicId, organizationPublicId,
                    cancellationToken));
        }
        catch (PaymentGatewayException)
        {
            return new BillingMutation(BillingMutationOutcome.GatewayUnavailable);
        }
    }

    public Task<AdminSubscriptionPage> ListAdminAsync(Guid userPublicId, string? query,
        SubscriptionStatus? status, int page, int pageSize, CancellationToken cancellationToken)
    {
        if (userPublicId == Guid.Empty || page is < 1 or > 10_000 || pageSize is < 1 or > 50 ||
            query?.Length > 200)
            throw new ArgumentException("Invalid billing administration query.");
        return repository.ListAdminSubscriptionsAsync(userPublicId,
            string.IsNullOrWhiteSpace(query) ? null : query.Trim(), status,
            page, pageSize, cancellationToken);
    }

    public Task<AdminBillingDashboard> GetAdminDashboardAsync(Guid userPublicId,
        CancellationToken cancellationToken) => userPublicId == Guid.Empty
        ? throw new ArgumentException("Invalid administrator identity.")
        : repository.GetAdminDashboardAsync(userPublicId, timeProvider.GetUtcNow(), cancellationToken);

    private static BillingMutation Invalid(string key, string message) => new(
        BillingMutationOutcome.ValidationFailed, Errors: new Dictionary<string, string[]>
        { [key] = [message] });
    private static bool ValidIdentity(Guid user, Guid organization) =>
        user != Guid.Empty && organization != Guid.Empty;
    private static bool ValidIdempotencyKey(string? value) => value is { Length: >= 16 and <= 128 } &&
        value.All(character => character is >= '!' and <= '~');
    private static byte[] Hash(string value) => SHA256.HashData(Encoding.UTF8.GetBytes(value));
}

public sealed class PaymentGatewayException(string code, Exception? innerException = null)
    : Exception("Payment gateway operation failed.", innerException)
{
    public string Code { get; } = code;
}

public sealed class PaymentWebhookVerificationException(string code)
    : Exception("Payment webhook verification failed.")
{
    public string Code { get; } = code;
}

public sealed class PaymentWebhookIngressService(
    IPaymentWebhookVerifier verifier,
    IBillingRepository repository,
    TimeProvider timeProvider)
{
    public async Task<bool> ReceiveAsync(string signature, string requestId, string dataId,
        byte[] payload, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var verified = verifier.Verify(signature, requestId, dataId, payload, now);
        return await repository.ReceiveWebhookAsync(verified, now, cancellationToken);
    }
}

public sealed record BillingProcessingCycle(int Claimed, int Completed, int Retried, int Failed);

public sealed class BillingProcessingService(
    IBillingRepository repository,
    IPaymentGateway gateway,
    TimeProvider timeProvider)
{
    public async Task<BillingProcessingCycle> ProcessWebhooksAsync(int batchSize,
        int leaseSeconds, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var leases = await repository.ClaimWebhooksAsync(batchSize, leaseSeconds, now,
            cancellationToken);
        var completed = 0; var retried = 0; var failed = 0;
        foreach (var lease in leases)
        {
            try
            {
                var snapshot = await gateway.GetWebhookSnapshotAsync(lease.EventType,
                    lease.ProviderResourceId, cancellationToken);
                if (snapshot is null || snapshot.LiveMode)
                    throw new PaymentGatewayException("resource-not-found-or-live");
                var outcome = await repository.ApplyProviderSnapshotAsync(null, null,
                    snapshot, timeProvider.GetUtcNow(), cancellationToken);
                if (outcome is not (BillingMutationOutcome.Updated or BillingMutationOutcome.Replay))
                    throw new PaymentGatewayException("provider-snapshot-not-applicable");
                if (await repository.CompleteWebhookAsync(lease.Id, lease.LeaseId, true,
                    false, null, timeProvider.GetUtcNow(), cancellationToken)) completed++;
            }
            catch (PaymentGatewayException exception)
            {
                var retryable = exception.Code is "provider-unavailable" or "provider-http-429" or
                    "provider-http-500" or "provider-http-502" or "provider-http-503" or
                    "provider-http-504";
                if (await repository.CompleteWebhookAsync(lease.Id, lease.LeaseId, false,
                    retryable, SafeCode(exception.Code), timeProvider.GetUtcNow(), cancellationToken))
                { if (retryable) retried++; else failed++; }
            }
        }
        return new BillingProcessingCycle(leases.Count, completed, retried, failed);
    }

    public async Task<int> ReconcileAsync(int batchSize, CancellationToken cancellationToken)
    {
        var items = await repository.ListReconciliationAsync(batchSize,
            timeProvider.GetUtcNow(), cancellationToken);
        var completed = 0;
        foreach (var item in items)
        {
            var snapshot = await gateway.GetSubscriptionAsync(item.ProviderSubscriptionId,
                cancellationToken);
            if (snapshot is null || snapshot.LiveMode) continue;
            var outcome = await repository.ApplyProviderSnapshotAsync(null, null, snapshot,
                timeProvider.GetUtcNow(), cancellationToken);
            if (outcome is BillingMutationOutcome.Updated or BillingMutationOutcome.Replay) completed++;
        }
        return completed;
    }

    private static string SafeCode(string value) => value.Length <= 100 &&
        value.All(character => char.IsAsciiLetterOrDigit(character) || character == '-')
            ? value : "provider-error";
}
