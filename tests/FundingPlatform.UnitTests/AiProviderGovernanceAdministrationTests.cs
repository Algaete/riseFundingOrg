using System.Security.Cryptography;
using FundingPlatform.Application.Semantics;

namespace FundingPlatform.UnitTests;

public sealed class AiProviderGovernanceAdministrationTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Policy_hash_is_stable_after_safe_canonicalization()
    {
        var repository = new RecordingRepository();
        var service = Service(repository);

        await service.RegisterEmbeddingPolicyAsync(
            Policy() with
            {
                Code = " EMBEDDINGS ",
                EndpointOrigin = "https://api.openai.com/",
                DataResidencyCode = " GLOBAL "
            },
            CancellationToken.None);
        var first = repository.PolicyRequestHash;
        await service.RegisterEmbeddingPolicyAsync(Policy(), CancellationToken.None);

        Assert.Equal(first, repository.PolicyRequestHash);
        Assert.Equal("embeddings", repository.Policy!.Code);
        Assert.Equal("https://api.openai.com", repository.Policy.EndpointOrigin);
        Assert.Equal("global", repository.Policy.DataResidencyCode);
        Assert.Equal(32, repository.PolicyIdempotencyHash!.Length);
    }

    [Fact]
    public async Task Region_endpoint_mismatch_is_rejected_before_SQL()
    {
        var repository = new RecordingRepository();
        var service = Service(repository);

        await Assert.ThrowsAsync<ArgumentException>(() =>
            service.RegisterEmbeddingPolicyAsync(
                Policy() with { DataResidencyCode = "eu" },
                CancellationToken.None));

        Assert.Equal(0, repository.PolicyCalls);
    }

    [Fact]
    public async Task Official_india_region_endpoint_is_allowlisted_exactly()
    {
        var repository = new RecordingRepository();

        await Service(repository).RegisterEmbeddingPolicyAsync(
            Policy() with
            {
                EndpointOrigin = "https://in.api.openai.com/",
                DataResidencyCode = "IN"
            },
            CancellationToken.None);

        Assert.Equal("in", repository.Policy!.DataResidencyCode);
        Assert.Equal("https://in.api.openai.com", repository.Policy.EndpointOrigin);
    }

    [Fact]
    public async Task Expired_governance_is_rejected_before_SQL()
    {
        var repository = new RecordingRepository();

        await Assert.ThrowsAsync<ArgumentException>(() =>
            Service(repository).RegisterEmbeddingPolicyAsync(
                Policy() with { ExpiresAtUtc = Now },
                CancellationToken.None));

        Assert.Equal(0, repository.PolicyCalls);
    }

    [Fact]
    public async Task Configuration_hash_binds_budget_and_exact_policy()
    {
        var repository = new RecordingRepository();
        var service = Service(repository);

        await service.PublishOpenAiConfigurationAsync(Configuration(), CancellationToken.None);
        var first = repository.ConfigurationRequestHash;
        await service.PublishOpenAiConfigurationAsync(
            Configuration() with { MonthlyBudgetUsd = 21m },
            CancellationToken.None);

        Assert.NotEqual(first, repository.ConfigurationRequestHash);
        Assert.Equal(2, repository.ConfigurationCalls);
        Assert.Equal(32, repository.ConfigurationIdempotencyHash!.Length);
    }

    [Fact]
    public async Task Structured_output_policy_binds_both_prices_and_exact_region()
    {
        var repository = new RecordingRepository();
        var command = new AiStructuredOutputProviderPolicyCommand(
            Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            " structured-output ",
            1,
            "https://eu.api.openai.com/",
            " EU ",
            SHA256.HashData("dpa"u8),
            SHA256.HashData("terms"u8),
            2.5m,
            10m,
            Now.AddDays(-1),
            Now.AddDays(90),
            "structured-policy-request-0001");

        await Service(repository).RegisterStructuredOutputPolicyAsync(
            command, CancellationToken.None);

        Assert.Equal(1, repository.StructuredPolicyCalls);
        Assert.Equal("structured-output", repository.StructuredPolicy!.Code);
        Assert.Equal("eu", repository.StructuredPolicy.DataResidencyCode);
        Assert.Equal("https://eu.api.openai.com", repository.StructuredPolicy.EndpointOrigin);
        Assert.Equal(32, repository.StructuredPolicyRequestHash!.Length);
    }

    [Fact]
    public async Task Explanation_configuration_hash_binds_output_limit_and_budget()
    {
        var repository = new RecordingRepository();
        var command = new OpenAiExplanationConfigurationCommand(
            Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            "explanation-shadow",
            1,
            512,
            0.1m,
            50m,
            "explanation-config-request-0001");

        await Service(repository).PublishOpenAiExplanationConfigurationAsync(
            command, CancellationToken.None);
        var first = repository.ExplanationConfigurationRequestHash;
        await Service(repository).PublishOpenAiExplanationConfigurationAsync(
            command with { MaximumOutputTokens = 768 }, CancellationToken.None);

        Assert.Equal(2, repository.ExplanationConfigurationCalls);
        Assert.NotEqual(first, repository.ExplanationConfigurationRequestHash);
    }

    private static AiProviderGovernanceAdministrationService Service(
        RecordingRepository repository) =>
        new(repository, new FixedTimeProvider(Now));

    private static AiEmbeddingProviderPolicyCommand Policy() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        "embeddings",
        1,
        "text-embedding-3-small",
        "https://api.openai.com",
        "global",
        SHA256.HashData("dpa"u8),
        SHA256.HashData("terms"u8),
        0.02m,
        Now.AddDays(-1),
        Now.AddDays(90),
        "governance-policy-request-0001");

    private static OpenAiSemanticConfigurationCommand Configuration() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
        "openai-shadow",
        1,
        8,
        0.001m,
        20m,
        "semantic-config-request-0001");

    private sealed class RecordingRepository : IAiProviderGovernanceAdministrationRepository
    {
        public int PolicyCalls { get; private set; }
        public AiEmbeddingProviderPolicyCommand? Policy { get; private set; }
        public byte[]? PolicyIdempotencyHash { get; private set; }
        public byte[]? PolicyRequestHash { get; private set; }
        public int ConfigurationCalls { get; private set; }
        public byte[]? ConfigurationIdempotencyHash { get; private set; }
        public byte[]? ConfigurationRequestHash { get; private set; }
        public int StructuredPolicyCalls { get; private set; }
        public AiStructuredOutputProviderPolicyCommand? StructuredPolicy { get; private set; }
        public byte[]? StructuredPolicyRequestHash { get; private set; }
        public int ExplanationConfigurationCalls { get; private set; }
        public byte[]? ExplanationConfigurationRequestHash { get; private set; }

        public Task<AiEmbeddingProviderPolicyMutation> RegisterEmbeddingPolicyAsync(
            AiEmbeddingProviderPolicyCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            PolicyCalls++;
            Policy = command;
            PolicyIdempotencyHash = idempotencyKeyHash;
            PolicyRequestHash = requestHash;
            return Task.FromResult(new AiEmbeddingProviderPolicyMutation(
                true, "published", false,
                Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                "embeddings-v1", "openai", command.ModelCode, command.EndpointOrigin,
                2, 0, command.DataResidencyCode, SHA256.HashData("policy"u8),
                command.InputTokenCostUsdPerMillion, true, true,
                command.ApprovedAtUtc, command.ExpiresAtUtc));
        }

        public Task<OpenAiSemanticConfigurationMutation> PublishOpenAiConfigurationAsync(
            OpenAiSemanticConfigurationCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            ConfigurationCalls++;
            ConfigurationIdempotencyHash = idempotencyKeyHash;
            ConfigurationRequestHash = requestHash;
            return Task.FromResult(new OpenAiSemanticConfigurationMutation(
                true, "published", false, Guid.NewGuid(), "openai-shadow-v1",
                command.ProviderPolicyPublicId, SHA256.HashData("policy"u8), "openai",
                "text-embedding-3-small", 1536, command.MaximumBatchSize,
                command.MaximumCostUsdPerEmbedding, command.MonthlyBudgetUsd, true, nowUtc));
        }

        public Task<AiStructuredOutputProviderPolicyMutation>
            RegisterStructuredOutputPolicyAsync(
                AiStructuredOutputProviderPolicyCommand command,
                byte[] idempotencyKeyHash,
                byte[] requestHash,
                DateTimeOffset nowUtc,
                CancellationToken cancellationToken)
        {
            StructuredPolicyCalls++;
            StructuredPolicy = command;
            StructuredPolicyRequestHash = requestHash;
            return Task.FromResult(new AiStructuredOutputProviderPolicyMutation(
                true, "published", false, Guid.NewGuid(), "structured-output-v1",
                "openai", "gpt-5.6-sol", 1, command.EndpointOrigin, 2, 0,
                command.DataResidencyCode, SHA256.HashData("policy"u8),
                command.InputTokenCostUsdPerMillion,
                command.OutputTokenCostUsdPerMillion,
                true, true, command.ApprovedAtUtc, command.ExpiresAtUtc));
        }

        public Task<OpenAiExplanationConfigurationMutation>
            PublishOpenAiExplanationConfigurationAsync(
                OpenAiExplanationConfigurationCommand command,
                byte[] idempotencyKeyHash,
                byte[] requestHash,
                DateTimeOffset nowUtc,
                CancellationToken cancellationToken)
        {
            ExplanationConfigurationCalls++;
            ExplanationConfigurationRequestHash = requestHash;
            return Task.FromResult(new OpenAiExplanationConfigurationMutation(
                true, "published", false, Guid.NewGuid(), "explanation-shadow-v1",
                command.ProviderPolicyPublicId, SHA256.HashData("policy"u8), "openai",
                "gpt-5.6-sol", "explanation-input-v1", "explanation-output-v1",
                "explanation-review-es-v1", SHA256.HashData("prompt"u8),
                SHA256.HashData("schema"u8), command.MaximumOutputTokens,
                command.MaximumCostUsdPerResult, command.MonthlyBudgetUsd,
                true, nowUtc));
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
