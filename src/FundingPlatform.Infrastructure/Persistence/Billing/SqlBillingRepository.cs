using System.Data;
using Dapper;
using FundingPlatform.Application.Billing;
using FundingPlatform.Core.Billing;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Billing;

public sealed class SqlBillingRepository(ISqlConnectionFactory connectionFactory) : IBillingRepository
{
    public async Task<IReadOnlyList<SubscriptionPlan>> ListPlansAsync(CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
            "dbo.FundingPlatform_usp_SubscriptionPlan_List", commandType: CommandType.StoredProcedure,
            commandTimeout: 20, cancellationToken: cancellationToken));
        var plans = (await reader.ReadAsync<PlanRow>()).ToArray();
        var prices = (await reader.ReadAsync<PriceRow>()).ToArray();
        var features = (await reader.ReadAsync<FeatureRow>()).ToArray();
        return plans.Select(plan => new SubscriptionPlan(plan.Id, plan.Code, plan.Name,
            plan.Description, plan.IsPurchasable,
            prices.Where(price => price.SubscriptionPlanId == plan.Id).Select(Map).ToArray(),
            features.Where(feature => feature.SubscriptionPlanId == plan.Id)
                .Select(feature => Map(feature, 0)).ToArray())).ToArray();
    }

    public async Task<CurrentSubscription?> GetCurrentAsync(Guid userPublicId,
        Guid organizationPublicId, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Subscription_GetCurrent",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                    NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
                commandTimeout: 20, cancellationToken: cancellationToken));
            var row = await reader.ReadSingleAsync<CurrentRow>();
            var features = (await reader.ReadAsync<FeatureUsageRow>()).Select(Map).ToArray();
            return Map(row, features);
        }
        catch (SqlException exception) when (exception.Number == 54703) { return null; }
    }

    public async Task<IReadOnlyList<SubscriptionUsage>?> GetUsageAsync(Guid userPublicId,
        Guid organizationPublicId, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<UsageRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SubscriptionUsage_List",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                    NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
                commandTimeout: 20, cancellationToken: cancellationToken));
            return rows.Select(row => new SubscriptionUsage(row.FeatureCode, row.FeatureName,
                row.IsEnabled, row.LimitValue, row.UsageValue, row.Unit,
                Utc(row.PeriodStartUtc), Utc(row.PeriodEndUtc))).ToArray();
        }
        catch (SqlException exception) when (exception.Number == 54703) { return null; }
    }

    public async Task<CheckoutPreparation> BeginCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, int planPriceId, byte[] idempotencyKeyHash,
        byte[] requestHash, DateTimeOffset nowUtc, DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<BeginRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SubscriptionCheckout_Begin",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                    PlanPriceId = planPriceId, IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash, NowUtc = nowUtc.UtcDateTime,
                    ExpiresAtUtc = expiresAtUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
            var outcome = Outcome(row.Code);
            var checkout = row.CheckoutPublicId.HasValue
                ? await GetCheckoutAsync(userPublicId, organizationPublicId,
                    row.CheckoutPublicId.Value, cancellationToken) : null;
            return new CheckoutPreparation(outcome, checkout, row.PayerEmail, row.ProviderPriceId);
        }
        catch (SqlException exception) when (exception.Number is 54703 or 54704)
        {
            return new CheckoutPreparation(exception.Number == 54704
                ? BillingMutationOutcome.Forbidden : BillingMutationOutcome.NotFound);
        }
    }

    public async Task<BillingMutationOutcome> RecordCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, Guid checkoutPublicId, string providerCheckoutId,
        Uri checkoutUri, DateTimeOffset providerUpdatedAtUtc, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<CodeRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_SubscriptionCheckout_RecordProvider",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                CheckoutPublicId = checkoutPublicId, ProviderCheckoutId = providerCheckoutId,
                CheckoutUrl = checkoutUri.AbsoluteUri,
                ProviderUpdatedAtUtc = providerUpdatedAtUtc.UtcDateTime,
                NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
            commandTimeout: 30, cancellationToken: cancellationToken));
        return Outcome(row.Code);
    }

    public async Task<SubscriptionCheckout?> GetCheckoutAsync(Guid userPublicId,
        Guid organizationPublicId, Guid checkoutPublicId, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleOrDefaultAsync<CheckoutRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_SubscriptionCheckout_Get",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                CheckoutPublicId = checkoutPublicId }, commandType: CommandType.StoredProcedure,
            commandTimeout: 15, cancellationToken: cancellationToken));
        return row is null ? null : Map(row);
    }

    public async Task<(BillingMutationOutcome Outcome, string? ProviderSubscriptionId)>
        BeginLifecycleAsync(Guid userPublicId, Guid organizationPublicId, bool resume,
            byte[]? expectedRowVersion, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<LifecycleRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_Subscription_LifecycleBegin",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                Resume = resume, ExpectedRowVersion = expectedRowVersion,
                NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
            commandTimeout: 20, cancellationToken: cancellationToken));
        return (Outcome(row.Code), row.ProviderSubscriptionId);
    }

    public async Task<BillingMutationOutcome> ApplyProviderSnapshotAsync(Guid? userPublicId,
        Guid? organizationPublicId, PaymentProviderSubscriptionSnapshot snapshot,
        DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        if (snapshot.LiveMode) return BillingMutationOutcome.ValidationFailed;
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<CodeRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_Subscription_ApplyProviderSnapshot",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                snapshot.ProviderSubscriptionId, snapshot.ProviderCustomerId, snapshot.StatusCode,
                CurrentPeriodStartUtc = snapshot.CurrentPeriodStartUtc?.UtcDateTime,
                CurrentPeriodEndUtc = snapshot.CurrentPeriodEndUtc?.UtcDateTime,
                snapshot.CancelAtPeriodEnd,
                ProviderUpdatedAtUtc = snapshot.ProviderUpdatedAtUtc.UtcDateTime,
                snapshot.ProviderPaymentId, snapshot.ProviderInvoiceId,
                snapshot.PaymentStatusCode, snapshot.PaymentAmount, snapshot.PaymentCurrency,
                PaidAtUtc = snapshot.PaidAtUtc?.UtcDateTime, snapshot.FailureCode,
                NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
            commandTimeout: 30, cancellationToken: cancellationToken));
        return Outcome(row.Code);
    }

    public async Task<bool> ReceiveWebhookAsync(VerifiedPaymentWebhook webhook,
        DateTimeOffset receivedAtUtc, CancellationToken cancellationToken)
    {
        if (webhook.LiveMode) return false;
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<CreatedRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_PaymentWebhookEvent_Receive",
            new { webhook.ProviderEventId, webhook.ProviderRequestId, webhook.EventType,
                webhook.ResourceType, webhook.ProviderResourceId, ProviderAction = webhook.Action,
                ProviderOccurredAtUtc = webhook.OccurredAtUtc?.UtcDateTime, webhook.PayloadHash,
                ReceivedAtUtc = receivedAtUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
            commandTimeout: 20, cancellationToken: cancellationToken));
        return row.Created;
    }

    public async Task<IReadOnlyList<PaymentWebhookLease>> ClaimWebhooksAsync(int batchSize,
        int leaseSeconds, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var rows = await connection.QueryAsync<WebhookLeaseRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_PaymentWebhookEvent_Claim",
            new { BatchSize = batchSize, LeaseSeconds = leaseSeconds,
                NowUtc = nowUtc.UtcDateTime }, commandType: CommandType.StoredProcedure,
            commandTimeout: 20, cancellationToken: cancellationToken));
        return rows.Select(row => new PaymentWebhookLease(row.Id, row.EventType,
            row.ProviderResourceId, row.LeaseId, Utc(row.LeaseUntilUtc))).ToArray();
    }

    public async Task<bool> CompleteWebhookAsync(long id, Guid leaseId, bool succeeded,
        bool retryable, string? errorCode, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<UpdatedRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_PaymentWebhookEvent_Complete",
            new { Id = id, LeaseId = leaseId, Succeeded = succeeded, Retryable = retryable,
                ErrorCode = errorCode, NowUtc = nowUtc.UtcDateTime },
            commandType: CommandType.StoredProcedure, commandTimeout: 20,
            cancellationToken: cancellationToken));
        return row.Updated;
    }

    public async Task<IReadOnlyList<SubscriptionReconciliationItem>> ListReconciliationAsync(
        int batchSize, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var rows = await connection.QueryAsync<ReconciliationRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_Subscription_ReconciliationList",
            new { BatchSize = batchSize, NowUtc = nowUtc.UtcDateTime },
            commandType: CommandType.StoredProcedure, commandTimeout: 20,
            cancellationToken: cancellationToken));
        return rows.Select(row => new SubscriptionReconciliationItem(
            row.ProviderSubscriptionId)).ToArray();
    }

    public async Task<AdminSubscriptionPage> ListAdminSubscriptionsAsync(Guid adminUserPublicId,
        string? query, SubscriptionStatus? status, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
            "dbo.FundingPlatform_usp_AdminSubscription_List",
            new { AdminUserPublicId = adminUserPublicId, Query = query,
                Status = status.HasValue ? (byte?)status.Value : null,
                PageNumber = pageNumber, PageSize = pageSize },
            commandType: CommandType.StoredProcedure, commandTimeout: 20,
            cancellationToken: cancellationToken));
        var total = await reader.ReadSingleAsync<TotalRow>();
        var rows = await reader.ReadAsync<AdminRow>();
        return new AdminSubscriptionPage(rows.Select(Map).ToArray(), total.TotalCount,
            pageNumber, pageSize);
    }

    public async Task<AdminBillingDashboard> GetAdminDashboardAsync(Guid adminUserPublicId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<DashboardRow>(new CommandDefinition(
            "dbo.FundingPlatform_usp_AdminBillingDashboard_Get",
            new { AdminUserPublicId = adminUserPublicId, NowUtc = nowUtc.UtcDateTime },
            commandType: CommandType.StoredProcedure, commandTimeout: 20,
            cancellationToken: cancellationToken));
        return new AdminBillingDashboard(row.ActiveOrganizations,
            row.ActivePaidSubscriptions, row.PastDueSubscriptions, row.PendingCheckouts,
            row.FailedWebhookEvents, row.MonthlyRecurringRevenueClp, Utc(row.GeneratedAtUtc));
    }

    private static CurrentSubscription Map(CurrentRow row, IReadOnlyList<SubscriptionFeature> features) =>
        new(row.OrganizationPublicId, row.PlanCode, row.PlanName,
            row.Status.HasValue ? (SubscriptionStatus?)row.Status.Value : null,
            row.BillingInterval.HasValue ? (BillingInterval?)row.BillingInterval.Value : null,
            row.Currency, row.Amount, Utc(row.CurrentPeriodStartUtc), Utc(row.CurrentPeriodEndUtc),
            row.CancelAtPeriodEnd, Utc(row.GraceUntilUtc), row.IsFreeFallback, features,
            row.RowVersion is null ? null : $"\"{Convert.ToHexString(row.RowVersion)}\"");
    private static SubscriptionPlanPrice Map(PriceRow row) => new(row.Id,
        (BillingInterval)row.BillingInterval, row.Currency, row.Amount,
        row.IsPurchasable, row.Provider);
    private static SubscriptionFeature Map(FeatureRow row, decimal usage) => new(
        row.FeatureCode, row.Name, row.IsEnabled, row.LimitValue, row.Unit, usage);
    private static SubscriptionFeature Map(FeatureUsageRow row) => new(row.FeatureCode,
        row.Name, row.IsEnabled, row.LimitValue, row.Unit, row.UsageValue);
    private static SubscriptionCheckout Map(CheckoutRow row) => new(row.PublicId,
        row.OrganizationPublicId, row.PlanPriceId, row.PlanName,
        (BillingInterval)row.BillingInterval, row.Currency, row.Amount,
        (CheckoutStatus)row.Status, row.Provider, row.ExternalReference,
        Uri.TryCreate(row.CheckoutUrl, UriKind.Absolute, out var uri) ? uri : null,
        Utc(row.ExpiresAtUtc), Utc(row.CreatedAtUtc), Utc(row.UpdatedAtUtc));
    private static AdminSubscriptionSummary Map(AdminRow row) => new(
        row.OrganizationPublicId, row.OrganizationName, row.PlanCode, row.PlanName,
        row.Status.HasValue ? (SubscriptionStatus?)row.Status.Value : null,
        Utc(row.CurrentPeriodEndUtc), row.CancelAtPeriodEnd, row.Provider,
        row.ProviderSubscriptionId, Utc(row.UpdatedAtUtc));
    private static BillingMutationOutcome Outcome(string code) => code switch
    {
        "created" => BillingMutationOutcome.Created,
        "replayed" => BillingMutationOutcome.Replay,
        "updated" => BillingMutationOutcome.Updated,
        "accepted" => BillingMutationOutcome.Accepted,
        "not-found" => BillingMutationOutcome.NotFound,
        "forbidden" => BillingMutationOutcome.Forbidden,
        "idempotency-conflict" => BillingMutationOutcome.IdempotencyConflict,
        "checkout-already-open" => BillingMutationOutcome.CheckoutAlreadyOpen,
        "invalid-transition" => BillingMutationOutcome.InvalidTransition,
        "etag-conflict" => BillingMutationOutcome.PreconditionFailed,
        _ => BillingMutationOutcome.ValidationFailed
    };
    private static DateTimeOffset Utc(DateTime value) => new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
    private static DateTimeOffset? Utc(DateTime? value) => value.HasValue ? Utc(value.Value) : null;

    private sealed record PlanRow(short Id, string Code, string Name, string? Description, bool IsPurchasable);
    private sealed record PriceRow(short SubscriptionPlanId, int Id, byte BillingInterval,
        string Currency, decimal Amount, bool IsPurchasable, string? Provider);
    private sealed record FeatureRow(short SubscriptionPlanId, string FeatureCode, string Name,
        bool IsEnabled, decimal? LimitValue, string? Unit);
    private sealed record FeatureUsageRow(string FeatureCode, string Name, bool IsEnabled,
        decimal? LimitValue, string? Unit, decimal UsageValue);
    private sealed record CurrentRow(Guid OrganizationPublicId, string PlanCode, string PlanName,
        byte? Status, byte? BillingInterval, string? Currency, decimal? Amount,
        DateTime? CurrentPeriodStartUtc, DateTime? CurrentPeriodEndUtc,
        bool CancelAtPeriodEnd, DateTime? GraceUntilUtc, bool IsFreeFallback, byte[]? RowVersion);
    private sealed record UsageRow(string FeatureCode, string FeatureName, bool IsEnabled,
        decimal? LimitValue, decimal UsageValue, string? Unit,
        DateTime PeriodStartUtc, DateTime PeriodEndUtc);
    private sealed record BeginRow(string Code, Guid? CheckoutPublicId,
        string? PayerEmail, string? ProviderPriceId);
    private sealed record CodeRow(string Code);
    private sealed record LifecycleRow(string Code, string? ProviderSubscriptionId);
    private sealed record CheckoutRow(Guid PublicId, Guid OrganizationPublicId, int PlanPriceId,
        string PlanName, byte BillingInterval, string Currency, decimal Amount, byte Status,
        string Provider, Guid ExternalReference, string? CheckoutUrl, DateTime ExpiresAtUtc,
        DateTime CreatedAtUtc, DateTime UpdatedAtUtc);
    private sealed record CreatedRow(bool Created);
    private sealed record UpdatedRow(bool Updated);
    private sealed record WebhookLeaseRow(long Id, string EventType,
        string ProviderResourceId, Guid LeaseId, DateTime LeaseUntilUtc);
    private sealed record ReconciliationRow(string ProviderSubscriptionId);
    private sealed record TotalRow(long TotalCount);
    private sealed record AdminRow(Guid OrganizationPublicId, string OrganizationName,
        string PlanCode, string PlanName, byte? Status, DateTime? CurrentPeriodEndUtc,
        bool CancelAtPeriodEnd, string? Provider, string? ProviderSubscriptionId,
        DateTime UpdatedAtUtc);
    private sealed record DashboardRow(long ActiveOrganizations, long ActivePaidSubscriptions,
        long PastDueSubscriptions, long PendingCheckouts, long FailedWebhookEvents,
        decimal MonthlyRecurringRevenueClp, DateTime GeneratedAtUtc);
}
