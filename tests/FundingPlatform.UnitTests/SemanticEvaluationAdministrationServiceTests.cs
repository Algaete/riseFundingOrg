using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.UnitTests;

public sealed class SemanticEvaluationAdministrationServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 24, 21, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Create_hashes_idempotency_and_never_accepts_provider_from_client()
    {
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(
                true, "created", Summary(), false)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Success, result.Outcome);
        Assert.Equal(32, repository.IdempotencyHash?.Length);
        Assert.Equal(32, repository.RequestHash?.Length);
        Assert.Equal("golden-v1", repository.EvaluationSetVersion);
        Assert.Equal("local-shadow-v1", repository.ConfigurationVersion);
        Assert.True(repository.RuntimeEnabled);
    }

    [Fact]
    public async Task Disabled_runtime_is_passed_to_repository_for_replay_before_readiness()
    {
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(
                true, "replayed", Summary(), true)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: false), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Success, result.Outcome);
        Assert.True(result.Value?.WasReplay);
        Assert.False(repository.RuntimeEnabled);
    }

    [Theory]
    [InlineData("bad version", "local-shadow-v1")]
    [InlineData("golden-v1", "latest@provider")]
    [InlineData("golden-v1", "x")]
    public async Task Create_rejects_unbounded_or_ambiguous_versions(
        string evaluationSetVersion,
        string configurationVersion)
    {
        var repository = new FakeRepository();
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), evaluationSetVersion, configurationVersion,
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Invalid, result.Outcome);
        Assert.Equal(0, repository.CreateCalls);
    }

    [Theory]
    [InlineData(51601, SemanticEvaluationOutcome.Forbidden, "forbidden")]
    [InlineData(54126, SemanticEvaluationOutcome.Conflict, "idempotency-conflict")]
    [InlineData(54127, SemanticEvaluationOutcome.Invalid, "eval-set-not-ready")]
    [InlineData(54129, SemanticEvaluationOutcome.Invalid, "eval-set-not-ready")]
    public async Task Create_maps_only_allowlisted_database_outcomes(
        int databaseError,
        SemanticEvaluationOutcome expectedOutcome,
        string expectedCode)
    {
        var repository = new FakeRepository { DatabaseError = databaseError };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(expectedOutcome, result.Outcome);
        Assert.Equal(expectedCode, result.Code);
    }

    [Fact]
    public async Task Create_reports_budget_exhaustion_without_masquerading_as_an_active_run()
    {
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(
                false, "budget-insufficient", null, false)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Invalid, result.Outcome);
        Assert.Equal("budget-insufficient", result.Code);
    }

    [Fact]
    public async Task Create_maps_the_exact_active_evaluation_code_to_conflict()
    {
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(
                false, "active-evaluation-exists", null, false)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Conflict, result.Outcome);
        Assert.Equal("active-evaluation-exists", result.Code);
    }

    [Theory]
    [InlineData("eval-set-not-ready", SemanticEvaluationOutcome.Invalid)]
    [InlineData("configuration-not-approved", SemanticEvaluationOutcome.Invalid)]
    [InlineData("semantic-processing-disabled", SemanticEvaluationOutcome.Unavailable)]
    public async Task Create_maps_exact_non_success_mutation_codes(
        string code,
        SemanticEvaluationOutcome expectedOutcome)
    {
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(false, code, null, false)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0001", CancellationToken.None);

        Assert.Equal(expectedOutcome, result.Outcome);
        Assert.Equal(code, result.Code);
    }

    [Fact]
    public async Task Report_returns_only_bounded_dataset_aggregates()
    {
        var report = new SemanticEvaluationRunReport(
            Summary(),
            [new SemanticEvaluationSplitReport(
                1, 300, 285, 285, 120, 95m, .8m, .75m, .7m, .05m, .6m, 2m)]);
        var repository = new FakeRepository
        {
            Report = report
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.GetReportAsync(
            Guid.NewGuid(), report.Run.PublicId, CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Success, result.Outcome);
        var split = Assert.Single(result.Value!.Splits);
        Assert.Equal(1, split.DatasetSplit);
        Assert.Equal(95m, split.CoveragePercentage);
    }

    [Fact]
    public async Task Create_rejects_an_impossible_promotable_local_fake_summary()
    {
        var impossible = Summary() with
        {
            Status = SemanticEvaluationRunStatus.Completed,
            EvaluatedCount = 300,
            LabelledCount = 300,
            Metrics = new SemanticEvaluationMetrics(
                100m, 100m, .9m, .8m, .7m, .1m, .75m, 3m, 0m, 12, 0, true),
            StartedAtUtc = Now,
            CompletedAtUtc = Now
        };
        var repository = new FakeRepository
        {
            Mutation = new SemanticEvaluationRunMutation(
                true, "queued", impossible, false)
        };
        var service = new SemanticEvaluationAdministrationService(
            repository, Policy(enabled: true), new FixedTimeProvider(Now));

        var result = await service.CreateAsync(
            Guid.NewGuid(), "golden-v1", "local-shadow-v1",
            "stable-evaluation-key-0002", CancellationToken.None);

        Assert.Equal(SemanticEvaluationOutcome.Unavailable, result.Outcome);
        Assert.Equal("semantic-data-invalid", result.Code);
    }

    private static SemanticProcessingPolicy Policy(bool enabled) => new(
        enabled, true, 1536, 8, TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30),
        3, 8192, "matching", "project-semantic-v1", "opportunity-semantic-v1",
        "semantic-text-v1", "cosine-linear-shadow-v1");

    private static SemanticEvaluationRunSummary Summary() => new(
        Guid.NewGuid(),
        SemanticEvaluationRunStatus.Queued,
        "golden-v1",
        "local-shadow-v1",
        "development-deterministic",
        "lexical-hash-1536-v1",
        1536,
        "matching",
        "semantic-text-v1",
        30,
        100,
        300,
        0,
        0,
        0,
        new SemanticEvaluationMetrics(
            null, null, null, null, null, null, null, null, null, null, null, null),
        Now,
        null,
        null,
        null);

    private sealed class FakeRepository : ISemanticEvaluationRepository
    {
        public SemanticEvaluationRunMutation Mutation { get; init; } =
            new(false, "active-evaluation-exists", null, false);
        public int CreateCalls { get; private set; }
        public byte[]? IdempotencyHash { get; private set; }
        public byte[]? RequestHash { get; private set; }
        public string? EvaluationSetVersion { get; private set; }
        public string? ConfigurationVersion { get; private set; }
        public bool RuntimeEnabled { get; private set; }
        public int? DatabaseError { get; init; }
        public SemanticEvaluationRunReport? Report { get; init; }

        public Task<SemanticEvaluationRunMutation> CreateAsync(
            Guid adminUserPublicId,
            string evaluationSetVersion,
            string semanticConfigurationVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            bool runtimeEnabled,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            CreateCalls++;
            if (DatabaseError.HasValue)
            {
                throw new SemanticProcessingDataException(
                    "create", DatabaseError.Value, new InvalidOperationException());
            }
            EvaluationSetVersion = evaluationSetVersion;
            ConfigurationVersion = semanticConfigurationVersion;
            IdempotencyHash = idempotencyKeyHash;
            RequestHash = requestHash;
            RuntimeEnabled = runtimeEnabled;
            return Task.FromResult(Mutation);
        }

        public Task<SemanticEvaluationRunPage> ListAsync(
            Guid adminUserPublicId, int page, int pageSize,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<SemanticEvaluationRunDetail?> GetAsync(
            Guid adminUserPublicId, Guid runPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<SemanticEvaluationRunReport?> GetReportAsync(
            Guid adminUserPublicId, Guid runPublicId,
            CancellationToken cancellationToken) => Task.FromResult(Report);
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
