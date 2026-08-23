using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class AdminFundingDuplicateEndpoints
{
    public static IEndpointRouteBuilder MapAdminFundingDuplicateEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/funding-duplicate-candidates")
            .WithTags("Admin Funding Duplicate Review")
            .RequireAuthorization("admin-mfa");
        group.MapGet("/", ListAsync)
            .Produces<FundingDuplicateCandidateListResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/{candidateId:guid}", GetAsync)
            .Produces<FundingDuplicateCandidateDetailResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapPost("/{candidateId:guid}/decisions", DecideAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingDuplicateDecisionResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        ClaimsPrincipal principal,
        FundingDuplicateReviewService service,
        CancellationToken cancellationToken,
        byte? status = null,
        int page = 1,
        int pageSize = 25)
    {
        if (!TryUser(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.ListAsync(
            userId, status, page, pageSize, cancellationToken);
        if (result.Value is null) return Failure(result.Outcome, result.Code, result.Errors);
        return Results.Ok(new FundingDuplicateCandidateListResponse(
            result.Value.Items.Select(item => new FundingDuplicateCandidateSummaryResponse(
                item.CandidateId,
                item.CandidateOpportunityId,
                item.CandidateTitle,
                item.CandidateSponsor,
                item.SuggestedCanonicalOpportunityId,
                item.SuggestedCanonicalTitle,
                item.MatchKind,
                MatchReason(item.MatchKind),
                item.Confidence,
                item.Status,
                item.CreatedAtUtc,
                item.DecidedAtUtc,
                ProjectEndpointResults.FormatETag(item.RowVersion))).ToArray(),
            result.Value.TotalCount,
            result.Value.Page,
            result.Value.PageSize));
    }

    private static async Task<IResult> GetAsync(
        Guid candidateId,
        ClaimsPrincipal principal,
        FundingDuplicateReviewService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.GetAsync(userId, candidateId, cancellationToken);
        if (result.Value is null) return Failure(result.Outcome, result.Code, result.Errors);
        var value = result.Value;
        var etag = ProjectEndpointResults.FormatETag(value.RowVersion);
        context.Response.Headers.ETag = etag;
        return Results.Ok(new FundingDuplicateCandidateDetailResponse(
            value.CandidateId,
            Preview(value.Candidate),
            value.SuggestedCanonical is null ? null : Preview(value.SuggestedCanonical),
            value.MatchKind,
            value.MatchReasonCode,
            value.Confidence,
            value.Status,
            value.CreatedAtUtc,
            value.DecidedAtUtc,
            value.Decision is null ? null : new FundingDuplicateDecisionViewResponse(
                value.Decision.DecisionId,
                value.Decision.Decision,
                value.Decision.CanonicalOpportunityId,
                value.Decision.Reason,
                value.Decision.CreatedAtUtc),
            etag));
    }

    private static async Task<IResult> DecideAsync(
        Guid candidateId,
        FundingDuplicateDecisionRequest request,
        ClaimsPrincipal principal,
        FundingDuplicateReviewService service,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!TryUser(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out var rowVersion))
            return ProjectEndpointResults.PreconditionRequired(
                "if-match-required", "Versión requerida", "Envía el ETag fuerte vigente.");
        var key = context.Request.Headers["Idempotency-Key"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(key))
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Idempotency-Key requerida",
                "Envía una clave única para esta decisión.");
        var result = await service.DecideAsync(
            userId,
            candidateId,
            rowVersion,
            request.Decision,
            request.CanonicalOpportunityId,
            request.Reason,
            key,
            cancellationToken);
        if (result.Value is not { Succeeded: true, CandidateId: not null,
                DecisionId: not null, Status: not null, Decision: not null,
                RowVersion.Length: 8 } value)
            return Failure(result.Outcome, result.Code, result.Errors);
        var etag = ProjectEndpointResults.FormatETag(value.RowVersion);
        context.Response.Headers.ETag = etag;
        return Results.Ok(new FundingDuplicateDecisionResponse(
            value.CandidateId.Value,
            value.DecisionId.Value,
            value.Status.Value,
            value.Decision.Value,
            value.CanonicalOpportunityId,
            value.DecidedAtUtc,
            etag,
            value.WasReplay));
    }

    private static FundingDuplicateOpportunityPreviewResponse Preview(
        FundingDuplicateOpportunityPreview value) => new(
            value.OpportunityId, value.Title, value.Sponsor, value.PublicationStatus);

    private static string MatchReason(byte kind) => kind switch
    {
        0 => "exact-content-fingerprint",
        1 => "exact-canonical-url",
        2 => "normalized-title-sponsor",
        _ => "unknown"
    };

    private static IResult Failure(
        FundingDuplicateReviewOutcome outcome,
        string code,
        IReadOnlyDictionary<string, string[]>? errors) => outcome switch
    {
        FundingDuplicateReviewOutcome.Invalid => ProjectEndpointResults.Validation(
            422, "Decisión inválida", code, errors),
        FundingDuplicateReviewOutcome.NotFound => ProjectEndpointResults.Problem(
            404, "Comparación no encontrada", null, code),
        FundingDuplicateReviewOutcome.Forbidden => ProjectEndpointResults.Problem(
            403, "Acceso denegado", null, code),
        FundingDuplicateReviewOutcome.PreconditionFailed => ProjectEndpointResults.Problem(
            412, "La comparación cambió",
            "Recarga la comparación antes de decidir.", code),
        FundingDuplicateReviewOutcome.Conflict => ProjectEndpointResults.Problem(
            409, "La decisión entra en conflicto con el estado vigente", null, code),
        _ => ProjectEndpointResults.Problem(
            503, "Revisión temporalmente no disponible", null,
            "duplicate-review-unavailable")
    };

    private static bool TryUser(ClaimsPrincipal principal, out Guid userId) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
