using System.Security.Claims;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Contracts.Semantics;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Api.Endpoints;

public static class AdminSemanticEvaluationEndpoints
{
    public const string Disclaimer =
        "Evaluación interna en modo sombra; no modifica la compatibilidad determinística, no recomienda fondos y no confirma elegibilidad.";

    public static IEndpointRouteBuilder MapAdminSemanticEvaluationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/semantic-evaluation-runs")
            .WithTags("Admin Semantic Evaluation")
            .RequireAuthorization("admin-mfa");

        group.MapPost("", CreateAsync)
            .RequireRateLimiting("semantic-evaluation-create")
            .Produces<SemanticEvaluationRunAcceptedResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("", ListAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<SemanticEvaluationRunPageResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/{runId:guid}", GetAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<SemanticEvaluationRunDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/{runId:guid}/report", GetReportAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<SemanticEvaluationRunReportResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> CreateAsync(
        CreateSemanticEvaluationRunRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        SemanticEvaluationAdministrationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required",
                "Idempotency-Key es obligatorio",
                "Envía una clave estable para reintentar sin duplicar la evaluación.");

        var result = await service.CreateAsync(
            userId,
            request.EvalSetVersion,
            request.SemanticConfigurationVersion,
            idempotencyKey,
            cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value?.Run is null)
            return MapFailure(result);
        var run = Map(result.Value.Run);
        var statusUrl = $"/api/v1/admin/semantic-evaluation-runs/{run.PublicId:D}";
        return Results.Accepted(statusUrl,
            new SemanticEvaluationRunAcceptedResponse(
                run, result.Value.WasReplay, statusUrl));
    }

    private static async Task<IResult> ListAsync(
        ClaimsPrincipal principal,
        SemanticEvaluationAdministrationService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 25)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var result = await service.ListAsync(userId, page, pageSize, cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value is null)
            return MapFailure(result);
        return Results.Ok(new SemanticEvaluationRunPageResponse(
            result.Value.Items.Select(Map).ToArray(),
            result.Value.TotalCount,
            result.Value.Page,
            result.Value.PageSize));
    }

    private static async Task<IResult> GetAsync(
        Guid runId,
        ClaimsPrincipal principal,
        SemanticEvaluationAdministrationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var result = await service.GetAsync(userId, runId, cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value is null)
            return MapFailure(result);
        var detail = result.Value;
        return Results.Ok(new SemanticEvaluationRunDetailResponse(
            Map(detail.Run),
            detail.QueuedEmbeddingJobCount,
            detail.ProcessingEmbeddingJobCount,
            detail.SucceededEmbeddingJobCount,
            detail.RetryScheduledEmbeddingJobCount,
            detail.PermanentFailedEmbeddingJobCount,
            detail.SkippedStaleEmbeddingJobCount,
            detail.RejectedInputEmbeddingJobCount,
            Disclaimer));
    }

    private static async Task<IResult> GetReportAsync(
        Guid runId,
        ClaimsPrincipal principal,
        SemanticEvaluationAdministrationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var result = await service.GetReportAsync(userId, runId, cancellationToken);
        if (result.Outcome != SemanticEvaluationOutcome.Success || result.Value is null)
            return MapFailure(result);
        return Results.Ok(new SemanticEvaluationRunReportResponse(
            Map(result.Value.Run),
            result.Value.Splits.Select(split => new SemanticEvaluationSplitReportResponse(
                split.DatasetSplit,
                split.PairCount,
                split.EvaluatedCount,
                split.LabelledCount,
                split.RelevantLabelCount,
                split.CoveragePercentage,
                split.RecallAt10,
                split.NormalizedDiscountedCumulativeGainAt10,
                split.BaselineNormalizedDiscountedCumulativeGainAt10,
                split.NormalizedDiscountedCumulativeGainDelta,
                split.MeanReciprocalRankAt10,
                split.MeanRankDelta)).ToArray(),
            Disclaimer));
    }

    private static IResult MapFailure<T>(SemanticEvaluationResult<T> result) =>
        result.Outcome switch
        {
            SemanticEvaluationOutcome.Invalid => ProjectEndpointResults.Validation(
                StatusCodes.Status422UnprocessableEntity,
                "Solicitud de evaluación semántica inválida",
                result.Code == "eval-set-not-ready"
                    ? "semantic-eval-set-not-ready"
                    : result.Code == "configuration-not-approved"
                        ? "semantic-configuration-not-approved"
                        : result.Code == "budget-insufficient"
                            ? "semantic-budget-insufficient"
                        : "semantic-evaluation-validation",
                result.Errors),
            SemanticEvaluationOutcome.Forbidden => ProjectEndpointResults.Problem(
                StatusCodes.Status403Forbidden, "Acceso denegado", null, "admin-role-required"),
            SemanticEvaluationOutcome.NotFound => ProjectEndpointResults.Problem(
                StatusCodes.Status404NotFound,
                "Evaluación semántica no encontrada", null, "semantic-evaluation-not-found"),
            SemanticEvaluationOutcome.Conflict => ProjectEndpointResults.Problem(
                StatusCodes.Status409Conflict,
                "No fue posible crear la evaluación",
                result.Code == "idempotency-conflict"
                    ? "La misma Idempotency-Key ya se utilizó para otra solicitud."
                    : "Ya existe una evaluación activa para esta configuración.",
                result.Code == "idempotency-conflict"
                    ? "idempotency-conflict"
                    : "semantic-evaluation-conflict"),
            SemanticEvaluationOutcome.Unavailable => ProjectEndpointResults.Problem(
                StatusCodes.Status503ServiceUnavailable,
                "Evaluación semántica no disponible",
                "El procesamiento semántico permanece deshabilitado o temporalmente no disponible.",
                "semantic-evaluation-unavailable"),
            _ => ProjectEndpointResults.Problem(
                StatusCodes.Status500InternalServerError,
                "No fue posible completar la operación", null, "semantic-evaluation-failed")
        };

    private static SemanticEvaluationRunSummaryResponse Map(
        SemanticEvaluationRunSummary run) => new(
        run.PublicId,
        (byte)run.Status,
        run.EvaluationSetVersion,
        run.SemanticConfigurationVersion,
        run.ProviderCode,
        run.ModelCode,
        run.Dimensions,
        run.PurposeCode,
        run.NormalizationVersion,
        run.ProjectCount,
        run.OpportunityCount,
        run.PairCount,
        run.PrimaryCohortCount,
        run.EvaluatedCount,
        run.LabelledCount,
        new SemanticEvaluationMetricsResponse(
            run.Metrics.CoveragePercentage,
            run.Metrics.ProviderSuccessPercentage,
            run.Metrics.RecallAt10,
            run.Metrics.NormalizedDiscountedCumulativeGainAt10,
            run.Metrics.BaselineNormalizedDiscountedCumulativeGainAt10,
            run.Metrics.NormalizedDiscountedCumulativeGainDelta,
            run.Metrics.MeanReciprocalRankAt10,
            run.Metrics.MeanRankDelta,
            run.Metrics.TotalEstimatedCostUsd,
            run.Metrics.LatencyP95Milliseconds,
            run.Metrics.HardGatePromotionCount,
            run.Metrics.MeetsPromotionGate),
        run.CreatedAtUtc,
        run.StartedAtUtc,
        run.CompletedAtUtc,
        run.LastErrorCode);
}
