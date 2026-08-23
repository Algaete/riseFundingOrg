using System.Security.Claims;
using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Api.Endpoints;

internal static class ProjectEndpointResults
{
    internal static IResult MapWorkflow(ProjectWorkflowResult result, HttpContext context)
    {
        if (result.Outcome == ProjectWorkflowOutcome.Success)
        {
            if (result.RowVersion is not { Length: 8 })
            {
                return Problem(500, "No fue posible completar la operación", null,
                    "project-workflow-failed");
            }

            var etag = FormatETag(result.RowVersion);
            context.Response.Headers.ETag = etag;
            return Results.Ok(new ProjectWorkflowResponse(
                result.ProjectPublicId,
                (byte)result.PublicationStatus,
                result.Completeness,
                etag,
                result.WasReplay));
        }

        return result.Outcome switch
        {
            ProjectWorkflowOutcome.ValidationFailed => Validation(
                422, "Solicitud inválida", "project-workflow-validation", result.Errors),
            ProjectWorkflowOutcome.NotReady => Validation(
                422, "El proyecto no está listo", "project-not-ready", result.Errors),
            ProjectWorkflowOutcome.NotFound => Problem(
                404, "Proyecto no encontrado", null, "project-not-found"),
            ProjectWorkflowOutcome.Forbidden => Problem(
                403, "Acceso denegado", null, "project-workflow-forbidden"),
            ProjectWorkflowOutcome.Conflict => Problem(
                409, "El proyecto cambió",
                "Recarga el proyecto e intenta nuevamente.", "project-concurrency-conflict"),
            ProjectWorkflowOutcome.InvalidTransition => Problem(
                409, "Transición no permitida",
                "El estado actual del proyecto no permite esta operación.",
                "project-invalid-transition"),
            ProjectWorkflowOutcome.IdempotencyConflict => Problem(
                409, "Conflicto de idempotencia",
                "La misma Idempotency-Key ya se usó con otra solicitud.",
                "idempotency-conflict"),
            _ => Problem(500, "No fue posible completar la operación", null,
                "project-workflow-failed")
        };
    }

    internal static bool TryParseETag(string? value, out byte[] rowVersion)
    {
        rowVersion = [];
        var normalized = value?.Trim();
        if (string.IsNullOrEmpty(normalized) || normalized == "*" || normalized.StartsWith("W/", StringComparison.OrdinalIgnoreCase))
            return false;

        normalized = normalized.Trim('"');
        if (normalized.Length != 16) return false;
        try
        {
            rowVersion = Convert.FromHexString(normalized);
            return rowVersion.Length == 8;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    internal static bool TryGetUserId(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);

    internal static string FormatETag(byte[] rowVersion) =>
        $"\"{Convert.ToHexString(rowVersion)}\"";

    internal static IResult InvalidSession() => Problem(
        401, "Sesión inválida", "Inicia sesión nuevamente.", "invalid-session");

    internal static IResult PreconditionRequired(
        string code,
        string title,
        string detail) => Problem(428, title, detail, code);

    internal static IResult Validation(
        int status,
        string title,
        string code,
        IReadOnlyDictionary<string, string[]>? errors) =>
        Results.Problem(
            statusCode: status,
            title: title,
            type: $"https://fundingplatform.local/problems/{code}",
            extensions: new Dictionary<string, object?>
            {
                ["errors"] = errors ?? new Dictionary<string, string[]>()
            });

    internal static IResult Problem(
        int status,
        string title,
        string? detail,
        string code) => Results.Problem(
            statusCode: status,
            title: title,
            detail: detail,
            type: $"https://fundingplatform.local/problems/{code}");
}
