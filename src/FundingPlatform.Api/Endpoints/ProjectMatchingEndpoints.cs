using System.Security.Claims;
using FundingPlatform.Application.Matching;
using FundingPlatform.Contracts.Matching;
using FundingPlatform.Core.Matching;

namespace FundingPlatform.Api.Endpoints;

public static class ProjectMatchingEndpoints
{
    public const string Disclaimer =
        "Resultado orientativo basado en datos disponibles; no confirma elegibilidad ni reemplaza la revisión de las bases del fondo.";

    public static IEndpointRouteBuilder MapProjectMatchingEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var project = endpoints
            .MapGroup(
                "/api/v1/organizations/{organizationId:guid}/projects/{projectId:guid}")
            .WithTags("Project matching")
            .RequireAuthorization("full-session");

        project.MapGet("/matching-runs", ListAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("ListProjectMatchingRuns")
            .WithSummary("Lists immutable deterministic matching runs for an authorized project.")
            .Produces<ProjectMatchingRunPageResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        project.MapPost("/matching-runs", CreateAsync)
            .RequireRateLimiting("matching-run-create")
            .WithName("CreateProjectMatchingRun")
            .WithSummary("Calculates and stores a bounded deterministic matching run.")
            .Produces<ProjectMatchingExecutionResponse>(StatusCodes.Status201Created)
            .Produces<ProjectMatchingExecutionResponse>(StatusCodes.Status200OK)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        project.MapGet("/matching-runs/{matchingRunId:guid}", GetAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("GetProjectMatchingRun")
            .WithSummary("Gets an immutable deterministic run and its explainable results.")
            .Produces<ProjectMatchingRunDetailsResponse>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        ProjectMatchingService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var result = await service.ListRunsAsync(
            userId,
            organizationId,
            projectId,
            new ProjectMatchingRunListFilters(page, pageSize),
            cancellationToken);
        return result.Outcome switch
        {
            ProjectMatchingOutcome.Success => Results.Ok(Map(result.Page!)),
            ProjectMatchingOutcome.ValidationFailed => Results.ValidationProblem(result.Errors!),
            _ => NotFound()
        };
    }

    private static async Task<IResult> GetAsync(
        Guid organizationId,
        Guid projectId,
        Guid matchingRunId,
        ClaimsPrincipal principal,
        ProjectMatchingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var result = await service.GetRunAsync(
            userId,
            organizationId,
            projectId,
            matchingRunId,
            cancellationToken);
        return result.Outcome == ProjectMatchingOutcome.Success
            ? Results.Ok(Map(result.Details!))
            : NotFound();
    }

    private static async Task<IResult> CreateAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectMatchingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
        {
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required",
                "Idempotency-Key requerida",
                "Envía una clave única para calcular compatibilidad de forma segura.");
        }

        var result = await service.CreateRunAsync(
            userId,
            organizationId,
            projectId,
            idempotencyKey,
            cancellationToken);
        if (result.Outcome != ProjectMatchingOutcome.Success)
        {
            return MapFailure(result);
        }

        var details = Map(result.Details!);
        var response = new ProjectMatchingExecutionResponse(details, result.WasReplay);
        if (result.WasReplay)
        {
            return Results.Ok(response);
        }

        return Results.Created(
            $"/api/v1/organizations/{organizationId:D}/projects/{projectId:D}/matching-runs/{details.Run.PublicId:D}",
            response);
    }

    private static IResult MapFailure(ProjectMatchingRunDetailsResult result) =>
        result.Outcome switch
        {
            ProjectMatchingOutcome.ValidationFailed or ProjectMatchingOutcome.NotReady =>
                ProjectEndpointResults.Validation(
                    StatusCodes.Status422UnprocessableEntity,
                    "No es posible calcular compatibilidad",
                    "project-matching-validation",
                    result.Errors),
            ProjectMatchingOutcome.NotFound => NotFound(),
            ProjectMatchingOutcome.IdempotencyConflict => ProjectEndpointResults.Problem(
                StatusCodes.Status409Conflict,
                "Conflicto de idempotencia",
                "La misma Idempotency-Key ya se utilizó para otra solicitud.",
                "idempotency-conflict"),
            ProjectMatchingOutcome.Unavailable => ProjectEndpointResults.Problem(
                StatusCodes.Status503ServiceUnavailable,
                "Compatibilidad temporalmente no disponible",
                "La configuración determinística no está disponible. Intenta más tarde.",
                "project-matching-unavailable"),
            _ => ProjectEndpointResults.Problem(
                StatusCodes.Status409Conflict,
                "No es posible calcular compatibilidad",
                "Los datos cambiaron durante la ejecución. Intenta nuevamente con una clave nueva.",
                "project-matching-conflict")
        };

    private static ProjectMatchingRunPageResponse Map(ProjectMatchingRunPage page) =>
        new(page.Items.Select(Map).ToArray(), page.TotalCount, page.PageNumber, page.PageSize);

    private static ProjectMatchingRunDetailsResponse Map(ProjectMatchingRunDetails details) =>
        new(Map(details.Run), details.Items.Select(Map).ToArray(), Disclaimer);

    private static ProjectMatchingRunSummaryResponse Map(ProjectMatchingRunSummary run) =>
        new(
            run.PublicId,
            new MatchingProjectResponse(
                run.Project.PublicId,
                run.Project.Slug,
                run.Project.Title),
            (byte)run.Status,
            run.EngineVersion,
            new MatchingProfileResponse(run.MatchingProfile.Name, run.MatchingProfile.Version),
            run.ProjectVersion,
            run.OrganizationProfileVersion,
            run.CandidateCount,
            run.CompatibleCount,
            run.IncompatibleCount,
            run.InsufficientDataCount,
            run.TotalCandidateCount,
            run.IsTruncated,
            run.IsCurrent,
            run.CatalogSnapshotAtUtc,
            run.CreatedAtUtc,
            run.CompletedAtUtc);

    private static ProjectMatchingResultResponse Map(ProjectMatchingResult result) =>
        new(
            new MatchingFundingOpportunityResponse(
                result.FundingOpportunity.PublicId,
                result.FundingOpportunity.Slug,
                result.FundingOpportunity.Title,
                result.FundingOpportunity.SponsorName,
                result.FundingOpportunity.CloseDate,
                result.FundingOpportunity.CloseAtUtc,
                result.FundingOpportunity.DeadlinePrecision,
                result.FundingOpportunity.ContentVersion),
            (byte)result.Classification,
            result.CompatibilityScore,
            result.EvidenceCoverage,
            (byte)result.HardGateStatus,
            result.IsCurrent,
            result.RuleResults.Select(Map).ToArray());

    private static ProjectMatchingRuleResultResponse Map(ProjectMatchingRuleResult result) =>
        new(
            result.Code,
            result.Name,
            result.IsHardGate,
            (byte)result.Outcome,
            (byte)result.DataState,
            result.RawScore,
            result.Weight,
            result.WeightedPoints,
            result.ReasonCode,
            result.ReasonParameters,
            result.Evidence is null
                ? null
                : new MatchingRuleEvidenceResponse(
                    result.Evidence.Source,
                    result.Evidence.FieldCode,
                    result.Evidence.ValueCodes),
            result.IsWarning);

    private static IResult NotFound() => ProjectEndpointResults.Problem(
        StatusCodes.Status404NotFound,
        "Ejecución de compatibilidad no encontrada",
        null,
        "project-matching-run-not-found");
}
