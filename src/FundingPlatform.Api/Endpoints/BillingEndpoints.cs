using System.Security.Claims;
using FundingPlatform.Application.Billing;
using FundingPlatform.Contracts.Billing;
using FundingPlatform.Core.Billing;

namespace FundingPlatform.Api.Endpoints;

public static class BillingEndpoints
{
    public static IEndpointRouteBuilder MapBillingEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/subscription-plans", ListPlansAsync)
            .WithTags("Subscriptions").AllowAnonymous().RequireRateLimiting("marketplace-read")
            .Produces<IReadOnlyList<SubscriptionPlanResponse>>();

        var group = endpoints.MapGroup("/api/v1/organizations/{organizationId:guid}")
            .WithTags("Subscriptions").RequireAuthorization("full-session");
        group.MapGet("/subscription", GetCurrentAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<CurrentSubscriptionResponse>().ProducesProblem(404);
        group.MapGet("/subscription/usage", GetUsageAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<IReadOnlyList<SubscriptionUsageResponse>>().ProducesProblem(404);
        group.MapPost("/subscription-checkouts", CreateCheckoutAsync)
            .RequireRateLimiting("billing-write")
            .Produces<SubscriptionCheckoutResponse>(201)
            .Produces<SubscriptionCheckoutResponse>(200)
            .ProducesValidationProblem(422).ProducesProblem(403).ProducesProblem(409)
            .ProducesProblem(428).ProducesProblem(503);
        group.MapGet("/subscription-checkouts/{checkoutId:guid}", GetCheckoutAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<SubscriptionCheckoutResponse>().ProducesProblem(404);
        group.MapPost("/subscription/cancel", CancelAsync)
            .RequireRateLimiting("billing-write").Produces<CurrentSubscriptionResponse>()
            .ProducesProblem(403).ProducesProblem(409).ProducesProblem(412)
            .ProducesProblem(428).ProducesProblem(503);
        group.MapPost("/subscription/resume", ResumeAsync)
            .RequireRateLimiting("billing-write").Produces<CurrentSubscriptionResponse>()
            .ProducesProblem(403).ProducesProblem(409).ProducesProblem(412)
            .ProducesProblem(428).ProducesProblem(503);

        endpoints.MapPost("/api/v1/webhooks/payments/mercado-pago", WebhookAsync)
            .WithTags("Payment webhooks").AllowAnonymous().RequireRateLimiting("payment-webhook")
            .DisableAntiforgery().Produces(200).Produces(401).Produces(413);

        var admin = endpoints.MapGroup("/api/v1/admin")
            .WithTags("Billing administration").RequireAuthorization("admin-mfa");
        admin.MapGet("/subscriptions", AdminListAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<AdminSubscriptionPageResponse>().ProducesValidationProblem();
        admin.MapGet("/dashboard", AdminDashboardAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<AdminBillingDashboardResponse>();
        return endpoints;
    }

    private static async Task<IResult> ListPlansAsync(BillingService service,
        HttpContext context, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok((await service.ListPlansAsync(cancellationToken)).Select(Map).ToArray());
    }

    private static async Task<IResult> GetCurrentAsync(Guid organizationId,
        ClaimsPrincipal principal, HttpContext context, BillingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var value = await service.GetCurrentAsync(userId, organizationId, cancellationToken);
        if (value is null) return NotFound();
        if (value.ETag is not null) context.Response.Headers.ETag = value.ETag;
        return Results.Ok(Map(value));
    }

    private static async Task<IResult> GetUsageAsync(Guid organizationId,
        ClaimsPrincipal principal, BillingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var value = await service.GetUsageAsync(userId, organizationId, cancellationToken);
        return value is null ? NotFound() : Results.Ok(value.Select(Map).ToArray());
    }

    private static async Task<IResult> CreateCheckoutAsync(Guid organizationId,
        CreateSubscriptionCheckoutRequest request, ClaimsPrincipal principal,
        HttpContext context, BillingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var key = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(key))
            return ProjectEndpointResults.PreconditionRequired("idempotency-key-required",
                "Idempotency-Key requerida", "Envía una clave estable para iniciar el checkout.");
        var result = await service.CreateCheckoutAsync(userId, organizationId,
            request.planPriceId, key, cancellationToken);
        if (result.Outcome is BillingMutationOutcome.Created or BillingMutationOutcome.Replay)
        {
            var response = Map(result.Checkout!, result.Outcome == BillingMutationOutcome.Replay);
            return result.Outcome == BillingMutationOutcome.Created
                ? Results.Created($"/api/v1/organizations/{organizationId:D}/subscription-checkouts/{response.id:D}", response)
                : Results.Ok(response);
        }
        return Failure(result);
    }

    private static async Task<IResult> GetCheckoutAsync(Guid organizationId, Guid checkoutId,
        ClaimsPrincipal principal, BillingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var value = await service.GetCheckoutAsync(userId, organizationId, checkoutId,
            cancellationToken);
        return value is null ? NotFound() : Results.Ok(Map(value, false));
    }

    private static Task<IResult> CancelAsync(Guid organizationId, ClaimsPrincipal principal,
        HttpContext context, BillingService service, CancellationToken cancellationToken) =>
        LifecycleAsync(organizationId, principal, context, service, false, cancellationToken);
    private static Task<IResult> ResumeAsync(Guid organizationId, ClaimsPrincipal principal,
        HttpContext context, BillingService service, CancellationToken cancellationToken) =>
        LifecycleAsync(organizationId, principal, context, service, true, cancellationToken);

    private static async Task<IResult> LifecycleAsync(Guid organizationId,
        ClaimsPrincipal principal, HttpContext context, BillingService service, bool resume,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(context.Request.Headers.IfMatch,
                out var expectedRowVersion))
            return ProjectEndpointResults.PreconditionRequired("if-match-required",
                "Versión requerida", "Recarga la suscripción y envía su ETag vigente.");
        var result = await service.ChangeRenewalAsync(userId, organizationId, resume,
            expectedRowVersion, cancellationToken);
        if (result.Outcome == BillingMutationOutcome.Updated && result.Subscription is not null)
        {
            if (result.Subscription.ETag is not null)
                context.Response.Headers.ETag = result.Subscription.ETag;
            return Results.Ok(Map(result.Subscription));
        }
        return Failure(result);
    }

    private static async Task<IResult> WebhookAsync(HttpRequest request,
        PaymentWebhookIngressService service, CancellationToken cancellationToken)
    {
        var dataId = request.Query["data.id"].ToString();
        if (string.IsNullOrWhiteSpace(dataId)) dataId = request.Query["data_id"].ToString();
        try
        {
            await using var memory = new MemoryStream();
            await request.Body.CopyToAsync(memory, cancellationToken);
            await service.ReceiveAsync(request.Headers["x-signature"].ToString(),
                request.Headers["x-request-id"].ToString(), dataId,
                memory.ToArray(), cancellationToken);
            return Results.Ok();
        }
        catch (PaymentWebhookVerificationException exception)
        {
            return ProjectEndpointResults.Problem(401, "Webhook no autenticado", null,
                exception.Code);
        }
    }

    private static async Task<IResult> AdminListAsync(ClaimsPrincipal principal,
        BillingService service, CancellationToken cancellationToken,
        string? q = null, string? status = null, int page = 1, int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!TryStatus(status, out var parsed) || page is < 1 or > 10_000 || pageSize is < 1 or > 50)
            return Results.ValidationProblem(new Dictionary<string, string[]>
            { ["filters"] = ["Estado o paginación no permitidos."] });
        var result = await service.ListAdminAsync(userId, q, parsed, page, pageSize,
            cancellationToken);
        return Results.Ok(new AdminSubscriptionPageResponse(result.Items.Select(Map).ToArray(),
            result.TotalCount, result.PageNumber, result.PageSize));
    }

    private static async Task<IResult> AdminDashboardAsync(ClaimsPrincipal principal,
        BillingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var value = await service.GetAdminDashboardAsync(userId, cancellationToken);
        return Results.Ok(new AdminBillingDashboardResponse(value.ActiveOrganizations,
            value.ActivePaidSubscriptions, value.PastDueSubscriptions, value.PendingCheckouts,
            value.FailedWebhookEvents, value.MonthlyRecurringRevenueClp, value.GeneratedAtUtc));
    }

    private static IResult Failure(BillingMutation result) => result.Outcome switch
    {
        BillingMutationOutcome.ValidationFailed => ProjectEndpointResults.Validation(422,
            "Solicitud inválida", "billing-validation", result.Errors),
        BillingMutationOutcome.NotFound => NotFound(),
        BillingMutationOutcome.Forbidden => ProjectEndpointResults.Problem(403,
            "Se requiere administración de la organización", null, "billing-forbidden"),
        BillingMutationOutcome.IdempotencyConflict => ProjectEndpointResults.Problem(409,
            "Conflicto de idempotencia", null, "idempotency-conflict"),
        BillingMutationOutcome.CheckoutAlreadyOpen => ProjectEndpointResults.Problem(409,
            "Ya existe un checkout pendiente", null, "checkout-already-open"),
        BillingMutationOutcome.InvalidTransition => ProjectEndpointResults.Problem(409,
            "Transición no permitida", null, "subscription-invalid-transition"),
        BillingMutationOutcome.PreconditionFailed => ProjectEndpointResults.Problem(412,
            "La suscripción cambió", "Recarga e intenta nuevamente.", "etag-conflict"),
        BillingMutationOutcome.GatewayDisabled => ProjectEndpointResults.Problem(503,
            "Billing sandbox deshabilitado", "El catálogo sigue disponible, pero no se pueden iniciar cobros.",
            "billing-disabled"),
        BillingMutationOutcome.GatewayUnavailable => ProjectEndpointResults.Problem(503,
            "Proveedor sandbox no disponible", "El checkout puede reconciliarse; reutiliza la misma clave.",
            "payment-provider-unavailable"),
        _ => ProjectEndpointResults.Problem(500, "No fue posible completar la operación", null,
            "billing-failed")
    };

    private static SubscriptionPlanResponse Map(SubscriptionPlan value) => new(value.Id,
        value.Code, value.Name, value.Description, value.IsPurchasable,
        value.Prices.Select(price => new SubscriptionPlanPriceResponse(price.Id,
            Interval(price.Interval), price.Currency, price.Amount, price.IsPurchasable,
            price.Provider)).ToArray(), value.Features.Select(Map).ToArray());
    private static SubscriptionFeatureResponse Map(SubscriptionFeature value) => new(
        value.Code, value.Name, value.IsEnabled, value.LimitValue, value.Unit, value.UsageValue);
    private static CurrentSubscriptionResponse Map(CurrentSubscription value) => new(
        value.OrganizationPublicId, value.PlanCode, value.PlanName,
        value.Status?.ToString().ToLowerInvariant() ?? "free",
        value.BillingInterval.HasValue ? Interval(value.BillingInterval.Value) : null,
        value.Currency, value.Amount, value.CurrentPeriodStartUtc, value.CurrentPeriodEndUtc,
        value.CancelAtPeriodEnd, value.GraceUntilUtc, value.IsFreeFallback,
        value.Features.Select(Map).ToArray(), value.ETag);
    private static SubscriptionCheckoutResponse Map(SubscriptionCheckout value, bool replayed) => new(
        value.PublicId, value.OrganizationPublicId, value.PlanPriceId, value.PlanName,
        Interval(value.Interval), value.Currency, value.Amount,
        value.Status.ToString().ToLowerInvariant(), value.Provider,
        value.CheckoutUri?.AbsoluteUri, value.ExpiresAtUtc, value.CreatedAtUtc,
        value.UpdatedAtUtc, replayed);
    private static SubscriptionUsageResponse Map(SubscriptionUsage value) => new(
        value.FeatureCode, value.FeatureName, value.IsEnabled, value.LimitValue,
        value.UsageValue, value.Unit, value.PeriodStartUtc, value.PeriodEndUtc);
    private static AdminSubscriptionSummaryResponse Map(AdminSubscriptionSummary value) => new(
        value.OrganizationPublicId, value.OrganizationName, value.PlanCode, value.PlanName,
        value.Status?.ToString().ToLowerInvariant() ?? "free", value.CurrentPeriodEndUtc,
        value.CancelAtPeriodEnd, value.Provider, value.ProviderSubscriptionReference,
        value.UpdatedAtUtc);
    private static string Interval(BillingInterval value) => value == BillingInterval.Annual ? "annual" : "monthly";
    private static bool TryStatus(string? value, out SubscriptionStatus? result)
    {
        result = null;
        if (string.IsNullOrWhiteSpace(value)) return true;
        if (!Enum.TryParse<SubscriptionStatus>(value, true, out var parsed) || !Enum.IsDefined(parsed))
            return false;
        result = parsed; return true;
    }
    private static IResult NotFound() => ProjectEndpointResults.Problem(404,
        "Recurso no encontrado", null, "not-found");
}
