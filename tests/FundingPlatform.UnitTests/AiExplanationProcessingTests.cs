using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.UnitTests;

public sealed class AiExplanationProcessingTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 18, 0, 0, TimeSpan.Zero);
    private const string CanonicalInput =
        "{\"schemaVersion\":\"explanation-input-v1\",\"semanticScore\":82.50,\"cosineSimilarity\":0.65,\"semanticRank\":1,\"deterministicRank\":2,\"classification\":0,\"hardGateStatus\":0,\"compatibilityScore\":85.00,\"ruleScore\":85.00,\"evidenceCoverage\":100.00,\"rules\":[{\"ruleCode\":\"amount\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"amount.within_range\",\"warning\":false},{\"ruleCode\":\"beneficiaries\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"beneficiaries.match\",\"warning\":false},{\"ruleCode\":\"categories\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"categories.match\",\"warning\":false},{\"ruleCode\":\"geography\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"geography.global\",\"warning\":false},{\"ruleCode\":\"legal_entity\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"legal_entity.not_required\",\"warning\":false},{\"ruleCode\":\"operating_years\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"operating_years.not_required\",\"warning\":false},{\"ruleCode\":\"organization_type\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"organization_type.not_restricted\",\"warning\":false},{\"ruleCode\":\"prior_experience\",\"outcome\":0,\"dataState\":2,\"reasonCode\":\"prior_experience.not_required\",\"warning\":false},{\"ruleCode\":\"project_type\",\"outcome\":0,\"dataState\":0,\"reasonCode\":\"project_type.match\",\"warning\":false}]}";

    [Fact]
    public async Task Valid_job_renews_before_and_after_provider_and_completes()
    {
        var repository = new RecordingRepository(Lease(), Input());
        var provider = new RecordingProvider(Generation());
        var result = await Service(repository, provider).ProcessAsync(CancellationToken.None);

        Assert.Equal(1, result.ClaimedCount);
        Assert.Equal(1, result.CompletedCount);
        Assert.Equal(2, repository.RenewCalls);
        Assert.Equal(1, repository.CompleteCalls);
        Assert.Equal(1, provider.Calls);
        Assert.Empty(repository.Failures);
    }

    [Fact]
    public async Task Pre_call_governance_failure_releases_cost_as_not_invoked()
    {
        var repository = new RecordingRepository(Lease(), Input());
        var provider = new ThrowingProvider(new AiExplanationProviderException(
            "explanation-configuration-invalid",
            retryable: false,
            providerCallAccounting: SemanticProviderCallAccounting.NotInvoked));

        var result = await Service(repository, provider).ProcessAsync(CancellationToken.None);

        Assert.Equal(1, result.FailedCount);
        var failure = Assert.Single(repository.Failures);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked, failure.Accounting);
        Assert.Equal("explanation-configuration-invalid", failure.Code);
    }

    [Fact]
    public async Task Invalid_output_is_charge_uncertain_and_never_persisted()
    {
        var repository = new RecordingRepository(Lease(), Input());
        var invalid = Generation() with { Summary = "persona@example.org" };

        var result = await Service(repository, new RecordingProvider(invalid))
            .ProcessAsync(CancellationToken.None);

        Assert.Equal(1, result.FailedCount);
        Assert.Equal(0, repository.CompleteCalls);
        Assert.Equal(SemanticProviderCallAccounting.ChargeUncertain,
            Assert.Single(repository.Failures).Accounting);
    }

    [Fact]
    public async Task Non_allowlisted_input_is_rejected_before_provider_call()
    {
        const string unsafeInput =
            "{\"schemaVersion\":\"explanation-input-v1\",\"email\":\"persona@example.org\"}";
        var lease = Lease() with
        {
            InputContentHash = SHA256.HashData(Encoding.UTF8.GetBytes(unsafeInput))
        };
        var input = Input() with
        {
            CanonicalInputJson = unsafeInput,
            InputContentHash = lease.InputContentHash
        };
        var repository = new RecordingRepository(lease, input);
        var provider = new RecordingProvider(Generation());

        var result = await Service(repository, provider).ProcessAsync(CancellationToken.None);

        Assert.Equal(1, result.FailedCount);
        Assert.Equal(0, provider.Calls);
        var failure = Assert.Single(repository.Failures);
        Assert.Equal("explanation-input-invalid", failure.Code);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked, failure.Accounting);
    }

    [Fact]
    public async Task Lost_completion_ack_replays_exact_output_once()
    {
        var repository = new RecordingRepository(Lease(), Input())
        {
            ThrowFirstCompletion = true
        };

        var result = await Service(repository, new RecordingProvider(Generation()))
            .ProcessAsync(CancellationToken.None);

        Assert.Equal(1, result.CompletedCount);
        Assert.Equal(2, repository.CompleteCalls);
        Assert.Equal(3, repository.RenewCalls);
    }

    private static AiExplanationProcessingService Service(
        IAiExplanationProcessingRepository repository,
        IStructuredExplanationService provider) => new(
        repository,
        provider,
        new AiExplanationProcessingPolicy(
            true, 1, TimeSpan.FromMinutes(10), TimeSpan.FromSeconds(60)),
        new FixedTimeProvider(Now),
        "semantic-worker-test");

    private static AiExplanationJobLease Lease() => new(
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        Guid.Parse("22222222-2222-2222-2222-222222222222"),
        Guid.Parse("33333333-3333-3333-3333-333333333333"),
        Guid.Parse("44444444-4444-4444-4444-444444444444"),
        "explanation-shadow-v1",
        SHA256.HashData("configuration"u8),
        "openai",
        "gpt-5.6-sol",
        "explanation-input-v1",
        "explanation-output-v1",
        "explanation-review-es-v1",
        SHA256.HashData("prompt"u8),
        SHA256.HashData("schema"u8),
        8192,
        512,
        3,
        0.01m,
        SHA256.HashData(Encoding.UTF8.GetBytes(CanonicalInput)),
        1);

    private static AiExplanationInput Input() => new(
        Lease().JobPublicId,
        Lease().LeaseId,
        CanonicalInput,
        Lease().InputContentHash,
        new AiProviderGovernanceContext(
            Guid.Parse("55555555-5555-5555-5555-555555555555"),
            "structured-output-v1",
            SHA256.HashData("policy"u8),
            1,
            "https://api.openai.com",
            AiProviderRetentionMode.ZeroDataRetention,
            0,
            "global",
            2m,
            10m,
            Now.AddDays(-1),
            Now.AddDays(30),
            true));

    private static AiExplanationGeneration Generation()
    {
        string[] cited = ["categories", "geography"];
        const string summary = "Las señales acotadas se encuentran alineadas.";
        const string reason = "signals-aligned";
        var material = string.Join('|',
            "0",
            summary,
            reason,
            JsonSerializer.Serialize(cited),
            Convert.ToHexString(Lease().ConfigurationFingerprint));
        return new AiExplanationGeneration(
            "openai",
            "gpt-5.6-sol",
            "explanation-review-es-v1",
            "explanation-output-v1",
            AiExplanationAssessment.Aligned,
            summary,
            reason,
            cited,
            SHA256.HashData(Encoding.Unicode.GetBytes(material)),
            SHA256.HashData("request"u8),
            100,
            20,
            0.0004m,
            250);
    }

    private sealed class RecordingRepository(
        AiExplanationJobLease lease,
        AiExplanationInput input) : IAiExplanationProcessingRepository
    {
        private bool claimed;
        public int RenewCalls { get; private set; }
        public int CompleteCalls { get; private set; }
        public bool ThrowFirstCompletion { get; init; }
        public List<(string Code, SemanticProviderCallAccounting Accounting)> Failures { get; } = [];

        public Task<AiExplanationJobLease?> ClaimAsync(
            string workerInstanceId, TimeSpan leaseDuration, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            if (claimed) return Task.FromResult<AiExplanationJobLease?>(null);
            claimed = true;
            return Task.FromResult<AiExplanationJobLease?>(lease);
        }

        public Task<AiExplanationInput?> GetInputAsync(
            Guid jobPublicId, Guid leaseId, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult<AiExplanationInput?>(input);

        public Task<bool> RenewLeaseAsync(
            Guid jobPublicId, Guid leaseId, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            RenewCalls++;
            return Task.FromResult(!(ThrowFirstCompletion && CompleteCalls == 1));
        }

        public Task CompleteAsync(
            AiExplanationJobLease value, AiExplanationGeneration generation,
            DateTimeOffset completedAtUtc, CancellationToken cancellationToken)
        {
            CompleteCalls++;
            if (ThrowFirstCompletion && CompleteCalls == 1)
                throw new InvalidOperationException("lost acknowledgement");
            return Task.CompletedTask;
        }

        public Task FailAsync(
            Guid jobPublicId, Guid leaseId, string safeCode, bool retryable,
            SemanticProviderCallAccounting providerCallAccounting,
            DateTimeOffset failedAtUtc, CancellationToken cancellationToken)
        {
            Failures.Add((safeCode, providerCallAccounting));
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingProvider(AiExplanationGeneration generation)
        : IStructuredExplanationService
    {
        public int Calls { get; private set; }
        public Task<AiExplanationGeneration> GenerateAsync(
            AiStructuredExplanationRequest request, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(generation);
        }
    }

    private sealed class ThrowingProvider(AiExplanationProviderException exception)
        : IStructuredExplanationService
    {
        public Task<AiExplanationGeneration> GenerateAsync(
            AiStructuredExplanationRequest request, CancellationToken cancellationToken) =>
            Task.FromException<AiExplanationGeneration>(exception);
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
