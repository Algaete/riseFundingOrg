using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Semantics;

public sealed class OpenAiStructuredExplanationService(
    HttpClient httpClient,
    IOptions<OpenAiProviderOptions> options,
    TimeProvider timeProvider) : IStructuredExplanationService
{
    public const string RequiredModel = "gpt-5.6-sol";
    public const string RequiredPromptVersion = "explanation-review-es-v1";
    public const string RequiredInputSchemaVersion = "explanation-input-v1";
    public const string RequiredOutputSchemaVersion = "explanation-output-v1";
    public const string DeveloperPrompt =
        "Eres un auditor de compatibilidad orientativa. Usa solo el JSON provisto. No confirmes elegibilidad, no agregues hechos y no incluyas datos personales. Devuelve unicamente el esquema solicitado.";
    public const string ResponseSchemaJson =
        "{\"type\":\"object\",\"properties\":{\"assessment\":{\"type\":\"string\",\"enum\":[\"aligned\",\"conflict\",\"insufficient\"]},\"summary\":{\"type\":\"string\"},\"primaryReasonCode\":{\"type\":\"string\",\"enum\":[\"signals-aligned\",\"semantic-high-hard-gate-conflict\",\"semantic-low-structured-compatible\",\"insufficient-structured-evidence\"]},\"citedRuleCodes\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"geography\",\"organization_type\",\"legal_entity\",\"operating_years\",\"prior_experience\",\"categories\",\"beneficiaries\",\"project_type\",\"amount\"]}}},\"required\":[\"assessment\",\"summary\",\"primaryReasonCode\",\"citedRuleCodes\"],\"additionalProperties\":false}";

    private readonly OpenAiProviderOptions options = ValidateOptions(options.Value);
    private readonly HttpClient httpClient = ValidateClient(httpClient, options.Value);

    public async Task<AiExplanationGeneration> GenerateAsync(
        AiStructuredExplanationRequest request,
        CancellationToken cancellationToken)
    {
        ValidateRequest(request);
        using var schemaDocument = JsonDocument.Parse(ResponseSchemaJson);
        var stopwatch = Stopwatch.StartNew();
        using var message = new HttpRequestMessage(HttpMethod.Post, "responses");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);
        if (!string.IsNullOrWhiteSpace(options.ProjectId))
            message.Headers.TryAddWithoutValidation("OpenAI-Project", options.ProjectId);
        message.Content = JsonContent.Create(new
        {
            model = request.ModelCode,
            store = false,
            input = new object[]
            {
                new
                {
                    role = "developer",
                    content = new[] { new { type = "input_text", text = DeveloperPrompt } }
                },
                new
                {
                    role = "user",
                    content = new[] { new { type = "input_text", text = request.CanonicalInputJson } }
                }
            },
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = "funding_compatibility_shadow_explanation",
                    strict = true,
                    schema = schemaDocument.RootElement.Clone()
                }
            },
            max_output_tokens = request.MaximumOutputTokens
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
            throw new AiExplanationProviderException(
                "explanation-provider-unavailable", retryable: true, exception);
        }

        using (response)
        {
            ValidateResponseOrigin(response);
            if (!response.IsSuccessStatusCode) throw MapFailure(response.StatusCode);
            using var document = await ReadBoundedJsonAsync(response, cancellationToken);
            var root = document.RootElement;
            if (!root.TryGetProperty("status", out var status) ||
                status.GetString() != "completed" ||
                !root.TryGetProperty("model", out var model) ||
                !string.Equals(model.GetString(), request.ModelCode, StringComparison.Ordinal) ||
                !TryReadOutputText(root, out var outputText) ||
                !TryReadUsage(root, out var inputTokens, out var outputTokens))
                throw InvalidResponse();
            if (outputTokens > request.MaximumOutputTokens) throw InvalidResponse();

            OutputPayload? output;
            try
            {
                output = JsonSerializer.Deserialize<OutputPayload>(outputText!, JsonOptions);
            }
            catch (JsonException exception)
            {
                throw new AiExplanationProviderException(
                    "explanation-provider-invalid-response", retryable: false, exception);
            }
            if (output is null || !TryMapAssessment(output.Assessment, out var assessment))
                throw InvalidResponse();
            var cited = output.CitedRuleCodes?
                .Order(StringComparer.Ordinal)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            if (!AiExplanationOutputPolicy.IsSafe(
                    assessment,
                    output.Summary,
                    output.PrimaryReasonCode,
                    cited))
                throw InvalidResponse();

            var cost = CalculateCost(
                inputTokens,
                outputTokens,
                request.ProviderGovernance.InputTokenCostUsdPerMillion,
                request.ProviderGovernance.OutputTokenCostUsdPerMillion);
            if (cost is < 0.000001m || cost > request.MaximumCostUsd)
                throw InvalidResponse();
            stopwatch.Stop();
            var material = string.Join('|',
                ((byte)assessment).ToString(CultureInfo.InvariantCulture),
                output.Summary,
                output.PrimaryReasonCode,
                JsonSerializer.Serialize(cited),
                Convert.ToHexString(request.ConfigurationFingerprint));
            return new AiExplanationGeneration(
                OpenAiProviderOptions.ProviderCode,
                request.ModelCode,
                request.PromptVersion,
                request.OutputSchemaVersion,
                assessment,
                output.Summary!,
                output.PrimaryReasonCode!,
                cited!,
                SHA256.HashData(Encoding.Unicode.GetBytes(material)),
                HashRequestId(response),
                inputTokens,
                outputTokens,
                cost,
                checked((int)Math.Min(stopwatch.ElapsedMilliseconds, int.MaxValue)));
        }
    }

    private void ValidateRequest(AiStructuredExplanationRequest request)
    {
        var now = timeProvider.GetUtcNow();
        var utf8 = Encoding.UTF8.GetBytes(request.CanonicalInputJson);
        var governance = request.ProviderGovernance;
        if (!options.Enabled || !options.StructuredOutputsEnabled ||
            request.ProviderCode != OpenAiProviderOptions.ProviderCode ||
            request.ModelCode != RequiredModel ||
            request.InputSchemaVersion != RequiredInputSchemaVersion ||
            request.OutputSchemaVersion != RequiredOutputSchemaVersion ||
            request.PromptVersion != RequiredPromptVersion ||
            request.ConfigurationFingerprint is not { Length: 32 } ||
            request.PromptFingerprint is not { Length: 32 } ||
            request.ResponseSchemaFingerprint is not { Length: 32 } ||
            request.InputContentHash is not { Length: 32 } ||
            !CryptographicOperations.FixedTimeEquals(
                request.PromptFingerprint,
                SHA256.HashData(Encoding.Unicode.GetBytes(DeveloperPrompt))) ||
            !CryptographicOperations.FixedTimeEquals(
                request.ResponseSchemaFingerprint,
                SHA256.HashData(Encoding.Unicode.GetBytes(ResponseSchemaJson))) ||
            !CryptographicOperations.FixedTimeEquals(
                request.InputContentHash,
                SHA256.HashData(utf8)) ||
            utf8.Length is < 2 or > 8192 ||
            !AiExplanationInputPolicy.IsCanonicalAndSafe(request.CanonicalInputJson) ||
            request.MaximumOutputTokens is < 128 or > 1024 ||
            request.MaximumCostUsd is < 0.000001m or > 1m ||
            governance.PolicyPublicId == Guid.Empty ||
            governance.PolicyFingerprint is not { Length: 32 } ||
            governance.Capability != 1 ||
            !CryptographicOperations.FixedTimeEquals(
                governance.PolicyFingerprint,
                options.GetRequiredStructuredOutputGovernanceFingerprint()) ||
            governance.EndpointOrigin !=
                options.GetEndpointOrigin().GetLeftPart(UriPartial.Authority) ||
            governance.RetentionMode != AiProviderRetentionMode.ZeroDataRetention ||
            governance.MaximumProviderRetentionDays != 0 ||
            governance.InputTokenCostUsdPerMillion is <= 0 or > 1000 ||
            governance.OutputTokenCostUsdPerMillion is <= 0 or > 1000 ||
            !governance.ExternalProcessingAllowed ||
            governance.ApprovedAtUtc > now || governance.ExpiresAtUtc <= now)
        {
            throw new AiExplanationProviderException(
                "explanation-configuration-invalid",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked);
        }
    }

    private static bool TryReadOutputText(JsonElement root, out string? text)
    {
        text = null;
        if (!root.TryGetProperty("output", out var output) ||
            output.ValueKind != JsonValueKind.Array)
            return false;
        var texts = new List<string>();
        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("type", out var type) || type.GetString() != "message" ||
                !item.TryGetProperty("role", out var role) || role.GetString() != "assistant" ||
                !item.TryGetProperty("content", out var content) ||
                content.ValueKind != JsonValueKind.Array)
                continue;
            foreach (var part in content.EnumerateArray())
            {
                if (part.TryGetProperty("type", out var partType) &&
                    partType.GetString() == "output_text" &&
                    part.TryGetProperty("text", out var textElement) &&
                    textElement.ValueKind == JsonValueKind.String)
                    texts.Add(textElement.GetString()!);
            }
        }
        if (texts.Count != 1 || string.IsNullOrWhiteSpace(texts[0])) return false;
        text = texts[0];
        return true;
    }

    private static bool TryReadUsage(
        JsonElement root,
        out int inputTokens,
        out int outputTokens)
    {
        inputTokens = outputTokens = -1;
        return root.TryGetProperty("usage", out var usage) &&
               usage.TryGetProperty("input_tokens", out var input) &&
               input.TryGetInt32(out inputTokens) && inputTokens is >= 0 and <= 8192 &&
               usage.TryGetProperty("output_tokens", out var output) &&
               output.TryGetInt32(out outputTokens) && outputTokens >= 0;
    }

    private static bool TryMapAssessment(
        string? value,
        out AiExplanationAssessment assessment)
    {
        assessment = value switch
        {
            "aligned" => AiExplanationAssessment.Aligned,
            "conflict" => AiExplanationAssessment.Conflict,
            "insufficient" => AiExplanationAssessment.Insufficient,
            _ => (AiExplanationAssessment)byte.MaxValue
        };
        return Enum.IsDefined(assessment);
    }

    private async Task<JsonDocument> ReadBoundedJsonAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(response.Content.Headers.ContentType?.MediaType,
                "application/json", StringComparison.OrdinalIgnoreCase) ||
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
                MaxDepth = 12
            });
        }
        catch (JsonException exception)
        {
            throw new AiExplanationProviderException(
                "explanation-provider-invalid-response", retryable: false, exception);
        }
    }

    private void ValidateResponseOrigin(HttpResponseMessage response)
    {
        var actual = response.RequestMessage?.RequestUri;
        var expected = new Uri(new Uri(options.GetEndpointOrigin(), "/v1/"), "responses");
        if (actual is null || actual.AbsoluteUri != expected.AbsoluteUri)
            throw InvalidResponse();
    }

    private static decimal CalculateCost(
        int inputTokens,
        int outputTokens,
        decimal inputPerMillion,
        decimal outputPerMillion)
    {
        var exact =
            (inputTokens * inputPerMillion + outputTokens * outputPerMillion) / 1_000_000m;
        return Math.Ceiling(exact * 1_000_000m) / 1_000_000m;
    }

    private static byte[]? HashRequestId(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("x-request-id", out var values)) return null;
        var value = values.SingleOrDefault();
        return string.IsNullOrWhiteSpace(value) || value.Length > 256 ||
               value.Any(char.IsControl)
            ? null
            : SHA256.HashData(Encoding.UTF8.GetBytes(value));
    }

    private static OpenAiProviderOptions ValidateOptions(OpenAiProviderOptions value)
    {
        var validation = new OpenAiProviderOptionsValidator().Validate(null, value);
        if (validation.Failed) throw new InvalidOperationException(validation.FailureMessage);
        return value;
    }

    private static HttpClient ValidateClient(HttpClient client, OpenAiProviderOptions options)
    {
        var expected = new Uri(options.GetEndpointOrigin(), "/v1/");
        if (client.BaseAddress is null || client.BaseAddress.AbsoluteUri != expected.AbsoluteUri)
            throw new InvalidOperationException("OpenAI HttpClient base address is not allowlisted.");
        return client;
    }

    private static AiExplanationProviderException MapFailure(HttpStatusCode status) =>
        status switch
        {
            HttpStatusCode.TooManyRequests =>
                new("explanation-provider-throttled", retryable: true),
            HttpStatusCode.RequestTimeout or HttpStatusCode.InternalServerError or
                HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or
                HttpStatusCode.GatewayTimeout =>
                new("explanation-provider-unavailable", retryable: true),
            _ => new("explanation-provider-unavailable", retryable: false)
        };

    private static AiExplanationProviderException InvalidResponse() =>
        new("explanation-provider-invalid-response", retryable: false);

    private sealed class OutputPayload
    {
        [JsonPropertyName("assessment")]
        public string? Assessment { get; init; }
        [JsonPropertyName("summary")]
        public string? Summary { get; init; }
        [JsonPropertyName("primaryReasonCode")]
        public string? PrimaryReasonCode { get; init; }
        [JsonPropertyName("citedRuleCodes")]
        public string[]? CitedRuleCodes { get; init; }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
}
