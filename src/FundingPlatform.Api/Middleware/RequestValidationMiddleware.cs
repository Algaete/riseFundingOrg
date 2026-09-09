using FundingPlatform.Api.Endpoints;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Api.Middleware;

// Binding happens before endpoint handlers. Keep parser exceptions and submitted
// values out of the response and logs; field rules remain in their own services.
public sealed class RequestValidationMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
            // Some binders set 415 without throwing, even with ThrowOnBadRequest.
            // Run inside StatusCodePages so its generic body has not been written.
            if (context.Response.StatusCode == 415 && !context.Response.HasStarted &&
                context.Response.ContentType is null && context.Response.ContentLength is null or 0 &&
                context.GetEndpoint() is not null && context.Request.Path.StartsWithSegments("/api"))
                await WriteProblemAsync(context, 415);
        }
        catch (BadHttpRequestException exception) when (
            exception.StatusCode is 400 or 415 && !context.Response.HasStarted)
        {
            await WriteProblemAsync(context, exception.StatusCode);
        }
    }

    private static Task WriteProblemAsync(HttpContext context, int statusCode)
    {
        var errors = FieldValidationErrors.Single("request", "request-invalid-format",
            "La solicitud contiene datos con formato inválido o incompletos. Revisa los campos.");
        return FieldValidationResults.BadRequest(errors,
            title: "Solicitud inválida", statusCode: statusCode,
            type: "https://fundingplatform.local/problems/request-invalid-format").ExecuteAsync(context);
    }
}
