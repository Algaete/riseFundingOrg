using System.Security.Claims;
using FundingPlatform.Application.Administration;
using FundingPlatform.Contracts.Administration;

namespace FundingPlatform.Api.Endpoints;

public static class AdminOperationsEndpoints
{
    private static readonly HashSet<string> ErrorCategories =
        new(["import", "extraction", "semantic", "explanation", "payment"],
            StringComparer.Ordinal);

    public static IEndpointRouteBuilder MapAdminOperationsEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin")
            .WithTags("Admin Operations")
            .RequireAuthorization("admin-mfa")
            .RequireRateLimiting("organization-activity-read");

        group.MapGet("/organizations", ListOrganizationsAsync)
            .Produces<AdminOrganizationPageResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/organizations/{organizationId:guid}", GetOrganizationAsync)
            .Produces<AdminOrganizationDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/operational-errors", ListOperationalErrorsAsync)
            .Produces<AdminOperationalErrorPageResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> ListOrganizationsAsync(
        ClaimsPrincipal principal,
        AdminOperationsService service,
        CancellationToken cancellationToken,
        string? q = null,
        int? profileStatus = null,
        bool? isActive = null,
        int page = 1,
        int pageSize = 25)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var errors = ValidatePage(q, page, pageSize);
        if (profileStatus.HasValue && profileStatus.Value is < 0 or > 2)
            errors["profileStatus"] = ["profileStatus debe estar entre 0 y 2."];
        if (errors.Count > 0) return Validation(errors, "Filtros de organizaciones inválidos");

        try
        {
            var value = await service.ListOrganizationsAsync(userId,
                new AdminOrganizationQuery(q,
                    profileStatus.HasValue ? checked((byte)profileStatus.Value) : null,
                    isActive, page, pageSize),
                cancellationToken);
            return Results.Ok(new AdminOrganizationPageResponse(
                value.Items.Select(Map).ToArray(), value.TotalCount, value.Page, value.PageSize));
        }
        catch (AdminOperationsDataException exception)
        {
            return Failure(exception);
        }
    }

    private static async Task<IResult> GetOrganizationAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        AdminOperationsService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (organizationId == Guid.Empty)
            return ProjectEndpointResults.Problem(404, "Organización no encontrada", null,
                "organization-not-found");
        try
        {
            var value = await service.GetOrganizationAsync(userId, organizationId,
                cancellationToken);
            return value is null
                ? ProjectEndpointResults.Problem(404, "Organización no encontrada", null,
                    "organization-not-found")
                : Results.Ok(Map(value));
        }
        catch (AdminOperationsDataException exception)
        {
            return Failure(exception);
        }
    }

    private static async Task<IResult> ListOperationalErrorsAsync(
        ClaimsPrincipal principal,
        AdminOperationsService service,
        CancellationToken cancellationToken,
        string? q = null,
        string? category = null,
        bool? retryable = null,
        int page = 1,
        int pageSize = 25)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var normalizedCategory = string.IsNullOrWhiteSpace(category)
            ? null
            : category.Trim().ToLowerInvariant();
        var errors = ValidatePage(q, page, pageSize);
        if (normalizedCategory is not null && !ErrorCategories.Contains(normalizedCategory))
            errors["category"] = ["category no es válida."];
        if (errors.Count > 0) return Validation(errors, "Filtros de errores inválidos");

        try
        {
            var value = await service.ListOperationalErrorsAsync(userId,
                new AdminOperationalErrorQuery(q, normalizedCategory, retryable, page, pageSize),
                cancellationToken);
            return Results.Ok(new AdminOperationalErrorPageResponse(
                value.Items.Select(Map).ToArray(), value.TotalCount, value.Page, value.PageSize));
        }
        catch (AdminOperationsDataException exception)
        {
            return Failure(exception);
        }
    }

    private static Dictionary<string, string[]> ValidatePage(string? query, int page, int pageSize)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (query?.Trim().Length > 200) errors["q"] = ["q no puede superar 200 caracteres."];
        if (page is < 1 or > 10000) errors["page"] = ["page debe estar entre 1 y 10000."];
        if (pageSize is < 1 or > 50) errors["pageSize"] = ["pageSize debe estar entre 1 y 50."];
        return errors;
    }

    private static IResult Validation(Dictionary<string, string[]> errors, string title) =>
        Results.ValidationProblem(errors,
            statusCode: StatusCodes.Status422UnprocessableEntity, title: title);

    private static IResult Failure(AdminOperationsDataException exception) =>
        exception.DatabaseErrorNumber is 51601 or 51602
            ? ProjectEndpointResults.Problem(403, "Acceso denegado", null,
                "admin-mfa-required")
            : ProjectEndpointResults.Problem(503, "Administración temporalmente no disponible",
                "Intenta nuevamente en unos minutos.", "admin-operations-unavailable");

    private static AdminOrganizationSummaryResponse Map(AdminOrganizationSummary value) => new(
        value.PublicId, value.Name, value.CountryCode, value.CountryName,
        value.OrganizationTypeName, value.ProfileStatus, value.ProfileCompleteness,
        value.IsActive, value.MemberCount, value.ProjectCount, value.PlanCode, value.PlanName,
        value.SubscriptionStatus, value.CreatedAtUtc, value.UpdatedAtUtc);

    private static AdminOrganizationDetailResponse Map(AdminOrganizationDetail value) => new(
        value.PublicId, value.Name, value.LegalName, value.CountryCode, value.CountryName,
        value.OrganizationTypeName, value.LegalEntityTypeName, value.OrganizationSizeName,
        value.EstablishedYear, value.WebsiteUrl, value.Description, value.ProfileStatus,
        value.ProfileCompleteness, value.ProfileVersion, value.IsActive, value.MemberCount,
        value.AdminMemberCount, value.ProjectCount, value.PublishedProjectCount,
        value.PlanCode, value.PlanName, value.SubscriptionStatus, value.CurrentPeriodEndUtc,
        value.CreatedAtUtc, value.UpdatedAtUtc);

    private static AdminOperationalErrorResponse Map(AdminOperationalErrorItem value) => new(
        value.Id, value.Category, value.Severity, value.Code, value.Message, value.IsRetryable,
        value.OccurredAtUtc, value.RelatedResourcePublicId, value.SourceName);
}
