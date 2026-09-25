using System.Security.Claims;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Contracts.Organizations;
using FundingPlatform.Core.Organizations;

namespace FundingPlatform.Api.Endpoints;

public static class OrganizationVerificationEndpoints
{
    public static IEndpointRouteBuilder MapOrganizationVerificationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/organizations/{organizationId:guid}/verification")
            .WithTags("Organization Verification")
            .RequireAuthorization("admin-mfa");

        group.MapGet("", GetAsync)
            .RequireRateLimiting("organization-activity-read")
            .Produces<OrganizationVerificationResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapPost("", DecideAsync)
            .RequireRateLimiting("organization-write")
            .Produces<OrganizationVerificationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        return endpoints;
    }

    private static async Task<IResult> GetAsync(Guid organizationId, ClaimsPrincipal principal,
        OrganizationVerificationService service, HttpContext context, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor))
            return ProjectEndpointResults.InvalidSession();
        if (organizationId == Guid.Empty) return NotFound();
        try
        {
            var value = await service.GetAsync(actor, organizationId, cancellationToken);
            return value is null ? NotFound() : Results.Ok(Map(value));
        }
        catch (OrganizationVerificationDataException exception) { return Failure(exception); }
    }

    private static async Task<IResult> DecideAsync(Guid organizationId,
        OrganizationVerificationDecisionRequest request, ClaimsPrincipal principal,
        OrganizationVerificationService service, HttpContext context, CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor))
            return ProjectEndpointResults.InvalidSession();
        if (organizationId == Guid.Empty) return NotFound();
        try
        {
            var result = await service.DecideAsync(actor, organizationId,
                new OrganizationVerificationDecision(request.Status ?? -1, request.Reason,
                    request.ExpectedRevision ?? -1, request.ExpectedProfileVersion ?? 0), cancellationToken);
            return result.Errors is { Count: > 0 }
                ? FieldValidationResults.BadRequest(result.Errors,
                    title: "Revisa la decisión de verificación", statusCode: StatusCodes.Status422UnprocessableEntity)
                : Results.Ok(Map(result.Verification!));
        }
        catch (OrganizationVerificationDataException exception) { return Failure(exception); }
    }

    private static IResult NotFound() => ProjectEndpointResults.Problem(404,
        "Organización no encontrada", null, "organization-not-found");

    private static IResult Failure(OrganizationVerificationDataException exception) =>
        exception.DatabaseErrorNumber switch
        {
            51601 or 51602 => ProjectEndpointResults.Problem(403, "Acceso denegado", null, "admin-mfa-required"),
            56301 => NotFound(),
            56302 => ProjectEndpointResults.Problem(409, "La organización cambió",
                "Recarga el perfil y la revisión antes de decidir nuevamente.", "organization-verification-conflict"),
            56303 => ProjectEndpointResults.Problem(422, "Decisión de verificación inválida",
                "Revisa el estado, el motivo y las versiones del perfil y de la revisión.", "organization-verification-invalid"),
            _ => ProjectEndpointResults.Problem(503, "Verificación temporalmente no disponible",
                "Intenta nuevamente en unos minutos.", "organization-verification-unavailable")
        };

    private static OrganizationVerificationResponse Map(OrganizationVerification value) => new(
        value.OrganizationPublicId, value.Name, value.Status, value.RecordedStatus, value.Revision,
        value.ProfileVersion, value.ReviewedProfileVersion, value.ReviewedAtUtc,
        value.ReviewedByUserPublicId, value.ReviewedByName, value.Reason, value.NeedsReverification,
        value.History.Select(entry => new OrganizationVerificationHistoryResponse(entry.Revision,
            entry.Status, entry.ProfileVersion, entry.Reason, entry.ReviewedAtUtc,
            entry.ReviewedByUserPublicId, entry.ReviewedByName)).ToArray());
}
