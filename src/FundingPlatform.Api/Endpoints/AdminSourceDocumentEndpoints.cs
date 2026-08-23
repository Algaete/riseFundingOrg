using System.Security.Claims;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Contracts.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Api.Endpoints;

public static class AdminSourceDocumentEndpoints
{
    public static IEndpointRouteBuilder MapAdminSourceDocumentEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var intents = endpoints.MapGroup("/api/v1/admin/source-document-upload-intents")
            .WithTags("Admin Source Document Uploads")
            .RequireAuthorization("admin-mfa");

        intents.MapPost("/", CreateUploadIntentAsync)
            .RequireRateLimiting("source-document-create")
            .Produces<SourceDocumentUploadIntentCreatedResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        intents.MapPost("/{intentId:guid}/complete", CompleteUploadIntentAsync)
            .RequireRateLimiting("source-document-mutation")
            .Produces<SourceDocumentOperationResponse>()
            .Produces<SourceDocumentOperationResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status410Gone)
            .ProducesProblem(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        intents.MapGet("/{intentId:guid}", GetUploadIntentAsync)
            .Produces<SourceDocumentUploadIntentResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);

        var documents = endpoints.MapGroup("/api/v1/admin/source-documents")
            .WithTags("Admin Source Documents")
            .RequireAuthorization("admin-mfa");
        documents.MapGet("/{sourceDocumentId:guid}", GetSourceDocumentAsync)
            .Produces<SourceDocumentResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        documents.MapPost("/{sourceDocumentId:guid}/scan/retry", RetryScanAsync)
            .RequireRateLimiting("source-document-mutation")
            .Produces<SourceDocumentOperationResponse>()
            .Produces<SourceDocumentOperationResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        documents.MapPost("/{sourceDocumentId:guid}/extractions", StartExtractionAsync)
            .RequireRateLimiting("source-document-mutation")
            .Produces<SourceDocumentExtractionStartedResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        documents.MapGet("/{sourceDocumentId:guid}/extractions/latest", GetLatestExtractionAsync)
            .Produces<SourceDocumentExtractionResultResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        documents.MapGet(
                "/{sourceDocumentId:guid}/extractions/latest/evidence",
                GetLatestExtractionEvidenceAsync)
            .Produces<SourceDocumentExtractionEvidencePageResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> CreateUploadIntentAsync(
        CreateSourceDocumentUploadIntentRequest request,
        ClaimsPrincipal principal,
        SourceDocumentService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.CreateUploadIntentAsync(
            userId,
            request.FundingSourceId,
            request.FileName,
            request.MimeType,
            request.ContentLength,
            cancellationToken);
        if (result.Outcome != SourceDocumentOutcome.Success ||
            result.IntentPublicId is null || result.Status is null ||
            result.ExpiresAtUtc is null || result.UploadUri is null ||
            result.RequiredHeaders is null || result.CompletionToken is null ||
            result.RowVersion is not { Length: 8 })
            return MapFailure(result.Outcome, result.Code, result.Errors);

        var etag = SetETag(context, result.RowVersion);
        return Results.Created(
            $"/api/v1/admin/source-document-upload-intents/{result.IntentPublicId:D}",
            new SourceDocumentUploadIntentCreatedResponse(
                result.IntentPublicId.Value,
                (byte)result.Status.Value,
                result.ExpiresAtUtc.Value,
                result.MaxContentLength,
                "PUT",
                result.UploadUri,
                result.RequiredHeaders,
                result.CompletionToken,
                $"/api/v1/admin/source-document-upload-intents/{result.IntentPublicId:D}",
                etag,
                "La autorización sólo permite crear este blob. Tamaño, MIME y PDF se validan nuevamente al completar."));
    }

    private static async Task<IResult> CompleteUploadIntentAsync(
        Guid intentId,
        CompleteSourceDocumentUploadIntentRequest request,
        ClaimsPrincipal principal,
        SourceDocumentService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.CompleteUploadIntentAsync(
            userId, intentId, request.CompletionToken, cancellationToken);
        return MapOperation(
            result,
            context,
            $"/api/v1/admin/source-document-upload-intents/{intentId:D}");
    }

    private static async Task<IResult> RetryScanAsync(
        Guid sourceDocumentId,
        ClaimsPrincipal principal,
        SourceDocumentService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out var rowVersion))
            return ProjectEndpointResults.PreconditionRequired(
                "if-match-required", "Versión requerida",
                "Envía el ETag fuerte vigente en If-Match.");
        var idempotencyKey = context.Request.Headers["Idempotency-Key"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Idempotency-Key requerida",
                "Envía una clave única y reutilízala sólo al reintentar esta operación.");

        var result = await service.RetryScanAsync(
            userId,
            sourceDocumentId,
            rowVersion,
            idempotencyKey,
            cancellationToken);
        return MapOperation(
            result,
            context,
            $"/api/v1/admin/source-documents/{sourceDocumentId:D}");
    }

    private static async Task<IResult> GetUploadIntentAsync(
        Guid intentId,
        ClaimsPrincipal principal,
        SourceDocumentService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.GetUploadIntentAsync(userId, intentId, cancellationToken);
        if (result.Value is null)
            return MapFailure(result.Outcome, "upload-intent-not-found", null);
        var value = result.Value;
        var etag = SetETag(context, value.RowVersion);
        return Results.Ok(new SourceDocumentUploadIntentResponse(
            value.IntentPublicId,
            value.FundingSourceId,
            value.FundingSourceName,
            value.OriginalFileName,
            value.DeclaredMimeType,
            value.ExpectedContentLength,
            value.MaxContentLength,
            (byte)value.Status,
            value.ExpiresAtUtc,
            value.SourceDocumentPublicId,
            value.StorageStatus.HasValue ? (byte)value.StorageStatus.Value : null,
            value.ScanStatus.HasValue ? (byte)value.ScanStatus.Value : null,
            value.ScanProvider.HasValue ? (byte)value.ScanProvider.Value : null,
            value.ScanResultCode,
            value.CreatedAtUtc,
            value.CompletedAtUtc,
            value.UpdatedAtUtc,
            etag,
            value.ScanProvider == SourceDocumentScanProvider.DevelopmentFake));
    }

    private static async Task<IResult> GetSourceDocumentAsync(
        Guid sourceDocumentId,
        ClaimsPrincipal principal,
        SourceDocumentService service,
        SourceDocumentExtractionAdminService extractionService,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.GetSourceDocumentAsync(
            userId, sourceDocumentId, cancellationToken);
        if (result.Value is null)
            return MapFailure(result.Outcome, "source-document-not-found", null);
        var value = result.Value;
        var etag = SetETag(context, value.RowVersion);
        var extraction = await extractionService.GetLatestAsync(
            userId, sourceDocumentId, cancellationToken);
        var summary = extraction.Value is { JobId: not null, JobRowVersion.Length: 8 } latest
            ? ToSummary(latest)
            : null;
        return Results.Ok(new SourceDocumentResponse(
            value.SourceDocumentPublicId,
            value.FundingSourceId,
            value.FundingSourceName,
            value.OriginalFileName,
            value.MimeType,
            value.ContentLength,
            (byte)value.StorageStatus,
            (byte)value.ScanStatus,
            (byte)value.ScanProvider,
            value.IsProductionScan,
            value.ScanAttemptCount,
            value.ScanResultCode,
            value.ScanStartedAtUtc,
            value.ScanCompletedAtUtc,
            value.ExtractionStatus,
            value.UploadedByUserPublicId,
            value.CreatedAtUtc,
            value.UpdatedAtUtc,
            etag,
            summary,
            (byte)value.ContentRetentionStatus,
            value.RetentionUntilUtc,
            value.ContentDeletionRequestedAtUtc,
            value.ContentRetentionLastErrorCode));
    }

    private static async Task<IResult> StartExtractionAsync(
        Guid sourceDocumentId,
        ClaimsPrincipal principal,
        SourceDocumentExtractionAdminService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out var rowVersion))
            return ProjectEndpointResults.PreconditionRequired(
                "if-match-required", "Versión requerida",
                "Envía el ETag fuerte vigente en If-Match.");
        var idempotencyKey = context.Request.Headers["Idempotency-Key"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Idempotency-Key requerida",
                "Envía una clave única y reutilízala sólo para reintentar esta extracción.");

        var result = await service.StartAsync(
            userId,
            sourceDocumentId,
            rowVersion,
            idempotencyKey,
            context.TraceIdentifier,
            cancellationToken);
        if (result.Outcome != SourceDocumentExtractionOutcome.Accepted ||
            result.JobId is null || result.Status is null ||
            result.RowVersion is not { Length: 8 })
            return MapExtractionFailure(result.Outcome, result.Code, result.Errors);
        var etag = SetETag(context, result.RowVersion);
        var statusUrl = $"/api/v1/admin/source-documents/{sourceDocumentId:D}/extractions/latest";
        context.Response.Headers.Location = statusUrl;
        return Results.Accepted(statusUrl, new SourceDocumentExtractionStartedResponse(
            sourceDocumentId,
            result.JobId.Value,
            (byte)result.Status.Value,
            result.AttemptCount,
            result.MaxAttempts,
            statusUrl,
            etag,
            result.WasReplay));
    }

    private static async Task<IResult> GetLatestExtractionAsync(
        Guid sourceDocumentId,
        ClaimsPrincipal principal,
        SourceDocumentExtractionAdminService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        var result = await service.GetLatestAsync(userId, sourceDocumentId, cancellationToken);
        if (result.Value is null)
            return MapExtractionFailure(result.Outcome, result.Code, null);
        var value = result.Value;
        var documentETag = ProjectEndpointResults.FormatETag(value.DocumentRowVersion);
        var etag = value.JobRowVersion is { Length: 8 }
            ? SetETag(context, value.JobRowVersion)
            : SetETag(context, value.DocumentRowVersion);
        return Results.Ok(new SourceDocumentExtractionResultResponse(
            value.SourceDocumentId,
            value.JobId,
            (byte)value.Status,
            value.ParserCode,
            value.ParserVersion,
            value.AttemptCount,
            value.MaxAttempts,
            value.PageCount,
            value.CharacterCount,
            value.CompletedWithErrors,
            value.EvidenceCount,
            value.ErrorCount,
            value.TextPreview,
            value.LastErrorCode,
            value.CreatedAtUtc,
            value.StartedAtUtc,
            value.CompletedAtUtc,
            value.UpdatedAtUtc,
            value.IsContentRedacted,
            value.RedactedAtUtc,
            value.IsSecurityRevoked,
            etag,
            documentETag));
    }

    private static async Task<IResult> GetLatestExtractionEvidenceAsync(
        Guid sourceDocumentId,
        ClaimsPrincipal principal,
        SourceDocumentExtractionAdminService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 25)
    {
        if (!TryGetUserId(principal, out var userId)) return InvalidSession();
        if (page < 1 || pageSize is < 1 or > 100)
            return ProjectEndpointResults.Validation(
                422,
                "Paginación inválida",
                "invalid-evidence-page",
                new Dictionary<string, string[]>
                {
                    ["page"] = ["Debe ser mayor o igual a 1."],
                    ["pageSize"] = ["Debe estar entre 1 y 100."]
                });
        var latest = await service.GetLatestAsync(userId, sourceDocumentId, cancellationToken);
        if (latest.Value?.JobId is not Guid jobId)
            return MapExtractionFailure(
                latest.Value is null ? latest.Outcome : SourceDocumentExtractionOutcome.NotFound,
                latest.Value is null ? latest.Code : "extraction-not-found",
                null);
        if (latest.Value.IsSecurityRevoked)
            return ProjectEndpointResults.Problem(
                409,
                "La extracción fue revocada por seguridad",
                "El resultado dejó de ser confiable después de una actualización del análisis antimalware.",
                "security-revoked");
        if (latest.Value.IsContentRedacted)
            return ProjectEndpointResults.Problem(
                410,
                "El contenido de la extracción fue eliminado",
                "La política de retención eliminó los extractos conservando sólo la trazabilidad técnica.",
                "content-retention-redacted");
        var result = await service.ListEvidenceAsync(
            userId, jobId, page, pageSize, cancellationToken);
        if (result.Value is null)
            return MapExtractionFailure(result.Outcome, result.Code, null);
        return Results.Ok(new SourceDocumentExtractionEvidencePageResponse(
            result.Value.Items.Select(item => new SourceDocumentExtractionEvidenceResponse(
                item.EvidenceId,
                item.Ordinal,
                item.PageNumber,
                item.StartOffset,
                item.CharacterLength,
                item.Excerpt,
                item.CreatedAtUtc)).ToArray(),
            result.Value.Page,
            result.Value.PageSize,
            result.Value.TotalCount));
    }

    private static SourceDocumentExtractionSummaryResponse ToSummary(
        SourceDocumentExtractionAdminView value) => new(
            value.JobId!.Value,
            (byte)value.Status,
            value.AttemptCount,
            value.MaxAttempts,
            value.PageCount,
            value.CharacterCount,
            value.CompletedWithErrors,
            value.EvidenceCount,
            value.ErrorCount,
            value.LastErrorCode,
            value.StartedAtUtc,
            value.CompletedAtUtc,
            value.CreatedAtUtc,
            value.UpdatedAtUtc,
            value.IsContentRedacted,
            value.RedactedAtUtc,
            value.IsSecurityRevoked,
            ProjectEndpointResults.FormatETag(value.JobRowVersion!));

    private static IResult MapExtractionFailure(
        SourceDocumentExtractionOutcome outcome,
        string code,
        IReadOnlyDictionary<string, string[]>? errors) => outcome switch
    {
        SourceDocumentExtractionOutcome.Invalid => ProjectEndpointResults.Validation(
            422, "Extracción inválida", code, errors),
        SourceDocumentExtractionOutcome.NotFound => ProjectEndpointResults.Problem(
            404, "Documento o extracción no encontrada", null, code),
        SourceDocumentExtractionOutcome.Forbidden => ProjectEndpointResults.Problem(
            403, "Acceso denegado", null, code),
        SourceDocumentExtractionOutcome.PreconditionFailed => ProjectEndpointResults.Problem(
            412, "El documento cambió",
            "Recarga el documento antes de iniciar la extracción.", code),
        SourceDocumentExtractionOutcome.Conflict => ProjectEndpointResults.Problem(
            409, "La extracción no puede iniciarse en el estado actual", null, code),
        _ => ProjectEndpointResults.Problem(
            503, "Extracción temporalmente no disponible", null,
            "source-document-extraction-unavailable")
    };

    private static IResult MapOperation(
        SourceDocumentOperationResult result,
        HttpContext context,
        string pendingStatusUrl)
    {
        if (result.Outcome is SourceDocumentOutcome.Success or SourceDocumentOutcome.Processing)
        {
            if (result.RowVersion is not { Length: 8 })
                return ProjectEndpointResults.Problem(
                    503, "Carga temporalmente no disponible", null, "source-document-unavailable");
            var etag = SetETag(context, result.RowVersion);
            var isTerminal = result.ScanStatus is SourceDocumentScanStatus.Clean or
                SourceDocumentScanStatus.Malicious or SourceDocumentScanStatus.Failed or
                SourceDocumentScanStatus.TimedOut ||
                result.IntentStatus is SourceDocumentUploadIntentStatus.Expired or
                    SourceDocumentUploadIntentStatus.Rejected;
            var response = new SourceDocumentOperationResponse(
                result.IntentPublicId,
                result.IntentStatus.HasValue ? (byte)result.IntentStatus.Value : null,
                result.SourceDocumentPublicId,
                result.StorageStatus.HasValue ? (byte)result.StorageStatus.Value : null,
                result.ScanStatus.HasValue ? (byte)result.ScanStatus.Value : null,
                result.ScanProvider.HasValue ? (byte)result.ScanProvider.Value : null,
                result.ScanAttemptCount,
                etag,
                result.WasReplay,
                isTerminal,
                result.ScanProvider == SourceDocumentScanProvider.DevelopmentFake);
            if (result.Outcome != SourceDocumentOutcome.Processing)
                return Results.Ok(response);
            context.Response.Headers.RetryAfter = "2";
            return Results.Accepted(pendingStatusUrl, response);
        }
        return MapFailure(result.Outcome, result.Code, result.Errors);
    }

    private static IResult MapFailure(
        SourceDocumentOutcome outcome,
        string code,
        IReadOnlyDictionary<string, string[]>? errors) => outcome switch
    {
        SourceDocumentOutcome.ValidationFailed => ProjectEndpointResults.Validation(
            422, "Documento inválido", code, errors),
        SourceDocumentOutcome.NotFound => ProjectEndpointResults.Problem(
            404, "Carga no encontrada", null, "source-document-upload-not-found"),
        SourceDocumentOutcome.Forbidden => ProjectEndpointResults.Problem(
            403, "Acceso denegado", null, "source-document-forbidden"),
        SourceDocumentOutcome.Expired => ProjectEndpointResults.Problem(
            410, "La autorización de carga venció",
            "Crea una nueva autorización y vuelve a cargar el archivo.", "upload-intent-expired"),
        SourceDocumentOutcome.Conflict or SourceDocumentOutcome.InvalidTransition =>
            ProjectEndpointResults.Problem(
                409, "La operación no es compatible con el estado actual", null, code),
        SourceDocumentOutcome.PreconditionFailed => ProjectEndpointResults.Problem(
            412, "El documento cambió",
            "Recarga el estado vigente antes de reintentar.", "source-document-etag-conflict"),
        SourceDocumentOutcome.RetryLimitReached => ProjectEndpointResults.Problem(
            429, "Se alcanzó el límite de reintentos", null, code),
        _ => ProjectEndpointResults.Problem(
            503, "Carga temporalmente no disponible", null, "source-document-unavailable")
    };

    private static string SetETag(HttpContext context, byte[] rowVersion)
    {
        var etag = ProjectEndpointResults.FormatETag(rowVersion);
        context.Response.Headers.ETag = etag;
        return etag;
    }

    private static bool TryGetUserId(ClaimsPrincipal principal, out Guid userId) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out userId);

    private static IResult InvalidSession() => ProjectEndpointResults.InvalidSession();
}
