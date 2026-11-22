using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.AspNetCore.Diagnostics;

namespace FundingPlatform.Api.Middleware;

public sealed class DatabaseAvailabilityExceptionHandler(
    ILogger<DatabaseAvailabilityExceptionHandler> logger) : IExceptionHandler
{
    public const string ProblemType = "https://fundingplatform.local/problems/data-service-unavailable";

    public async ValueTask<bool> TryHandleAsync(
        HttpContext context, Exception exception, CancellationToken cancellationToken)
    {
        if (context.Response.HasStarted || context.RequestAborted.IsCancellationRequested ||
            !SqlConnectionResilience.IsTemporarilyUnavailable(exception)) return false;

        // Do not log SQL messages, connection details, query text or submitted values.
        logger.LogWarning("Database temporarily unavailable; correlation {CorrelationId}",
            context.TraceIdentifier);
        context.Response.Headers.RetryAfter = "10";
        context.Response.Headers.CacheControl = "no-store";
        await Results.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            type: ProblemType,
            title: "Servicio temporalmente no disponible",
            detail: "No pudimos conectar con los datos en este momento. Espera unos segundos y vuelve a intentarlo.")
            .ExecuteAsync(context);
        return true;
    }
}
