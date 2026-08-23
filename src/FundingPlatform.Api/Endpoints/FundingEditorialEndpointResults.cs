using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

internal static class FundingEditorialEndpointResults
{
    internal static IResult MapCommand(
        FundingEditorialCommandResult result,
        HttpContext context,
        string entityName,
        string notFoundCode)
    {
        if (result.Outcome == FundingEditorialOutcome.Success)
        {
            if (result.RowVersion is not { Length: 8 })
            {
                return ProjectEndpointResults.Problem(
                    500, "No fue posible completar la operación", null,
                    "funding-editorial-operation-failed");
            }

            var etag = ProjectEndpointResults.FormatETag(result.RowVersion);
            context.Response.Headers.ETag = etag;
            return Results.Ok(new FundingEditorialMutationResponse(
                result.EntityPublicId,
                (byte)result.PublicationStatus,
                result.ContentVersion,
                etag,
                result.WasReplay));
        }

        return result.Outcome switch
        {
            FundingEditorialOutcome.ValidationFailed => ProjectEndpointResults.Validation(
                422, "Solicitud inválida",
                result.Code == "source-disabled"
                    ? "source-disabled"
                    : "funding-editorial-validation",
                result.Errors),
            FundingEditorialOutcome.NotReady => ProjectEndpointResults.Validation(
                422, $"{entityName} no está listo para revisión",
                result.Code is "funder-not-ready" or "opportunity-not-ready"
                    ? result.Code
                    : "funding-editorial-not-ready",
                result.Errors),
            FundingEditorialOutcome.NotFound => ProjectEndpointResults.Problem(
                404, $"{entityName} no encontrado", null, notFoundCode),
            FundingEditorialOutcome.Forbidden => ProjectEndpointResults.Problem(
                403, "Acceso denegado", null, "admin-role-required"),
            FundingEditorialOutcome.PreconditionFailed => ProjectEndpointResults.Problem(
                412, "La versión ya no está vigente",
                "Otro cambio fue aplicado antes de esta solicitud. Carga la versión vigente y vuelve a intentarlo.",
                "funding-editorial-precondition-failed"),
            FundingEditorialOutcome.InvalidTransition => ProjectEndpointResults.Problem(
                409, "Transición no permitida",
                "El estado editorial actual no permite esta operación.",
                "funding-editorial-invalid-transition"),
            FundingEditorialOutcome.IdempotencyConflict => ProjectEndpointResults.Problem(
                409, "Conflicto de idempotencia",
                "La misma Idempotency-Key ya se usó con otra solicitud.",
                "idempotency-conflict"),
            FundingEditorialOutcome.Conflict when result.Errors is { Count: > 0 } =>
                ProjectEndpointResults.Validation(
                    409, "La referencia de la fuente ya está vinculada",
                    NormalizeConflictCode(result.Code), result.Errors),
            FundingEditorialOutcome.Conflict => ProjectEndpointResults.Problem(
                409, "El contenido cambió",
                "Recarga el contenido, revisa los datos e intenta nuevamente.",
                NormalizeConflictCode(result.Code)),
            _ => ProjectEndpointResults.Problem(
                500, "No fue posible completar la operación", null,
                "funding-editorial-operation-failed")
        };
    }

    internal static IResult MapCreated(
        FundingEditorialCommandResult result,
        HttpContext context,
        string entityName,
        string notFoundCode,
        string location)
    {
        if (result.Outcome != FundingEditorialOutcome.Success)
        {
            return MapCommand(result, context, entityName, notFoundCode);
        }

        if (result.RowVersion is not { Length: 8 })
        {
            return ProjectEndpointResults.Problem(
                500, "No fue posible completar la operación", null,
                "funding-editorial-operation-failed");
        }

        var etag = ProjectEndpointResults.FormatETag(result.RowVersion);
        context.Response.Headers.ETag = etag;
        return Results.Created(location, new FundingEditorialMutationResponse(
            result.EntityPublicId,
            (byte)result.PublicationStatus,
            result.ContentVersion,
            etag,
            result.WasReplay));
    }

    internal static bool TryGetMutationHeaders(
        HttpContext context,
        bool requiresIfMatch,
        out byte[] rowVersion,
        out string idempotencyKey,
        out IResult? error)
    {
        rowVersion = [];
        idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        error = null;

        if (requiresIfMatch && !ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.ToString(), out rowVersion))
        {
            error = ProjectEndpointResults.PreconditionRequired(
                "if-match-required", "Versión requerida",
                "Envía If-Match con el ETag vigente.");
            return false;
        }

        if (string.IsNullOrWhiteSpace(idempotencyKey))
        {
            error = ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required", "Clave de idempotencia requerida",
                "Envía Idempotency-Key para ejecutar esta mutación.");
            return false;
        }

        return true;
    }

    private static string NormalizeConflictCode(string? code) => code switch
    {
        "slug-conflict" => "funding-editorial-slug-conflict",
        "name-conflict" => "funder-name-conflict",
        "alias-conflict" => "funder-alias-conflict",
        "source-link-conflict" => "source-link-conflict",
        _ => "funding-editorial-conflict"
    };
}
