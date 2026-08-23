using System.Net;
using System.Text.Json;
using FundingPlatform.Application.SourceDocuments;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace FundingPlatform.Workers.Functions;

public sealed class DefenderEventGridFunction(
    IEventGridBearerTokenValidator tokens,
    DefenderEventGridService service,
    ILogger<DefenderEventGridFunction> logger)
{
    [Function(nameof(DefenderEventGridFunction))]
    public async Task<HttpResponseData> RunAsync(
        [HttpTrigger(
            AuthorizationLevel.Anonymous,
            "post",
            Route = "webhooks/defender-storage")]
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrEmpty(request.Url.Query) ||
            !TrySingleHeader(request, "Content-Type", out var contentType) ||
            !IsJson(contentType) ||
            !TrySingleHeader(request, "aeg-event-type", out var eventType) ||
            !TrySingleHeader(request, "aeg-subscription-name", out var subscriptionName))
        {
            return await ResponseAsync(request, HttpStatusCode.BadRequest,
                new { code = "event-request-rejected" }, cancellationToken);
        }

        if (!TrySingleHeader(request, "Authorization", out var authorization))
        {
            return await ResponseAsync(request, HttpStatusCode.Unauthorized,
                new { code = "event-authentication-required" }, cancellationToken);
        }

        var tokenValidation = await tokens.ValidateAsync(authorization, cancellationToken);
        if (tokenValidation.Outcome == EventGridTokenValidationOutcome.Unavailable)
        {
            return await ResponseAsync(request, HttpStatusCode.ServiceUnavailable,
                new { code = "event-authentication-unavailable" }, cancellationToken);
        }
        if (tokenValidation.Outcome != EventGridTokenValidationOutcome.Valid ||
            tokenValidation.Caller is null)
        {
            return await ResponseAsync(request, HttpStatusCode.Unauthorized,
                new { code = "event-authentication-required" }, cancellationToken);
        }

        var payload = await ReadBoundedAsync(request.Body, 65_536, cancellationToken);
        if (payload is null)
        {
            return await ResponseAsync(request, HttpStatusCode.RequestEntityTooLarge,
                new { code = "event-payload-too-large" }, cancellationToken);
        }

        var result = await service.HandleAsync(
            payload,
            eventType,
            subscriptionName,
            tokenValidation.Caller,
            cancellationToken);
        logger.LogInformation(
            "Defender Event Grid delivery finished with {OutcomeCode} for source document {SourceDocumentId}.",
            result.Code,
            result.SourceDocumentId);

        return result.Outcome switch
        {
            DefenderEventGridOutcome.ValidationHandshake => await ResponseAsync(
                request,
                HttpStatusCode.OK,
                new { validationResponse = result.ValidationCode },
                cancellationToken),
            DefenderEventGridOutcome.Applied => await ResponseAsync(
                request,
                HttpStatusCode.OK,
                new { code = result.Code },
                cancellationToken),
            DefenderEventGridOutcome.Rejected => await ResponseAsync(
                request,
                HttpStatusCode.BadRequest,
                new { code = result.Code },
                cancellationToken),
            _ => await ResponseAsync(
                request,
                HttpStatusCode.ServiceUnavailable,
                new { code = result.Code },
                cancellationToken)
        };
    }

    private static bool TrySingleHeader(
        HttpRequestData request,
        string name,
        out string value)
    {
        value = string.Empty;
        if (!request.Headers.TryGetValues(name, out var values)) return false;
        using var enumerator = values.GetEnumerator();
        if (!enumerator.MoveNext()) return false;
        var candidate = enumerator.Current;
        if (enumerator.MoveNext() || string.IsNullOrWhiteSpace(candidate) ||
            candidate.Contains('\r') || candidate.Contains('\n')) return false;
        value = candidate;
        return true;
    }

    private static bool IsJson(string? contentType) =>
        string.Equals(
            contentType?.Split(';', 2)[0].Trim(),
            "application/json",
            StringComparison.OrdinalIgnoreCase);

    private static async Task<byte[]?> ReadBoundedAsync(
        Stream stream,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        using var buffer = new MemoryStream();
        var chunk = new byte[8 * 1024];
        while (true)
        {
            var read = await stream.ReadAsync(chunk, cancellationToken);
            if (read == 0) return buffer.ToArray();
            if (buffer.Length + read > maximumBytes) return null;
            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }
    }

    private static async Task<HttpResponseData> ResponseAsync<T>(
        HttpRequestData request,
        HttpStatusCode status,
        T body,
        CancellationToken cancellationToken)
    {
        var response = request.CreateResponse(status);
        response.Headers.Add("Content-Type", "application/json; charset=utf-8");
        response.Headers.Add("Cache-Control", "no-store");
        await JsonSerializer.SerializeAsync(response.Body, body,
            cancellationToken: cancellationToken);
        return response;
    }
}
