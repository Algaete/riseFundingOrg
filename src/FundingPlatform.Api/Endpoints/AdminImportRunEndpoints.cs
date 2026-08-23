using System.Security.Claims;
using FundingPlatform.Application.Imports;
using FundingPlatform.Contracts.Imports;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.Api.Endpoints;

public static class AdminImportRunEndpoints
{
    public static IEndpointRouteBuilder MapAdminImportRunEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin")
            .WithTags("Admin Imports")
            .RequireAuthorization("admin-mfa");

        group.MapPost(
                "/funding-sources/{fundingSourceId:int}/import-runs",
                CreateAsync)
            .RequireRateLimiting("import-run-create")
            .Produces<ImportRunAcceptedResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        group.MapGet("/import-runs", ListAsync)
            .Produces<ImportRunListResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        group.MapGet("/import-runs/{runId:guid}", GetAsync)
            .Produces<ImportRunDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> CreateAsync(
        int fundingSourceId,
        CreateImportRunRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        IImportRunService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        if (!context.Request.Headers.TryGetValue("Idempotency-Key", out var header) ||
            string.IsNullOrWhiteSpace(header.ToString()))
        {
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required",
                "Idempotency-Key es obligatorio",
                "Envía una clave estable para poder reintentar sin duplicar la ejecución.");
        }

        var result = await service.CreateManualAsync(
            userId,
            fundingSourceId,
            request.Keyword,
            request.MaximumResults,
            header.ToString(),
            context.TraceIdentifier,
            cancellationToken);

        if (result.Outcome != ImportRunOutcome.Success || result.Value is null)
        {
            return MapFailure(result);
        }

        var statusUrl = $"/api/v1/admin/import-runs/{result.Value.RunId:D}";
        return Results.Accepted(
            statusUrl,
            new ImportRunAcceptedResponse(
                result.Value.RunId,
                result.Value.FundingSourceId,
                result.Value.SourceName,
                (byte)result.Value.Status,
                result.Value.CreatedAtUtc,
                result.Value.WasReplay,
                statusUrl));
    }

    private static async Task<IResult> ListAsync(
        ClaimsPrincipal principal,
        IImportRunService service,
        CancellationToken cancellationToken,
        int? sourceId = null,
        byte? status = null,
        int page = 1,
        int pageSize = 25)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        ImportRunStatus? parsedStatus = null;
        if (status.HasValue)
        {
            if (!Enum.IsDefined(typeof(ImportRunStatus), status.Value))
            {
                return ProjectEndpointResults.Validation(
                    422,
                    "Filtros inválidos",
                    "invalid-import-run-query",
                    new Dictionary<string, string[]>
                    {
                        ["status"] = ["El estado de la ejecución no es válido."]
                    });
            }

            parsedStatus = (ImportRunStatus)status.Value;
        }

        var result = await service.ListAsync(
            userId, sourceId, parsedStatus, page, pageSize, cancellationToken);
        if (result.Outcome != ImportRunOutcome.Success || result.Value is null)
        {
            return MapFailure(result);
        }

        return Results.Ok(new ImportRunListResponse(
            result.Value.Items.Select(Map).ToArray(),
            result.Value.TotalCount,
            result.Value.Page,
            result.Value.PageSize));
    }

    private static async Task<IResult> GetAsync(
        Guid runId,
        ClaimsPrincipal principal,
        IImportRunService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var result = await service.GetAsync(userId, runId, cancellationToken);
        if (result.Outcome != ImportRunOutcome.Success || result.Value is null)
        {
            return MapFailure(result);
        }

        var value = result.Value;
        return Results.Ok(new ImportRunDetailResponse(
            value.RunId,
            value.FundingSourceId,
            value.SourceName,
            value.ProviderCode,
            (byte)value.TriggerType,
            (byte)value.Status,
            value.Keyword,
            value.MaximumResults,
            value.RetrievedCount,
            value.CreatedCount,
            value.UpdatedCount,
            value.UnchangedCount,
            value.StagedForReviewCount,
            value.FailedCount,
            value.AttemptCount,
            value.CreatedAtUtc,
            value.StartedAtUtc,
            value.CompletedAtUtc,
            value.LastErrorCode,
            value.Items.Select(Map).ToArray(),
            value.Errors.Select(Map).ToArray()));
    }

    private static IResult MapFailure<T>(ImportRunResult<T> result) => result.Outcome switch
    {
        ImportRunOutcome.Invalid => ProjectEndpointResults.Validation(
            422,
            "Solicitud de importación inválida",
            result.Code is "source-disabled" or "compliance-required" or
                "provider-not-allowlisted" or "provider-not-supported"
                ? result.Code
                : "invalid-import-run-request",
            result.Errors),
        ImportRunOutcome.NotFound => ProjectEndpointResults.Problem(
            404,
            "Ejecución o fuente no encontrada",
            null,
            "import-run-not-found"),
        ImportRunOutcome.Forbidden => ProjectEndpointResults.Problem(
            403,
            "Acceso denegado",
            null,
            "admin-role-required"),
        ImportRunOutcome.Conflict => ProjectEndpointResults.Problem(
            409,
            "No fue posible crear la ejecución",
            result.Code == "idempotency-conflict"
                ? "La misma Idempotency-Key ya se utilizó con otra solicitud."
                : "La fuente no permite esta operación en su estado actual.",
            result.Code == "idempotency-conflict"
                ? "idempotency-conflict"
                : "import-run-conflict"),
        ImportRunOutcome.Unavailable => ProjectEndpointResults.Problem(
            503,
            "Importaciones temporalmente no disponibles",
            "Intenta nuevamente en unos minutos.",
            "import-service-unavailable"),
        _ => ProjectEndpointResults.Problem(
            500,
            "No fue posible completar la operación",
            null,
            "import-run-failed")
    };

    private static ImportRunSummaryResponse Map(ImportRunSummary value) => new(
        value.RunId,
        value.FundingSourceId,
        value.SourceName,
        value.ProviderCode,
        (byte)value.TriggerType,
        (byte)value.Status,
        value.Keyword,
        value.MaximumResults,
        value.RetrievedCount,
        value.CreatedCount,
        value.UpdatedCount,
        value.UnchangedCount,
        value.StagedForReviewCount,
        value.FailedCount,
        value.CreatedAtUtc,
        value.StartedAtUtc,
        value.CompletedAtUtc,
        value.LastErrorCode);

    private static ImportRunItemResponse Map(ImportRunItem value) => new(
        value.ItemId,
        value.RawObservationId,
        value.OpportunityId,
        value.ExternalId,
        (byte)value.Status,
        value.OutcomeCode,
        value.CreatedAtUtc,
        value.CompletedAtUtc,
        value.DuplicateCandidateId,
        value.DuplicateCandidateStatus,
        value.DuplicateMatchKind,
        value.DuplicateConfidence,
        value.SuggestedCanonicalOpportunityId,
        value.SuggestedCanonicalTitle,
        value.DuplicateDecisionId,
        value.DuplicateDecision,
        value.DuplicateCandidateRowVersion is { Length: 8 }
            ? ProjectEndpointResults.FormatETag(value.DuplicateCandidateRowVersion)
            : null);

    private static ImportRunErrorResponse Map(ImportRunError value) => new(
        value.ErrorId,
        value.ItemId,
        value.Stage,
        value.Code,
        value.Message,
        value.IsRetryable,
        value.OccurredAtUtc);
}
