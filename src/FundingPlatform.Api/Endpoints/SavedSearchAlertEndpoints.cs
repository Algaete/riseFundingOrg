using System.Globalization;
using System.Security.Claims;
using FundingPlatform.Application.Alerts;
using FundingPlatform.Contracts.Alerts;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class SavedSearchAlertEndpoints
{
    private static readonly IReadOnlyDictionary<string, FundingOpportunitySearchSort> Sorts =
        new Dictionary<string, FundingOpportunitySearchSort>(StringComparer.OrdinalIgnoreCase)
        {
            ["relevance"] = FundingOpportunitySearchSort.Relevance,
            ["closing-soon"] = FundingOpportunitySearchSort.ClosingSoon,
            ["newest"] = FundingOpportunitySearchSort.Newest,
            ["amount-asc"] = FundingOpportunitySearchSort.AmountAscending,
            ["amount-desc"] = FundingOpportunitySearchSort.AmountDescending
        };

    public static IEndpointRouteBuilder MapSavedSearchAlertEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/organizations/{organizationId:guid}")
            .WithTags("Saved searches and alerts")
            .RequireAuthorization("full-session");
        group.MapGet("/saved-searches", ListAsync)
            .RequireRateLimiting("organization-funding-read")
            .Produces<SavedSearchListResponse>().ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPost("/saved-searches", CreateAsync)
            .RequireRateLimiting("organization-write")
            .Produces<SavedSearchDetailResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem().ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapGet("/saved-searches/{savedSearchId:guid}", GetAsync)
            .RequireRateLimiting("organization-funding-read")
            .Produces<SavedSearchDetailResponse>().ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPatch("/saved-searches/{savedSearchId:guid}", UpdateAsync)
            .RequireRateLimiting("organization-write")
            .Produces<SavedSearchDetailResponse>().ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapDelete("/saved-searches/{savedSearchId:guid}", DeleteAsync)
            .RequireRateLimiting("organization-write")
            .Produces(StatusCodes.Status204NoContent)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPut("/saved-searches/{savedSearchId:guid}/alert", PutAlertAsync)
            .RequireRateLimiting("organization-write")
            .Produces<AlertSubscriptionResponse>()
            .ProducesValidationProblem().ProducesProblem(StatusCodes.Status503ServiceUnavailable)
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapDelete("/saved-searches/{savedSearchId:guid}/alert", DeleteAlertAsync)
            .RequireRateLimiting("organization-write")
            .Produces(StatusCodes.Status204NoContent)
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapGet("/notification-logs", ListNotificationsAsync)
            .RequireRateLimiting("organization-funding-read")
            .Produces<NotificationLogListResponse>().ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound);

        endpoints.MapPost("/api/v1/alerts/unsubscribe", UnsubscribeAsync)
            .WithTags("Saved searches and alerts")
            .AllowAnonymous()
            .RequireRateLimiting("auth-token")
            .Produces(StatusCodes.Status204NoContent);
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        Guid organizationId, ClaimsPrincipal principal, HttpRequest request,
        SavedSearchAlertService service, CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        if (!Pagination(request, out var page, out var pageSize, out var errors))
            return Results.ValidationProblem(errors);
        var result = await service.ListAsync(userId, organizationId, page, pageSize, cancellationToken);
        return result is null ? NotFound() : Results.Ok(new SavedSearchListResponse(
            result.Items.Select(MapSummary).ToArray(), result.TotalCount,
            result.PageNumber, result.PageSize));
    }

    private static async Task<IResult> GetAsync(
        Guid organizationId, Guid savedSearchId, ClaimsPrincipal principal,
        HttpContext context, SavedSearchAlertService service,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        var result = await service.GetAsync(
            userId, organizationId, savedSearchId, cancellationToken);
        if (result is null) return NotFound();
        context.Response.Headers.ETag = result.ETag;
        return Results.Ok(MapDetail(result));
    }

    private static async Task<IResult> CreateAsync(
        Guid organizationId, SavedSearchWriteRequest request, ClaimsPrincipal principal,
        HttpContext context, SavedSearchAlertService service,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        if (!TryFilters(request, out var filters, out var errors))
            return Results.ValidationProblem(errors);
        var result = await service.CreateAsync(new SavedSearchWriteCommand(
            userId, organizationId, null, request.Name, filters!,
            context.Request.Headers["Idempotency-Key"].ToString(), null), cancellationToken);
        return MutationResult(result, context, organizationId, StatusCodes.Status201Created);
    }

    private static async Task<IResult> UpdateAsync(
        Guid organizationId, Guid savedSearchId, SavedSearchWriteRequest request,
        ClaimsPrincipal principal, HttpContext context, SavedSearchAlertService service,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.ToString(), out var rowVersion))
            return Problem(StatusCodes.Status428PreconditionRequired,
                "Versión requerida", "Envía If-Match con el ETag vigente.", "if-match-required");
        if (!TryFilters(request, out var filters, out var errors))
            return Results.ValidationProblem(errors);
        var result = await service.UpdateAsync(new SavedSearchWriteCommand(
            userId, organizationId, savedSearchId, request.Name, filters!, null, rowVersion),
            cancellationToken);
        return MutationResult(result, context, organizationId, StatusCodes.Status200OK);
    }

    private static async Task<IResult> DeleteAsync(
        Guid organizationId, Guid savedSearchId, ClaimsPrincipal principal,
        HttpContext context, SavedSearchAlertService service,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.ToString(), out var rowVersion))
            return Problem(StatusCodes.Status428PreconditionRequired,
                "Versión requerida", "Envía If-Match con el ETag vigente.", "if-match-required");
        var result = await service.DeleteAsync(
            userId, organizationId, savedSearchId, rowVersion, cancellationToken);
        return result.Outcome switch
        {
            SavedSearchServiceOutcome.Deleted => Results.NoContent(),
            SavedSearchServiceOutcome.PreconditionFailed => PreconditionFailed(),
            SavedSearchServiceOutcome.NotFound => NotFound(),
            _ => Results.ValidationProblem(result.Errors ?? new Dictionary<string, string[]>())
        };
    }

    private static async Task<IResult> PutAlertAsync(
        Guid organizationId, Guid savedSearchId, AlertSubscriptionWriteRequest request,
        ClaimsPrincipal principal, HttpContext context, SavedSearchAlertService service,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        var result = await service.PutAlertAsync(
            userId, organizationId, savedSearchId, request.PreferredHourLocal,
            request.TimeZoneId, cancellationToken);
        if (result.Outcome == SavedSearchServiceOutcome.AlertsDisabled)
            return Problem(StatusCodes.Status503ServiceUnavailable, "Alertas desactivadas",
                "El envío de alertas todavía no está habilitado en este ambiente.", "alerts-disabled");
        if (result.Outcome == SavedSearchServiceOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == SavedSearchServiceOutcome.NotFound || result.Alert is null)
            return NotFound();
        context.Response.Headers.ETag = result.Alert.ETag;
        return Results.Ok(MapAlert(result.Alert));
    }

    private static async Task<IResult> DeleteAlertAsync(
        Guid organizationId, Guid savedSearchId, ClaimsPrincipal principal,
        SavedSearchAlertService service, CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        var result = await service.DeleteAlertAsync(
            userId, organizationId, savedSearchId, cancellationToken);
        return result.Outcome == SavedSearchServiceOutcome.NotFound
            ? NotFound() : Results.NoContent();
    }

    private static async Task<IResult> ListNotificationsAsync(
        Guid organizationId, ClaimsPrincipal principal, HttpRequest request,
        SavedSearchAlertService service, CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return InvalidSession();
        if (!Pagination(request, out var page, out var pageSize, out var errors))
            return Results.ValidationProblem(errors);
        var result = await service.ListNotificationsAsync(
            userId, organizationId, page, pageSize, cancellationToken);
        return result is null ? NotFound() : Results.Ok(new NotificationLogListResponse(
            result.Items.Select(item => new NotificationLogListItemResponse(
                item.PublicId, item.AlertSubscriptionPublicId, item.SavedSearchPublicId,
                item.SavedSearchName, StatusCode(item.Status), item.ItemCount,
                item.WasTruncated, item.ScheduledForUtc, item.SentAtUtc,
                item.ErrorCode, item.CreatedAtUtc)).ToArray(), result.TotalCount,
            result.PageNumber, result.PageSize));
    }

    private static async Task<IResult> UnsubscribeAsync(
        UnsubscribeAlertRequest request, SavedSearchAlertService service,
        AlertUnsubscribeTokenService tokenService, CancellationToken cancellationToken)
    {
        _ = await service.UnsubscribeAsync(request.Token, tokenService, cancellationToken);
        return Results.NoContent();
    }

    private static IResult MutationResult(
        SavedSearchServiceResult result, HttpContext context,
        Guid organizationId, int successStatus)
    {
        if (result.Outcome == SavedSearchServiceOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == SavedSearchServiceOutcome.PreconditionFailed)
            return PreconditionFailed();
        if (result.Outcome == SavedSearchServiceOutcome.IdempotencyConflict)
            return Problem(StatusCodes.Status409Conflict, "Conflicto de idempotencia",
                "La misma clave ya fue usada con otro contenido.", "idempotency-conflict");
        if (result.Outcome == SavedSearchServiceOutcome.NotFound || result.SavedSearch is null)
            return NotFound();
        context.Response.Headers.ETag = result.SavedSearch.ETag;
        var response = MapDetail(result.SavedSearch);
        return successStatus == StatusCodes.Status201Created &&
               result.Outcome == SavedSearchServiceOutcome.Created
            ? Results.Created($"/api/v1/organizations/{organizationId:D}/saved-searches/{response.Id:D}", response)
            : Results.Ok(response);
    }

    private static bool TryFilters(SavedSearchWriteRequest request,
        out FundingOpportunitySearchFilters? filters,
        out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        var defaultSort = string.IsNullOrWhiteSpace(request.Query) ? "closing-soon" : "relevance";
        if (!Sorts.TryGetValue((request.Sort ?? defaultSort).Trim(), out var sort))
        {
            errors["sort"] = ["El orden solicitado no está permitido."];
            filters = null;
            return false;
        }
        filters = new FundingOpportunitySearchFilters(
            request.Query, request.Sponsor, request.MinimumAmount, request.MaximumAmount,
            request.Currency, request.ClosingFrom, request.ClosingTo, request.OnlyOpen,
            sort, 1, 20, request.CountryIds ?? [], request.RegionIds ?? [],
            request.CategoryIds ?? [], request.TagIds ?? [],
            request.BeneficiaryTypeIds ?? [], request.ProjectTypeIds ?? [],
            request.FundingTypeIds ?? [], request.OrganizationTypeIds ?? [],
            request.FunderIds ?? []);
        return true;
    }

    private static bool Pagination(HttpRequest request, out int page, out int pageSize,
        out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        page = ParseInt(request.Query["page"], 1, "page", errors);
        pageSize = ParseInt(request.Query["pageSize"], 20, "pageSize", errors);
        if (page is < 1 or > 10_000) errors["page"] = ["La página debe estar entre 1 y 10000."];
        if (pageSize is < 1 or > 50) errors["pageSize"] = ["El tamaño debe estar entre 1 y 50."];
        return errors.Count == 0;
    }

    private static int ParseInt(string? value, int fallback, string key,
        IDictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        if (int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed))
            return parsed;
        errors[key] = ["Debe ser un entero válido."];
        return fallback;
    }

    private static SavedSearchListItemResponse MapSummary(SavedSearchSummary value) => new(
        value.PublicId, value.Name, value.Query, value.OnlyOpen, SortCode(value.Sort),
        value.HasActiveAlert, value.CreatedAtUtc, value.UpdatedAtUtc, value.ETag);
    private static SavedSearchDetailResponse MapDetail(SavedSearchDetails value) => new(
        value.PublicId, value.Name, new SavedSearchWriteRequest(
            value.Name, value.Filters.Query, value.Filters.Sponsor,
            value.Filters.MinimumAmount, value.Filters.MaximumAmount, value.Filters.Currency,
            value.Filters.ClosingFrom, value.Filters.ClosingTo, value.Filters.OnlyOpen,
            SortCode(value.Filters.Sort), value.Filters.CountryIds, value.Filters.RegionIds,
            value.Filters.CategoryIds, value.Filters.TagIds,
            value.Filters.BeneficiaryTypeIds, value.Filters.ProjectTypeIds,
            value.Filters.FundingTypeIds, value.Filters.OrganizationTypeIds,
            value.Filters.FunderPublicIds),
        value.Alert is null ? null : MapAlert(value.Alert), value.CreatedAtUtc,
        value.UpdatedAtUtc, value.ETag);
    private static AlertSubscriptionResponse MapAlert(AlertSubscriptionDetails value) => new(
        value.PublicId, value.PreferredHourLocal, value.TimeZoneId, value.NextRunAtUtc,
        value.LastRunAtUtc, value.IsActive, value.DisabledReasonCode,
        value.CreatedAtUtc, value.UpdatedAtUtc, value.ETag);
    private static string SortCode(FundingOpportunitySearchSort value) => value switch
    {
        FundingOpportunitySearchSort.Relevance => "relevance",
        FundingOpportunitySearchSort.ClosingSoon => "closing-soon",
        FundingOpportunitySearchSort.Newest => "newest",
        FundingOpportunitySearchSort.AmountAscending => "amount-asc",
        FundingOpportunitySearchSort.AmountDescending => "amount-desc",
        _ => "closing-soon"
    };
    private static string StatusCode(NotificationDeliveryStatus value) => value switch
    {
        NotificationDeliveryStatus.Pending => "pending",
        NotificationDeliveryStatus.Processing => "processing",
        NotificationDeliveryStatus.Sent => "sent",
        NotificationDeliveryStatus.RetryScheduled => "retry-scheduled",
        NotificationDeliveryStatus.Unknown => "unknown",
        NotificationDeliveryStatus.PermanentFailed => "permanent-failed",
        NotificationDeliveryStatus.Skipped => "skipped",
        _ => "unknown"
    };
    private static bool TryUser(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);
    private static IResult InvalidSession() => Problem(StatusCodes.Status401Unauthorized,
        "Sesión inválida", "Inicia sesión nuevamente.", "invalid-session");
    private static IResult NotFound() => Problem(StatusCodes.Status404NotFound,
        "Contenido no encontrado", "No existe o no tienes acceso.", "saved-search-not-found");
    private static IResult PreconditionFailed() => Problem(StatusCodes.Status412PreconditionFailed,
        "Versión desactualizada", "Recarga la búsqueda guardada e inténtalo nuevamente.", "etag-conflict");
    private static IResult Problem(int status, string title, string detail, string code) =>
        Results.Problem(statusCode: status, title: title, detail: detail,
            type: $"https://fundingplatform.local/problems/{code}");
}
