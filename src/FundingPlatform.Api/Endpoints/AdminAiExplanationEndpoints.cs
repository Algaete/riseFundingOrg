using System.Security.Claims;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Contracts.Semantics;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Api.Endpoints;

public static class AdminAiExplanationEndpoints
{
    public const string Disclaimer =
        "Explicación automática interna en modo sombra. Usa señales estructuradas y semánticas acotadas; no modifica 9A, no recomienda fondos y no confirma elegibilidad.";

    public static IEndpointRouteBuilder MapAdminAiExplanationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/semantic-explanation-runs")
            .WithTags("Admin Semantic Explanations")
            .RequireAuthorization("admin-mfa");
        group.MapPost("", CreateAsync)
            .RequireRateLimiting("semantic-evaluation-create")
            .Produces<AiExplanationRunAcceptedResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/{runId:guid}", GetAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<AiExplanationRunDetailResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> CreateAsync(
        CreateAiExplanationRunRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        AiExplanationAdministrationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required",
                "Idempotency-Key es obligatorio",
                "Envía una clave estable para reintentar sin duplicar la explicación.");
        var result = await service.CreateAsync(
            userId,
            request.SourceSemanticEvaluationRunPublicId,
            request.ExplanationConfigurationVersion,
            idempotencyKey,
            cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value is null)
            return MapFailure(result);
        var run = Map(result.Value);
        var statusUrl = $"/api/v1/admin/semantic-explanation-runs/{run.PublicId:D}";
        return Results.Accepted(statusUrl,
            new AiExplanationRunAcceptedResponse(
                run,
                result.Code == "replayed",
                statusUrl));
    }

    private static async Task<IResult> GetAsync(
        Guid runId,
        ClaimsPrincipal principal,
        AiExplanationAdministrationService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 25)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var result = await service.GetAsync(userId, runId, page, pageSize, cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value is null)
            return MapFailure(result);
        return Results.Ok(new AiExplanationRunDetailResponse(
            Map(result.Value.Run),
            result.Value.ResultCount,
            result.Value.Page,
            result.Value.PageSize,
            result.Value.Results.Select(item => new AiExplanationResultResponse(
                item.CaseOrdinal,
                (byte)item.Assessment,
                item.Summary,
                item.PrimaryReasonCode,
                item.CitedRuleCodes,
                item.InputTokens,
                item.OutputTokens,
                item.EstimatedCostUsd,
                item.LatencyMilliseconds,
                item.CreatedAtUtc)).ToArray(),
            Disclaimer));
    }

    private static IResult MapFailure<T>(SemanticEvaluationResult<T> result) =>
        result.Outcome switch
        {
            SemanticEvaluationOutcome.Invalid => ProjectEndpointResults.Validation(
                StatusCodes.Status422UnprocessableEntity,
                "Solicitud de explicación estructurada inválida",
                result.Code == "budget-insufficient"
                    ? "structured-explanation-budget-insufficient"
                    : "structured-explanation-validation",
                result.Errors),
            SemanticEvaluationOutcome.Forbidden => ProjectEndpointResults.Problem(
                StatusCodes.Status403Forbidden,
                "Acceso denegado",
                null,
                "admin-role-required"),
            SemanticEvaluationOutcome.NotFound => ProjectEndpointResults.Problem(
                StatusCodes.Status404NotFound,
                "Explicación no encontrada",
                null,
                "structured-explanation-not-found"),
            SemanticEvaluationOutcome.Conflict => ProjectEndpointResults.Problem(
                StatusCodes.Status409Conflict,
                "No fue posible crear la explicación",
                result.Code == "idempotency-conflict"
                    ? "La misma Idempotency-Key ya se utilizó para otra solicitud."
                    : "Ya existe una explicación estructurada activa.",
                result.Code == "idempotency-conflict"
                    ? "idempotency-conflict"
                    : "structured-explanation-conflict"),
            _ => ProjectEndpointResults.Problem(
                StatusCodes.Status503ServiceUnavailable,
                "Explicaciones estructuradas no disponibles",
                "La capacidad permanece deshabilitada o temporalmente no disponible.",
                "structured-explanation-unavailable")
        };

    private static AiExplanationRunSummaryResponse Map(AiExplanationRunSummary run) => new(
        run.PublicId,
        run.SourceSemanticEvaluationRunPublicId,
        (byte)run.Status,
        run.ExplanationConfigurationVersion,
        run.ProviderCode,
        run.ModelCode,
        run.ItemCount,
        run.CompletedCount,
        run.FailedCount,
        run.TotalEstimatedCostUsd,
        run.CreatedAtUtc,
        run.CompletedAtUtc);
}
