using System.Diagnostics;
using Serilog.Context;

namespace FundingPlatform.Api.Middleware;

public sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Correlation-ID";

    private const int MaxLength = 128;

    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var correlationId = TryGetRequestedCorrelationId(context, out var requestedCorrelationId)
            ? requestedCorrelationId
            : CreateCorrelationId(context);

        context.TraceIdentifier = correlationId;
        context.Response.OnStarting(() =>
        {
            context.Response.Headers[HeaderName] = correlationId;
            return Task.CompletedTask;
        });

        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            await next(context);
        }
    }

    private static bool TryGetRequestedCorrelationId(HttpContext context, out string correlationId)
    {
        correlationId = string.Empty;

        if (!context.Request.Headers.TryGetValue(HeaderName, out var values) || values.Count != 1)
        {
            return false;
        }

        var candidate = values[0];
        if (string.IsNullOrWhiteSpace(candidate) || candidate.Length > MaxLength)
        {
            return false;
        }

        if (!candidate.All(character => char.IsLetterOrDigit(character) || character is '-' or '_' or '.' or ':' or '/'))
        {
            return false;
        }

        correlationId = candidate;
        return true;
    }

    private static string CreateCorrelationId(HttpContext context)
    {
        var traceId = Activity.Current?.TraceId.ToString();
        return !string.IsNullOrWhiteSpace(traceId)
            ? traceId
            : string.IsNullOrWhiteSpace(context.TraceIdentifier)
                ? Guid.NewGuid().ToString("N")
                : context.TraceIdentifier;
    }
}
