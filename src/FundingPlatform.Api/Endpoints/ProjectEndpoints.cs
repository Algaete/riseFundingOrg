using System.Security.Claims;
using FundingPlatform.Application.Projects;
using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Api.Endpoints;

public static class ProjectEndpoints
{
    public static IEndpointRouteBuilder MapProjectEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/organizations/{organizationId:guid}/projects")
            .WithTags("Projects")
            .RequireAuthorization("full-session");

        group.MapGet("/", ListAsync)
            .Produces<IReadOnlyList<ProjectSummaryResponse>>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPost("/", CreateAsync)
            .RequireRateLimiting("organization-write")
            .Produces<ProjectCreatedResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapGet("/{projectId:guid}", GetAsync)
            .Produces<ProjectResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPut("/{projectId:guid}", UpdateAsync)
            .RequireRateLimiting("organization-write")
            .Produces<ProjectResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapPost("/{projectId:guid}/publish", RequestPublicationAsync)
            .RequireRateLimiting("organization-write")
            .Produces<ProjectWorkflowResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapPost("/{projectId:guid}/archive", ArchiveAsync)
            .RequireRateLimiting("organization-write")
            .Produces<ProjectWorkflowResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);

        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        ProjectService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.ListAsync(userId, organizationId, cancellationToken);
        return result.OrganizationFound
            ? Results.Ok(result.Projects.Select(MapSummary).ToArray())
            : NotFound();
    }

    private static async Task<IResult> CreateAsync(
        Guid organizationId,
        ProjectWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        if (!TryMap(request, out var project, out var collectionError)) return collectionError!;
        var result = await service.CreateAsync(userId, organizationId, project!, cancellationToken);
        if (result.Outcome == ProjectWriteOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == ProjectWriteOutcome.NotFound) return NotFound();
        if (result.Project is null)
            return Problem(500, "No fue posible crear el proyecto", null, "project-create-failed");

        var response = new ProjectCreatedResponse(
            result.Project.PublicId, result.Project.ProjectVersion, FormatETag(result.Project.RowVersion));
        context.Response.Headers.ETag = response.ETag;
        return Results.Created(
            $"/api/v1/organizations/{organizationId:D}/projects/{response.PublicId:D}", response);
    }

    private static async Task<IResult> GetAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var project = await service.GetAsync(userId, organizationId, projectId, cancellationToken);
        if (project is null) return NotFound();
        var response = Map(project);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static async Task<IResult> UpdateAsync(
        Guid organizationId,
        Guid projectId,
        ProjectWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        if (!TryParseETag(context.Request.Headers.IfMatch, out var expectedRowVersion))
            return Problem(428, "Versión requerida", "Vuelve a cargar el proyecto e intenta nuevamente.", "if-match-required");
        if (!TryMap(request, out var data, out var collectionError)) return collectionError!;
        var result = await service.UpdateAsync(
            userId, organizationId, projectId, expectedRowVersion, data!, cancellationToken);
        if (result.Outcome == ProjectWriteOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == ProjectWriteOutcome.NotFound) return NotFound();
        if (result.Outcome == ProjectWriteOutcome.Conflict)
            return Problem(409, "El proyecto cambió",
                "Otra sesión guardó una versión más reciente. Recarga antes de continuar.",
                "project-concurrency-conflict");
        if (result.Outcome == ProjectWriteOutcome.InvalidState)
            return Problem(409, "El contenido está congelado",
                "Los proyectos pendientes o publicados no pueden editarse.",
                "project-content-frozen");

        var project = await service.GetAsync(userId, organizationId, projectId, cancellationToken);
        if (project is null) return NotFound();
        var response = Map(project);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static Task<IResult> RequestPublicationAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectWorkflowService service,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            organizationId,
            projectId,
            principal,
            context,
            service,
            static (workflowService, userId, tenantId, targetId, rowVersion, key, token) =>
                workflowService.RequestPublicationAsync(
                    userId, tenantId, targetId, rowVersion, key, token),
            cancellationToken);

    private static Task<IResult> ArchiveAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectWorkflowService service,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            organizationId,
            projectId,
            principal,
            context,
            service,
            static (workflowService, userId, tenantId, targetId, rowVersion, key, token) =>
                workflowService.ArchiveAsync(
                    userId, tenantId, targetId, rowVersion, key, token),
            cancellationToken);

    private static async Task<IResult> ExecuteWorkflowAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectWorkflowService service,
        Func<ProjectWorkflowService, Guid, Guid, Guid, byte[], string, CancellationToken,
            Task<ProjectWorkflowResult>> execute,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.ToString(), out var expectedRowVersion))
            return ProjectEndpointResults.PreconditionRequired("if-match-required", "Versión requerida",
                "Envía If-Match con el ETag vigente del proyecto.");

        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Clave de idempotencia requerida",
                "Envía Idempotency-Key para ejecutar esta mutación.");

        var result = await execute(
            service, userId, organizationId, projectId, expectedRowVersion,
            idempotencyKey, cancellationToken);
        return ProjectEndpointResults.MapWorkflow(result, context);
    }

    private static bool TryMap(
        ProjectWriteRequest request,
        out ProjectData? project,
        out IResult? error)
    {
        project = null;
        error = null;
        if (request.CountryIds is null || request.RegionIds is null || request.CategoryIds is null ||
            request.BeneficiaryTypeIds is null || request.ProjectTypeIds is null)
        {
            error = Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["collections"] = ["Todas las colecciones del proyecto deben enviarse."]
            });
            return false;
        }

        project = new ProjectData(
            request.Title, request.Summary, request.Description, (ProjectStatus)request.Status,
            request.StartDate, request.EndDate, request.BudgetTotal, request.ConfirmedFunding,
            request.Currency, request.CountryIds, request.RegionIds, request.CategoryIds,
            request.BeneficiaryTypeIds, request.ProjectTypeIds);
        return true;
    }

    private static ProjectSummaryResponse MapSummary(ProjectSummary project) => new(
        project.PublicId, project.Slug, project.Title, project.Summary, (byte)project.Status,
        (byte)project.PublicationStatus, project.StartDate, project.EndDate,
        project.BudgetTotal, project.ConfirmedFunding, project.Currency, project.FundingGap,
        project.ProjectVersion, project.UpdatedAtUtc);

    private static ProjectResponse Map(ProjectDetails project) => new(
        project.PublicId, project.Slug, project.Title, project.Summary, project.Description,
        (byte)project.Status, (byte)project.PublicationStatus, project.StartDate, project.EndDate,
        project.BudgetTotal, project.ConfirmedFunding, project.Currency, project.FundingGap,
        project.ProjectVersion, project.UpdatedAtUtc, FormatETag(project.RowVersion),
        project.CountryIds, project.RegionIds, project.CategoryIds,
        project.BeneficiaryTypeIds, project.ProjectTypeIds, project.SubmittedAtUtc,
        project.ReviewedAtUtc, project.RejectionReason, project.PublishedAtUtc);

    private static string FormatETag(byte[] rowVersion) => $"\"{Convert.ToHexString(rowVersion)}\"";

    private static bool TryParseETag(string? value, out byte[] rowVersion)
    {
        rowVersion = [];
        var normalized = value?.Trim().Trim('"');
        if (normalized?.Length != 16) return false;
        try { rowVersion = Convert.FromHexString(normalized); return rowVersion.Length == 8; }
        catch (FormatException) { return false; }
    }

    private static bool TryGetUserId(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);

    private static IResult NotFound() => Problem(404, "Proyecto no encontrado",
        "No existe o no tienes una membresía activa en la organización.", "project-not-found");
    private static IResult InvalidSession() => Problem(401, "Sesión inválida", "Inicia sesión nuevamente.", "invalid-session");
    private static IResult Problem(int status, string title, string? detail, string code) => Results.Problem(
        statusCode: status, title: title, detail: detail,
        type: $"https://fundingplatform.local/problems/{code}");
}
