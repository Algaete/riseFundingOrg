using FundingPlatform.Application.Collaboration;

namespace FundingPlatform.Api.Endpoints;

public sealed class CollaborationExceptionFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        try { return await next(context); }
        catch (CollaborationDataException exception) when (exception.DatabaseErrorNumber is >= 55501 and <= 55508 or 1205)
        {
            var (status, code) = exception.DatabaseErrorNumber switch
            {
                55501 => (404, "collaboration-not-found"),
                55502 => (403, "collaboration-forbidden"),
                55503 => (412, "collaboration-version-conflict"),
                55504 => (409, "collaboration-already-exists"),
                55505 => (422, "collaboration-invalid-data"),
                55506 => (409, "idempotency-conflict"),
                55507 => (409, "collaboration-invalid-transition"),
                55508 => (429, "collaboration-limit"),
                _ => (503, "collaboration-retry")
            };
            return ProjectEndpointResults.Problem(status, "No fue posible completar la operación", null, code);
        }
    }
}

internal static class CollaborationEndpointSupport
{
    internal static bool Headers(HttpContext context, bool versionRequired, bool allowCreate,
        out string key, out byte[]? version, out IResult? error)
    {
        key = context.Request.Headers["Idempotency-Key"].ToString(); version = null; error = null;
        if (!CollaborationRules.ValidKey(key))
        {
            error = ProjectEndpointResults.Problem(string.IsNullOrEmpty(key) ? 428 : 400, "Idempotency-Key requerida", null, "idempotency-key-required");
            return false;
        }
        if (!versionRequired) return true;
        var match = context.Request.Headers.IfMatch.ToString();
        var none = context.Request.Headers.IfNoneMatch.ToString();
        if (allowCreate && none == "*" && string.IsNullOrEmpty(match)) return true;
        if (!string.IsNullOrEmpty(none) || !ProjectEndpointResults.TryParseETag(match, out var parsed))
        {
            error = ProjectEndpointResults.Problem(string.IsNullOrEmpty(match) && string.IsNullOrEmpty(none) ? 428 : 400,
                "Precondición requerida", null, "if-match-required");
            return false;
        }
        version = parsed; return true;
    }
}
