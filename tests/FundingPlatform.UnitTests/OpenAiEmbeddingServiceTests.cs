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

public sealed class OpenAiEmbeddingServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 15, 0, 0, TimeSpan.Zero);
    private static readonly byte[] PolicyFingerprint = SHA256.HashData("policy-v1"u8);

    [Fact]
    public async Task Governed_embedding_uses_exact_model_dimensions_and_safe_usage()
    {
        var vector = Enumerable.Range(0, 1536).Select(index => index == 0 ? 1f : 0.001f).ToArray();
        var handler = new RecordingHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new
            {
                @object = "list",
                model = "text-embedding-3-small",
                data = new[] { new { @object = "embedding", embedding = vector, index = 0 } },
                usage = new { prompt_tokens = 100, total_tokens = 100 }
            }),
            Headers = { { "x-request-id", "req_safe_123" } }
        });
        var service = Service(handler);

        var result = await service.GenerateAsync(Request(), CancellationToken.None);

        Assert.Equal("openai", result.ProviderCode);
        Assert.Equal("text-embedding-3-small", result.ModelCode);
        Assert.Equal(1536, result.Vector.Length);
        Assert.Equal(100, result.InputTokens);
        Assert.Equal(0, result.OutputTokens);
        Assert.Equal(0.000002m, result.EstimatedCostUsd);
        Assert.NotNull(result.ProviderRequestIdHash);
        Assert.Contains("\"dimensions\":1536", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"encoding_format\":\"float\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"model\":\"text-embedding-3-small\"", handler.Body,
            StringComparison.Ordinal);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal("secret-test-key-with-enough-length", handler.AuthorizationParameter);
        Assert.Equal("proj_test", handler.ProjectId);
    }

    [Fact]
    public async Task Governance_mismatch_fails_before_network_access()
    {
        var handler = new RecordingHandler(_ => throw new InvalidOperationException("network-called"));
        var request = Request() with
        {
            ProviderGovernance = Governance() with
            {
                PolicyFingerprint = SHA256.HashData("different"u8)
            }
        };

        var exception = await Assert.ThrowsAsync<SemanticEmbeddingException>(() =>
            Service(handler).GenerateAsync(request, CancellationToken.None));

        Assert.Equal("embedding-provider-unavailable", exception.SafeCode);
        Assert.False(exception.Retryable);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked,
            exception.ProviderCallAccounting);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task Throttling_is_retryable_without_exposing_provider_body()
    {
        var handler = new RecordingHandler(_ => new HttpResponseMessage(
            HttpStatusCode.TooManyRequests)
        {
            Content = JsonContent.Create(new { error = new { message = "provider secret text" } })
        });

        var exception = await Assert.ThrowsAsync<SemanticEmbeddingException>(() =>
            Service(handler).GenerateAsync(Request(), CancellationToken.None));

        Assert.Equal("embedding-provider-throttled", exception.SafeCode);
        Assert.True(exception.Retryable);
        Assert.DoesNotContain("provider secret text", exception.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void Hosted_options_require_capability_key_and_governance_fingerprint()
    {
        var invalid = new OpenAiProviderOptions
        {
            Enabled = true,
            EmbeddingsEnabled = true
        };
        Assert.True(new OpenAiProviderOptionsValidator().Validate(null, invalid).Failed);

        var valid = OptionsValue();
        Assert.True(new OpenAiProviderOptionsValidator().Validate(null, valid).Succeeded);
    }

    private static OpenAiEmbeddingService Service(HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.com/v1/")
        };
        return new OpenAiEmbeddingService(
            client,
            Options.Create(OptionsValue()),
            new FixedTimeProvider(Now));
    }

    private static OpenAiProviderOptions OptionsValue() => new()
    {
        Enabled = true,
        EmbeddingsEnabled = true,
        EndpointOrigin = "https://api.openai.com",
        ApiKey = "secret-test-key-with-enough-length",
        ProjectId = "proj_test",
        RequiredEmbeddingGovernancePolicySha256 = Convert.ToHexString(PolicyFingerprint),
        MaximumResponseBytes = 262_144
    };

    private static SemanticEmbeddingRequest Request() => new(
        SemanticSubjectType.Project,
        Guid.Parse("6cd280cb-c6b1-48e2-a400-d0157f0f4187"),
        2,
        "openai-shadow-v1",
        SHA256.HashData("config"u8),
        "openai",
        "text-embedding-3-small",
        "matching",
        "project-semantic-v1",
        "semantic-text-v1",
        1536,
        "{\"schemaVersion\":\"semantic-input-v1\"}",
        SHA256.HashData(Encoding.UTF8.GetBytes("{\"schemaVersion\":\"semantic-input-v1\"}")),
        0.01m,
        Governance());

    private static AiProviderGovernanceContext Governance() => new(
        Guid.Parse("9cce1014-029c-4460-a662-24df22eea275"),
        "openai-embedding-governance-v1",
        PolicyFingerprint,
        0,
        "https://api.openai.com",
        AiProviderRetentionMode.ZeroDataRetention,
        0,
        "global",
        0.02m,
        0m,
        Now.AddDays(-1),
        Now.AddDays(30),
        true);

    private sealed class RecordingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory) : HttpMessageHandler
    {
        public int CallCount { get; private set; }
        public string Body { get; private set; } = string.Empty;
        public string? AuthorizationScheme { get; private set; }
        public string? AuthorizationParameter { get; private set; }
        public string? ProjectId { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Body = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken);
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            ProjectId = request.Headers.TryGetValues("OpenAI-Project", out var projectIds)
                ? projectIds.SingleOrDefault()
                : null;
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
