using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Semantics;

public sealed class OpenAiEmbeddingService(
    HttpClient httpClient,
    IOptions<OpenAiProviderOptions> options,
    TimeProvider timeProvider) : IEmbeddingService
{
    private static readonly HashSet<string> SupportedModels =
    [
        "text-embedding-3-small", "text-embedding-3-large"
    ];

    private readonly OpenAiProviderOptions options = ValidateOptions(options.Value);
    private readonly HttpClient httpClient = ValidateClient(httpClient, options.Value);

    public async Task<SemanticEmbeddingGeneration> GenerateAsync(
        SemanticEmbeddingRequest request,
        CancellationToken cancellationToken)
    {
        ValidateRequest(request);
        var stopwatch = Stopwatch.StartNew();
        using var message = new HttpRequestMessage(HttpMethod.Post, "embeddings");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);
        if (!string.IsNullOrWhiteSpace(options.ProjectId))
            message.Headers.TryAddWithoutValidation("OpenAI-Project", options.ProjectId);
        message.Content = JsonContent.Create(new
        {
            input = request.CanonicalInputJson,
            model = request.ModelCode,
            dimensions = request.Dimensions,
            encoding_format = "float"
        });

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (HttpRequestException exception)
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-unavailable", retryable: true, exception);
        }

        using (response)
        {
            ValidateResponseOrigin(response);
            if (!response.IsSuccessStatusCode)
                throw MapFailure(response.StatusCode);
            var document = await ReadBoundedJsonAsync(response, cancellationToken);
            using (document)
            {
                var root = document.RootElement;
                if (!root.TryGetProperty("object", out var objectType) ||
                    objectType.GetString() != "list" ||
                    !root.TryGetProperty("model", out var model) ||
                    !string.Equals(model.GetString(), request.ModelCode, StringComparison.Ordinal) ||
                    !root.TryGetProperty("data", out var data) ||
                    data.ValueKind != JsonValueKind.Array || data.GetArrayLength() != 1)
                    throw InvalidResponse();
                var item = data[0];
                if (!item.TryGetProperty("index", out var index) || index.GetInt32() != 0 ||
                    !item.TryGetProperty("object", out var itemType) ||
                    itemType.GetString() != "embedding" ||
                    !item.TryGetProperty("embedding", out var embedding) ||
                    embedding.ValueKind != JsonValueKind.Array ||
                    embedding.GetArrayLength() != request.Dimensions)
                    throw InvalidResponse();

                var vector = new float[request.Dimensions];
                var nonZero = false;
                var position = 0;
                foreach (var value in embedding.EnumerateArray())
                {
                    if (!value.TryGetSingle(out var component) || !float.IsFinite(component))
                        throw InvalidResponse();
                    vector[position++] = component;
                    nonZero |= component != 0;
                }
                if (!nonZero) throw InvalidResponse();

                if (!root.TryGetProperty("usage", out var usage) ||
                    !usage.TryGetProperty("prompt_tokens", out var promptTokensElement) ||
                    !promptTokensElement.TryGetInt32(out var inputTokens) || inputTokens < 0 ||
                    !usage.TryGetProperty("total_tokens", out var totalTokensElement) ||
                    !totalTokensElement.TryGetInt32(out var totalTokens) ||
                    totalTokens < inputTokens)
                    throw InvalidResponse();

                var estimatedCost = CalculateCost(
                    inputTokens,
                    request.ProviderGovernance!.InputTokenCostUsdPerMillion);
                if (estimatedCost > request.MaximumCostUsd)
                    throw InvalidResponse();

                stopwatch.Stop();
                return new SemanticEmbeddingGeneration(
                    OpenAiProviderOptions.ProviderCode,
                    request.ModelCode,
                    request.TemplateVersion,
                    request.Dimensions,
                    vector,
                    inputTokens,
                    totalTokens - inputTokens,
                    estimatedCost,
                    HashRequestId(response),
                    checked((int)Math.Min(stopwatch.ElapsedMilliseconds, int.MaxValue)));
            }
        }
    }

    private void ValidateRequest(SemanticEmbeddingRequest request)
    {
        if (!options.Enabled || !options.EmbeddingsEnabled ||
            !string.Equals(request.ProviderCode, OpenAiProviderOptions.ProviderCode,
                StringComparison.Ordinal) ||
            !SupportedModels.Contains(request.ModelCode) || request.Dimensions != 1536 ||
            request.MaximumCostUsd is < 0 or > 1 ||
            request.ProviderGovernance is not { } governance ||
            governance.PolicyPublicId == Guid.Empty ||
            governance.PolicyFingerprint is not { Length: 32 } ||
            governance.Capability != 0 ||
            !CryptographicOperations.FixedTimeEquals(
                governance.PolicyFingerprint,
                options.GetRequiredEmbeddingGovernanceFingerprint()) ||
            !string.Equals(governance.EndpointOrigin,
                options.GetEndpointOrigin().GetLeftPart(UriPartial.Authority),
                StringComparison.Ordinal) ||
            governance.RetentionMode != AiProviderRetentionMode.ZeroDataRetention ||
            governance.MaximumProviderRetentionDays != 0 ||
            governance.InputTokenCostUsdPerMillion is < 0 or > 1000 ||
            governance.OutputTokenCostUsdPerMillion != 0 ||
            !governance.ExternalProcessingAllowed ||
            governance.ApprovedAtUtc > timeProvider.GetUtcNow() ||
            governance.ExpiresAtUtc <= timeProvider.GetUtcNow())
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-unavailable",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked);
        }
    }

    private static OpenAiProviderOptions ValidateOptions(OpenAiProviderOptions value)
    {
        var validation = new OpenAiProviderOptionsValidator().Validate(null, value);
        if (validation.Failed)
            throw new InvalidOperationException(validation.FailureMessage);
        return value;
    }

    private static HttpClient ValidateClient(
        HttpClient client,
        OpenAiProviderOptions options)
    {
        var endpoint = options.GetEndpointOrigin();
        var expected = new Uri(endpoint, "/v1/");
        if (client.BaseAddress is null ||
            !string.Equals(client.BaseAddress.AbsoluteUri, expected.AbsoluteUri,
                StringComparison.Ordinal))
            throw new InvalidOperationException("OpenAI HttpClient base address is not allowlisted.");
        return client;
    }

    private void ValidateResponseOrigin(HttpResponseMessage response)
    {
        var actual = response.RequestMessage?.RequestUri;
        var expected = new Uri(new Uri(options.GetEndpointOrigin(), "/v1/"), "embeddings");
        if (actual is null ||
            !string.Equals(actual.AbsoluteUri, expected.AbsoluteUri, StringComparison.Ordinal))
        {
            response.Dispose();
            throw new SemanticEmbeddingException(
                "embedding-provider-invalid-response", retryable: false);
        }
    }

    private async Task<JsonDocument> ReadBoundedJsonAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (!string.Equals(mediaType, "application/json", StringComparison.OrdinalIgnoreCase) ||
            response.Content.Headers.ContentLength is long length &&
            length > options.MaximumResponseBytes)
            throw InvalidResponse();
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var buffer = new MemoryStream();
        var chunk = new byte[16 * 1024];
        while (true)
        {
            var read = await source.ReadAsync(chunk, cancellationToken);
            if (read == 0) break;
            if (buffer.Length + read > options.MaximumResponseBytes) throw InvalidResponse();
            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }
        try
        {
            return JsonDocument.Parse(buffer.ToArray(), new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 8
            });
        }
        catch (JsonException exception)
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-invalid-response", retryable: false, exception);
        }
    }

    private static decimal CalculateCost(int inputTokens, decimal perMillion)
    {
        if (inputTokens == 0 || perMillion == 0) return 0;
        var exact = inputTokens * perMillion / 1_000_000m;
        return Math.Ceiling(exact * 1_000_000m) / 1_000_000m;
    }

    private static byte[]? HashRequestId(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("x-request-id", out var values)) return null;
        var requestId = values.SingleOrDefault();
        return string.IsNullOrWhiteSpace(requestId) || requestId.Length > 256 ||
               requestId.Any(char.IsControl)
            ? null
            : SHA256.HashData(Encoding.UTF8.GetBytes(requestId));
    }

    private static SemanticEmbeddingException MapFailure(HttpStatusCode status) => status switch
    {
        HttpStatusCode.TooManyRequests => new(
            "embedding-provider-throttled", retryable: true),
        HttpStatusCode.RequestTimeout or HttpStatusCode.InternalServerError or
            HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or
            HttpStatusCode.GatewayTimeout => new(
                "embedding-provider-unavailable", retryable: true),
        _ => new SemanticEmbeddingException(
            "embedding-provider-unavailable", retryable: false)
    };

    private static SemanticEmbeddingException InvalidResponse() => new(
        "embedding-provider-invalid-response", retryable: false);
}

public sealed class GovernedEmbeddingServiceRouter(
    DeterministicDevelopmentEmbeddingService deterministic,
    OpenAiEmbeddingService openAi,
    bool localEnvironment) : IEmbeddingService
{
    public Task<SemanticEmbeddingGeneration> GenerateAsync(
        SemanticEmbeddingRequest request,
        CancellationToken cancellationToken)
    {
        if (string.Equals(request.ProviderCode,
                DeterministicDevelopmentEmbeddingService.ProviderCode,
                StringComparison.Ordinal))
        {
            return localEnvironment
                ? deterministic.GenerateAsync(request, cancellationToken)
                : Task.FromException<SemanticEmbeddingGeneration>(
                    new SemanticEmbeddingException(
                        "embedding-provider-unavailable",
                        retryable: false,
                        providerCallAccounting: SemanticProviderCallAccounting.NotInvoked));
        }
        if (string.Equals(request.ProviderCode, OpenAiProviderOptions.ProviderCode,
                StringComparison.Ordinal))
            return openAi.GenerateAsync(request, cancellationToken);
        return Task.FromException<SemanticEmbeddingGeneration>(
            new SemanticEmbeddingException(
                "embedding-provider-unavailable",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked));
    }
}
