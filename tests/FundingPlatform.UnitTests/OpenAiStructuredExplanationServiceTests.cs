using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Semantics;
using Microsoft.Extensions.Options;

namespace FundingPlatform.UnitTests;

public sealed class OpenAiStructuredExplanationServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 18, 0, 0, TimeSpan.Zero);
    private static readonly byte[] PolicyFingerprint = SHA256.HashData("structured-policy"u8);
    private const string Input =
        "{\"schemaVersion\":\"explanation-input-v1\",\"semanticScore\":82.50,\"cosineSimilarity\":0.65,\"semanticRank\":1,\"deterministicRank\":2,\"classification\":0,\"hardGateStatus\":0,\"compatibilityScore\":85.00,\"ruleScore\":85.00,\"evidenceCoverage\":100.00,\"rules\":[{\"ruleCode\":\"amount\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"amount.within_range\",\"warning\":false},{\"ruleCode\":\"beneficiaries\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"beneficiaries.match\",\"warning\":false},{\"ruleCode\":\"categories\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"categories.match\",\"warning\":false},{\"ruleCode\":\"geography\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"geography.global\",\"warning\":false},{\"ruleCode\":\"legal_entity\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"legal_entity.not_required\",\"warning\":false},{\"ruleCode\":\"operating_years\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"operating_years.not_required\",\"warning\":false},{\"ruleCode\":\"organization_type\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"organization_type.not_restricted\",\"warning\":false},{\"ruleCode\":\"prior_experience\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"prior_experience.not_required\",\"warning\":false},{\"ruleCode\":\"project_type\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"project_type.match\",\"warning\":false}]}";

    [Fact]
    public async Task Exact_structured_output_is_validated_costed_and_fingerprinted()
    {
        const string providerOutput =
            "{\"assessment\":\"aligned\",\"summary\":\"Las señales acotadas se encuentran alineadas.\",\"primaryReasonCode\":\"signals-aligned\",\"citedRuleCodes\":[\"categories\",\"geography\"]}";
        var handler = new RecordingHandler(_ => Success(providerOutput));

        var result = await Service(handler).GenerateAsync(Request(), CancellationToken.None);

        Assert.Equal(AiExplanationAssessment.Aligned, result.Assessment);
        Assert.Equal(["categories", "geography"], result.CitedRuleCodes);
        Assert.Equal(0.000400m, result.EstimatedCostUsd);
        Assert.Equal(32, result.OutputFingerprint.Length);
        Assert.Equal(32, result.ProviderRequestIdHash?.Length);
        Assert.Contains("\"store\":false", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"type\":\"json_schema\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"strict\":true", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"model\":\"gpt-5.6-sol\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains(OpenAiStructuredExplanationService.DeveloperPrompt,
            handler.Body, StringComparison.Ordinal);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal(1, handler.CallCount);
    }

    [Fact]
    public async Task Governance_mismatch_fails_before_provider_call_without_charge()
    {
        var handler = new RecordingHandler(_ =>
            throw new InvalidOperationException("provider was called"));
        var request = Request() with
        {
            ProviderGovernance = Governance() with
            {
                PolicyFingerprint = SHA256.HashData("wrong-policy"u8)
            }
        };

        var exception = await Assert.ThrowsAsync<AiExplanationProviderException>(() =>
            Service(handler).GenerateAsync(request, CancellationToken.None));

        Assert.Equal("explanation-configuration-invalid", exception.SafeCode);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked,
            exception.ProviderCallAccounting);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task Non_allowlisted_canonical_input_fails_before_provider_call()
    {
        const string unsafeInput =
            "{\"schemaVersion\":\"explanation-input-v1\",\"email\":\"persona@example.org\"}";
        var handler = new RecordingHandler(_ =>
            throw new InvalidOperationException("provider was called"));
        var request = Request() with
        {
            CanonicalInputJson = unsafeInput,
            InputContentHash = SHA256.HashData(Encoding.UTF8.GetBytes(unsafeInput))
        };

        var exception = await Assert.ThrowsAsync<AiExplanationProviderException>(() =>
            Service(handler).GenerateAsync(request, CancellationToken.None));

        Assert.Equal("explanation-configuration-invalid", exception.SafeCode);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked,
            exception.ProviderCallAccounting);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task Unsafe_summary_is_rejected_without_exposing_provider_payload()
    {
        const string providerOutput =
            "{\"assessment\":\"aligned\",\"summary\":\"Contacta persona@example.org\",\"primaryReasonCode\":\"signals-aligned\",\"citedRuleCodes\":[]}";
        var handler = new RecordingHandler(_ => Success(providerOutput));

        var exception = await Assert.ThrowsAsync<AiExplanationProviderException>(() =>
            Service(handler).GenerateAsync(Request(), CancellationToken.None));

        Assert.Equal("explanation-provider-invalid-response", exception.SafeCode);
        Assert.DoesNotContain("persona@example.org", exception.ToString(),
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Throttling_is_retryable_and_provider_body_is_not_propagated()
    {
        var handler = new RecordingHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.TooManyRequests)
            {
                Content = JsonContent.Create(new { error = "provider-secret" })
            });

        var exception = await Assert.ThrowsAsync<AiExplanationProviderException>(() =>
            Service(handler).GenerateAsync(Request(), CancellationToken.None));

        Assert.True(exception.Retryable);
        Assert.Equal("explanation-provider-throttled", exception.SafeCode);
        Assert.DoesNotContain("provider-secret", exception.ToString(), StringComparison.Ordinal);
    }

    private static OpenAiStructuredExplanationService Service(HttpMessageHandler handler) => new(
        new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.com/v1/") },
        Options.Create(OptionsValue()),
        new FixedTimeProvider(Now));

    private static OpenAiProviderOptions OptionsValue() => new()
    {
        Enabled = true,
        StructuredOutputsEnabled = true,
        EndpointOrigin = "https://api.openai.com",
        ApiKey = "secret-test-key-with-enough-length",
        ProjectId = "proj_test",
        RequiredStructuredOutputGovernancePolicySha256 =
            Convert.ToHexString(PolicyFingerprint),
        MaximumResponseBytes = 262_144
    };

    private static AiStructuredExplanationRequest Request() => new(
        "explanation-shadow-v1",
        SHA256.HashData("configuration"u8),
        "openai",
        "gpt-5.6-sol",
        "explanation-input-v1",
        "explanation-output-v1",
        "explanation-review-es-v1",
        SHA256.HashData(Encoding.Unicode.GetBytes(
            OpenAiStructuredExplanationService.DeveloperPrompt)),
        SHA256.HashData(Encoding.Unicode.GetBytes(
            OpenAiStructuredExplanationService.ResponseSchemaJson)),
        512,
        0.01m,
        Input,
        SHA256.HashData(Encoding.UTF8.GetBytes(Input)),
        Governance());

    private static AiProviderGovernanceContext Governance() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        "structured-output-v1",
        PolicyFingerprint,
        1,
        "https://api.openai.com",
        AiProviderRetentionMode.ZeroDataRetention,
        0,
        "global",
        2m,
        10m,
        Now.AddDays(-1),
        Now.AddDays(30),
        true);

    private static HttpResponseMessage Success(string outputText) => new(HttpStatusCode.OK)
    {
        Content = JsonContent.Create(new
        {
            status = "completed",
            model = "gpt-5.6-sol",
            output = new[]
            {
                new
                {
                    type = "message",
                    role = "assistant",
                    content = new[] { new { type = "output_text", text = outputText } }
                }
            },
            usage = new { input_tokens = 100, output_tokens = 20 }
        }),
        Headers = { { "x-request-id", "req_structured_123" } }
    };

    private sealed class RecordingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory) : HttpMessageHandler
    {
        public int CallCount { get; private set; }
        public string Body { get; private set; } = "";
        public string? AuthorizationScheme { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Body = request.Content is null
                ? ""
                : await request.Content.ReadAsStringAsync(cancellationToken);
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            var response = responseFactory(request);
            response.RequestMessage = request;
            return response;
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
