using System.Security.Claims;
using FundingPlatform.Application.Projects;
using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Api.Endpoints;

public static class AdminProjectEndpoints
{
    public static IEndpointRouteBuilder MapAdminProjectEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/projects")
            .WithTags("Admin Projects")
            .RequireAuthorization("admin-mfa");

        group.MapGet("/review-queue", ListReviewQueueAsync)
            .Produces<ProjectReviewQueueResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        group.MapGet("/{projectId:guid}", GetReviewDetailsAsync)
            .Produces<ProjectAdminReviewDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/{projectId:guid}/reviews", ReviewAsync)
            .RequireRateLimiting("organization-write")
            .Produces<ProjectWorkflowResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);

        return endpoints;
    }

    private static async Task<IResult> GetReviewDetailsAsync(
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectWorkflowService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();

        var result = await service.GetReviewDetailsAsync(userId, projectId, cancellationToken);
        if (result.Outcome == ProjectWorkflowOutcome.Forbidden)
            return ProjectEndpointResults.Problem(403, "Acceso denegado", null, "admin-role-required");
        if (result.Outcome == ProjectWorkflowOutcome.NotFound || result.Project is null)
            return ProjectEndpointResults.Problem(404, "Proyecto no encontrado", null,
                "review-project-not-found");

        context.Response.Headers.ETag = ProjectEndpointResults.FormatETag(result.Project.RowVersion);
        return Results.Ok(Map(result.Project));
    }

    private static async Task<IResult> ListReviewQueueAsync(
        ClaimsPrincipal principal,
        ProjectWorkflowService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 50)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (page < 1 || pageSize is < 1 or > 100)
        {
            return ProjectEndpointResults.Validation(
                422,
                "Paginación inválida",
                "invalid-pagination",
                new Dictionary<string, string[]>
                {
                    [page < 1 ? "page" : "pageSize"] =
                        [page < 1 ? "page debe ser al menos 1." : "pageSize debe estar entre 1 y 100."]
                });
        }

        var result = await service.ListReviewQueueAsync(userId, page, pageSize, cancellationToken);
        if (result.Outcome == ProjectWorkflowOutcome.Forbidden)
            return ProjectEndpointResults.Problem(403, "Acceso denegado", null, "admin-role-required");
        if (result.Page is null)
            return ProjectEndpointResults.Problem(500, "No fue posible cargar la cola", null,
                "review-queue-failed");

        return Results.Ok(new ProjectReviewQueueResponse(
            result.Page.Items.Select(Map).ToArray(),
            result.Page.TotalCount,
            result.Page.PageNumber,
            result.Page.PageSize));
    }

    private static async Task<IResult> ReviewAsync(
        Guid projectId,
        ProjectReviewRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectWorkflowService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!TryParseDecision(request.Decision, out var decision))
        {
            return ProjectEndpointResults.Validation(
                422,
                "Decisión inválida",
                "invalid-review-decision",
                new Dictionary<string, string[]>
                {
                    ["decision"] = ["decision debe ser approve o reject."]
                });
        }

        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.ToString(), out var expectedRowVersion))
            return ProjectEndpointResults.PreconditionRequired("if-match-required", "Versión requerida",
                "Envía If-Match con el ETag vigente del proyecto.");

        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Clave de idempotencia requerida",
                "Envía Idempotency-Key para ejecutar esta mutación.");

        var result = await service.ReviewAsync(
            userId,
            projectId,
            decision,
            request.Reason,
            expectedRowVersion,
            idempotencyKey,
            cancellationToken);
        return ProjectEndpointResults.MapWorkflow(result, context);
    }

    private static ProjectReviewQueueItemResponse Map(ProjectReviewQueueItem item) => new(
        item.PublicId,
        item.Slug,
        item.Title,
        item.Summary,
        (byte)item.Status,
        (byte)item.PublicationStatus,
        item.OrganizationPublicId,
        item.OrganizationName,
        item.Completeness,
        item.SubmittedAtUtc,
        item.UpdatedAtUtc,
        ProjectEndpointResults.FormatETag(item.RowVersion));

    private static ProjectAdminReviewDetailResponse Map(ProjectReviewDetails project) => new(
        project.PublicId,
        project.Slug,
        project.Title,
        project.Summary,
        project.Description,
        (byte)project.Status,
        (byte)project.PublicationStatus,
        project.StartDate,
        project.EndDate,
        project.BudgetTotal,
        project.ConfirmedFunding,
        project.Currency,
        project.FundingGap,
        project.ProjectVersion,
        project.Completeness,
        project.SubmittedAtUtc,
        project.UpdatedAtUtc,
        ProjectEndpointResults.FormatETag(project.RowVersion),
        new PublicProjectOrganizationResponse(
            project.Organization.PublicId,
            project.Organization.Name,
            project.Organization.WebsiteUrl),
        project.Countries.Select(Map).ToArray(),
        project.Regions.Select(Map).ToArray(),
        project.Categories.Select(Map).ToArray(),
        project.BeneficiaryTypes.Select(Map).ToArray(),
        project.ProjectTypes.Select(Map).ToArray());

    private static PublicProjectTaxonomyResponse Map(PublicProjectTaxonomyItem item) =>
        new(item.Id, item.Code, item.Name);

    private static PublicProjectRegionResponse Map(PublicProjectRegion item) =>
        new(item.Id, item.CountryId, item.Code, item.Name);

    private static bool TryParseDecision(string? value, out ProjectReviewDecision decision)
    {
        if (string.Equals(value?.Trim(), "approve", StringComparison.OrdinalIgnoreCase))
        {
            decision = ProjectReviewDecision.Approve;
            return true;
        }

        if (string.Equals(value?.Trim(), "reject", StringComparison.OrdinalIgnoreCase))
        {
            decision = ProjectReviewDecision.Reject;
            return true;
        }

        decision = default;
        return false;
    }
}
