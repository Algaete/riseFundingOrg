using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Semantics;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;

namespace FundingPlatform.UnitTests;

public sealed class SemanticProcessingTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 24, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Development_embedding_is_deterministic_bounded_and_normalized()
    {
        var input = ProjectInput("Educación rural para comunidades");
        var request = Request(input);
        var service = new DeterministicDevelopmentEmbeddingService();

        var first = await service.GenerateAsync(request, CancellationToken.None);
        var second = await service.GenerateAsync(request, CancellationToken.None);

        Assert.Equal(1536, first.Vector.Length);
        Assert.Equal(first.Vector, second.Vector);
        Assert.Equal(DeterministicDevelopmentEmbeddingService.ProviderCode, first.ProviderCode);
        var norm = Math.Sqrt(first.Vector.Sum(value => (double)value * value));
        Assert.InRange(norm, .999999, 1.000001);
    }

    [Fact]
    public async Task Development_embedding_rejects_configuration_it_does_not_implement()
    {
        var input = ProjectInput("Educación");
        var request = Request(input) with { ModelCode = "client-selected-latest" };

        var exception = await Assert.ThrowsAsync<SemanticEmbeddingException>(() =>
            new DeterministicDevelopmentEmbeddingService()
                .GenerateAsync(request, CancellationToken.None));

        Assert.Equal("embedding-provider-unavailable", exception.SafeCode);
        Assert.False(exception.Retryable);
    }

    [Fact]
    public async Task Opportunity_input_uses_the_public_opportunity_template_exactly()
    {
        var input = OpportunityInput("Fondo regional de educación");
        var lease = Lease(input);
        var policy = Policy(enabled: true);

        Assert.Equal("opportunity-semantic-v1", lease.TemplateVersion);
        Assert.True(SemanticInputPolicy.TryValidate(input, lease, policy, out _));

        var generation = await new DeterministicDevelopmentEmbeddingService()
            .GenerateAsync(Request(input), CancellationToken.None);

        Assert.Equal("opportunity-semantic-v1", generation.TemplateVersion);
        Assert.Equal(1536, generation.Vector.Length);
    }

    [Fact]
    public void Canonical_input_policy_rejects_hash_drift_unknown_fields_and_pii()
    {
        var policy = Policy(enabled: true);
        var valid = ProjectInput("Educación rural");
        var lease = Lease(valid);
        Assert.True(SemanticInputPolicy.TryValidate(valid, lease, policy, out _));

        var drift = valid with { CanonicalText = valid.CanonicalText.Replace("rural", "urbana") };
        Assert.False(SemanticInputPolicy.TryValidate(drift, lease, policy, out var driftCode));
        Assert.Equal("semantic-input-hash-mismatch", driftCode);

        var pii = ProjectInput("Contacto persona@example.org");
        Assert.False(SemanticInputPolicy.TryValidate(
            pii, Lease(pii), policy, out var piiCode));
        Assert.Equal("semantic-input-privacy-rejected", piiCode);

        foreach (var privateValue in new[]
                 {
                     "RUT 12.345.678-5",
                     "Más información en https://private.example.org"
                 })
        {
            var privateInput = ProjectInput(privateValue);
            Assert.False(SemanticInputPolicy.TryValidate(
                privateInput, Lease(privateInput), policy, out var privateCode));
            Assert.Equal("semantic-input-privacy-rejected", privateCode);
        }

        var extraJson = valid.CanonicalText.Replace(
            "\"summary\"", "\"email\":null,\"summary\"");
        var extra = InputFromJson(extraJson);
        Assert.False(SemanticInputPolicy.TryValidate(extra, Lease(extra), policy, out _));

        var objectTaxonomy = InputFromJson(valid.CanonicalText.Replace(
            "\"countryIds\":[]", "\"countryIds\":[{\"id\":1}]"));
        Assert.False(SemanticInputPolicy.TryValidate(
            objectTaxonomy, Lease(objectTaxonomy), policy, out _));

        var unsortedTaxonomy = InputFromJson(valid.CanonicalText.Replace(
            "\"countryIds\":[]", "\"countryIds\":[2,1]"));
        Assert.False(SemanticInputPolicy.TryValidate(
            unsortedTaxonomy, Lease(unsortedTaxonomy), policy, out _));

        var canonicalTaxonomy = InputFromJson(valid.CanonicalText.Replace(
            "\"countryIds\":[]", "\"countryIds\":[1,2]"));
        Assert.True(SemanticInputPolicy.TryValidate(
            canonicalTaxonomy, Lease(canonicalTaxonomy), policy, out _));

        var duplicateTaxonomy = InputFromJson(valid.CanonicalText.Replace(
            "\"countryIds\":[]", "\"countryIds\":[1,1]"));
        Assert.False(SemanticInputPolicy.TryValidate(
            duplicateTaxonomy, Lease(duplicateTaxonomy), policy, out _));
    }

    [Fact]
    public async Task Disabled_processing_never_claims_or_invokes_provider()
    {
        var repository = new FakeProcessingRepository();
        var provider = new RecordingEmbeddingService();
        var service = Service(repository, provider, Policy(enabled: false));

        var result = await service.ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(0, 0, 0), result);
        Assert.Equal(0, repository.ClaimEmbeddingCalls);
        Assert.Equal(0, provider.Calls);
    }

    [Fact]
    public async Task Processing_renews_then_validates_and_completes_exact_reserved_job()
    {
        var input = ProjectInput("Educación rural");
        var lease = Lease(input);
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [lease],
            Input = input
        };
        var provider = new RecordingEmbeddingService();
        var service = Service(repository, provider, Policy(enabled: true));

        var result = await service.ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(1, 1, 0), result);
        Assert.Equal(["renew", "input", "renew", "complete"], repository.Events);
        Assert.Equal(1, provider.Calls);
        Assert.Equal(lease.BudgetReservationPublicId, repository.CompletedReservationId);
        Assert.Equal(lease.SemanticConfigurationVersion,
            Assert.Single(provider.Requests).SemanticConfigurationVersion);
    }

    [Fact]
    public async Task Lost_lease_stops_before_loading_input_or_calling_provider()
    {
        var input = ProjectInput("Educación rural");
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [Lease(input)],
            Input = input,
            Renewed = false
        };
        var provider = new RecordingEmbeddingService();

        var result = await Service(repository, provider, Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(0, result.FailedCount);
        Assert.Equal(1, result.DeferredCount);
        Assert.Equal(["renew"], repository.Events);
        Assert.Equal(0, provider.Calls);
    }

    [Fact]
    public async Task Provider_configuration_drift_is_safely_failed_and_not_persisted()
    {
        var input = ProjectInput("Educación rural");
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [Lease(input)],
            Input = input
        };
        var provider = new RecordingEmbeddingService { ReturnWrongModel = true };

        var result = await Service(repository, provider, Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(0, result.CompletedCount);
        Assert.Equal(0, result.DeferredCount);
        Assert.Equal(1, result.FailedCount);
        Assert.Null(repository.CompletedReservationId);
        Assert.Equal("embedding-provider-invalid-response", repository.FailureCode);
        Assert.Equal(
            SemanticProviderCallAccounting.ChargeUncertain,
            repository.FailureAccounting);
    }

    [Fact]
    public async Task Unsafe_input_data_error_is_pre_call_and_does_not_abort_the_batch()
    {
        var unsafeInput = ProjectInput("Contacto persona@example.org");
        var validInput = ProjectInput("Educación rural");
        var unsafeLease = Lease(unsafeInput);
        var validLease = Lease(validInput);
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [unsafeLease, validLease],
            InputsByJob = { [validLease.JobPublicId] = validInput },
            InputErrorNumbers = { [unsafeLease.JobPublicId] = 54111 }
        };
        var provider = new RecordingEmbeddingService();

        var result = await Service(repository, provider, Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(2, result.ClaimedCount);
        Assert.Equal(1, result.CompletedCount);
        Assert.Equal(1, result.FailedCount);
        Assert.Equal(1, provider.Calls);
        Assert.Equal(SemanticProviderCallAccounting.NotInvoked,
            repository.FailureAccounting);
    }

    [Fact]
    public async Task Database_terminalized_input_is_skipped_and_next_job_still_completes()
    {
        var rejectedInput = ProjectInput("Entrada rechazada por SQL");
        var validInput = ProjectInput("Educación rural");
        var rejectedLease = Lease(rejectedInput);
        var validLease = Lease(validInput);
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [rejectedLease, validLease],
            InputsByJob = { [validLease.JobPublicId] = validInput }
        };
        var provider = new RecordingEmbeddingService();

        var result = await Service(repository, provider, Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(2, result.ClaimedCount);
        Assert.Equal(1, result.CompletedCount);
        Assert.Equal(1, result.SkippedCount);
        Assert.Equal(0, result.FailedCount);
        Assert.Equal(1, provider.Calls);
    }

    [Fact]
    public async Task Provider_timeout_is_retryable_but_conservatively_charged()
    {
        var input = ProjectInput("Educación rural");
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [Lease(input)],
            Input = input
        };
        var provider = new RecordingEmbeddingService { ThrowTimeout = true };

        var result = await Service(repository, provider, Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(1, result.FailedCount);
        Assert.Equal("embedding-provider-timeout", repository.FailureCode);
        Assert.Equal(SemanticProviderCallAccounting.ChargeUncertain,
            repository.FailureAccounting);
    }

    [Theory]
    [InlineData(1, true, 1, 0)]
    [InlineData(2, false, 0, 1)]
    public async Task Ambiguous_completion_replays_once_without_mislabeling_provider_failure(
        int persistenceFailures,
        bool commitsBeforeThrow,
        int expectedCompleted,
        int expectedDeferred)
    {
        var input = ProjectInput("Educación rural");
        var repository = new FakeProcessingRepository
        {
            EmbeddingJobs = [Lease(input)],
            Input = input,
            CompletionFailuresRemaining = persistenceFailures,
            CompletionCommitsBeforeThrow = commitsBeforeThrow
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(expectedCompleted, result.CompletedCount);
        Assert.Equal(expectedDeferred, result.DeferredCount);
        Assert.Equal(0, result.FailedCount);
        Assert.Equal(2, repository.CompleteCalls);
        Assert.Equal(3, repository.Events.Count(item => item == "renew"));
        Assert.DoesNotContain("fail", repository.Events);
    }

    [Fact]
    public async Task Just_in_time_claims_respect_the_database_configuration_cycle_cap()
    {
        var inputs = Enumerable.Range(1, 3)
            .Select(index => ProjectInput($"Proyecto {index}"))
            .ToArray();
        var leases = inputs.Select(input => Lease(input) with { MaximumBatchSize = 2 })
            .ToArray();
        var repository = new FakeProcessingRepository { EmbeddingJobs = leases };
        foreach (var pair in leases.Zip(inputs))
            repository.InputsByJob[pair.First.JobPublicId] = pair.Second;

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessEmbeddingsAsync(CancellationToken.None);

        Assert.Equal(2, result.ClaimedCount);
        Assert.Equal(2, result.CompletedCount);
        Assert.Equal(2, repository.CompleteCalls);
    }

    [Fact]
    public async Task Shadow_processing_renews_and_completes_ready_corpus_server_side()
    {
        var run = ShadowRun();
        var repository = new FakeProcessingRepository
        {
            ShadowRuns = [run],
            WorkState = new SemanticShadowEvaluationWorkState(
                run.RunPublicId, run.LeaseId, 300, 300, 0, 0)
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessShadowEvaluationsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(1, 1, 0), result);
        Assert.True(repository.ShadowCompleted);
        Assert.Equal(
            ["renew-shadow", "work-shadow", "renew-shadow", "complete-shadow"],
            repository.Events);
    }

    [Fact]
    public async Task Shadow_processing_never_completes_with_missing_embeddings()
    {
        var run = ShadowRun();
        var repository = new FakeProcessingRepository
        {
            ShadowRuns = [run],
            WorkState = new SemanticShadowEvaluationWorkState(
                run.RunPublicId, run.LeaseId, 300, 299, 1, 0)
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessShadowEvaluationsAsync(CancellationToken.None);

        Assert.Equal(0, result.CompletedCount);
        Assert.Equal(0, result.FailedCount);
        Assert.Equal(1, result.DeferredCount);
        Assert.Equal("semantic-embeddings-pending", repository.FailureCode);
        Assert.False(repository.ShadowCompleted);
    }

    [Fact]
    public async Task Shadow_processing_completes_a_conservative_partial_report_after_terminal_provider_failures()
    {
        var run = ShadowRun();
        var repository = new FakeProcessingRepository
        {
            ShadowRuns = [run],
            WorkState = new SemanticShadowEvaluationWorkState(
                run.RunPublicId, run.LeaseId, 300, 285, 0, 15)
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessShadowEvaluationsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(1, 1, 0), result);
        Assert.True(repository.ShadowCompleted);
        Assert.DoesNotContain("fail-shadow", repository.Events);
    }

    [Fact]
    public async Task Shadow_completion_replays_once_after_an_ambiguous_ack()
    {
        var run = ShadowRun();
        var repository = new FakeProcessingRepository
        {
            ShadowRuns = [run],
            WorkState = new SemanticShadowEvaluationWorkState(
                run.RunPublicId, run.LeaseId, 300, 300, 0, 0),
            ShadowCompletionFailuresRemaining = 1,
            ShadowCompletionCommitsBeforeThrow = true
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessShadowEvaluationsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(1, 1, 0), result);
        Assert.Equal(2, repository.ShadowCompleteCalls);
        Assert.Equal(3, repository.Events.Count(item => item == "renew-shadow"));
        Assert.True(repository.ShadowCompleted);
    }

    [Fact]
    public async Task Missing_shadow_work_defers_without_consuming_an_attempt()
    {
        var repository = new FakeProcessingRepository
        {
            ShadowRuns = [ShadowRun()],
            WorkState = null
        };

        var result = await Service(
                repository, new RecordingEmbeddingService(), Policy(enabled: true))
            .ProcessShadowEvaluationsAsync(CancellationToken.None);

        Assert.Equal(new SemanticProcessingBatchResult(1, 0, 0, 1), result);
        Assert.DoesNotContain("fail-shadow", repository.Events);
        Assert.DoesNotContain("complete-shadow", repository.Events);
    }

    [Fact]
    public void Hosted_configuration_fails_closed_when_semantics_are_enabled()
    {
        var options = new SemanticOptions { Enabled = true };
        var hosted = new FakeHostEnvironment { EnvironmentName = Environments.Production };
        var local = new FakeHostEnvironment { EnvironmentName = Environments.Development };

        Assert.True(new SemanticWorkerOptionsValidator(hosted)
            .Validate(null, options).Failed);
        Assert.True(new SemanticWorkerOptionsValidator(local)
            .Validate(null, options).Succeeded);
        Assert.True(new SemanticOptionsValidator().Validate(null, options).Succeeded);
    }

    [Fact]
    public void Unsafe_serial_batch_lease_fails_closed_before_claiming()
    {
        var unsafePolicy = Policy(enabled: true) with
        {
            BatchSize = 8,
            LeaseDuration = TimeSpan.FromMinutes(3)
        };

        Assert.Throws<InvalidOperationException>(unsafePolicy.Validate);
    }

    private static SemanticProcessingService Service(
        FakeProcessingRepository repository,
        IEmbeddingService provider,
        SemanticProcessingPolicy policy) => new(
        repository,
        provider,
        policy,
        new FixedTimeProvider(Now),
        "semantic-unit-test");

    private static SemanticProcessingPolicy Policy(bool enabled) => new(
        enabled, true, 1536, 8, TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30),
        3, 8192, "matching", "project-semantic-v1", "opportunity-semantic-v1",
        "semantic-text-v1", "cosine-linear-shadow-v1");

    private static SemanticEmbeddingJobLease Lease(SemanticEmbeddingInput input) => new(
        input.JobPublicId,
        input.LeaseId,
        Guid.NewGuid(),
        input.SubjectType,
        input.SubjectPublicId,
        input.SubjectVersion,
        "local-shadow-v1",
        SHA256.HashData("config"u8),
        DeterministicDevelopmentEmbeddingService.ProviderCode,
        DeterministicDevelopmentEmbeddingService.ModelCode,
        1536,
        "matching",
        input.SubjectType == SemanticSubjectType.Project
            ? "project-semantic-v1"
            : "opportunity-semantic-v1",
        "semantic-text-v1",
        8192,
        8,
        3,
        1m,
        input.InputContentHash,
        1);

    private static SemanticEmbeddingRequest Request(SemanticEmbeddingInput input) => new(
        input.SubjectType,
        input.SubjectPublicId,
        input.SubjectVersion,
        "local-shadow-v1",
        SHA256.HashData("config"u8),
        DeterministicDevelopmentEmbeddingService.ProviderCode,
        DeterministicDevelopmentEmbeddingService.ModelCode,
        "matching",
        input.SubjectType == SemanticSubjectType.Project
            ? "project-semantic-v1"
            : "opportunity-semantic-v1",
        "semantic-text-v1",
        1536,
        input.CanonicalText,
        input.InputContentHash);

    private static SemanticEmbeddingInput ProjectInput(string description) => InputFromJson(
        $$"""{"schemaVersion":"semantic-input-v1","normalizationVersion":"semantic-text-v1","summary":null,"description":"{{description}}","projectStatus":1,"startDate":null,"endDate":null,"budgetTotal":null,"confirmedFunding":null,"currency":null,"countryIds":[],"regionIds":[],"categoryIds":[],"beneficiaryTypeIds":[],"projectTypeIds":[]}""");

    private static SemanticEmbeddingInput OpportunityInput(string title) => InputFromJson(
        $$"""{"schemaVersion":"semantic-input-v1","normalizationVersion":"semantic-text-v1","title":"{{title}}","description":null,"summary":null,"sponsorName":null,"currency":null,"minAmount":null,"maxAmount":null,"eligibilityDescription":null,"requirements":null,"objectives":null,"allowedActivities":null,"excludedActivities":null,"restrictions":null,"targetOrganizationsDescription":null,"targetPopulationsDescription":null,"minimumOperatingYears":null,"requiresLegalEntity":null,"requiresPriorExperience":null,"requiresCofunding":null,"cofundingPercentage":null,"geographicScope":null,"countryIds":[],"regionIds":[],"categoryIds":[],"beneficiaryTypeIds":[],"projectTypeIds":[]}""",
        SemanticSubjectType.FundingOpportunity);

    private static SemanticEmbeddingInput InputFromJson(
        string json,
        SemanticSubjectType subjectType = SemanticSubjectType.Project)
    {
        var bytes = Encoding.UTF8.GetBytes(json);
        return new SemanticEmbeddingInput(
            Guid.NewGuid(), Guid.NewGuid(), subjectType, Guid.NewGuid(),
            3, "matching", json, SHA256.HashData(bytes));
    }

    private static SemanticShadowEvaluationRunLease ShadowRun() => new(
        Guid.NewGuid(), Guid.NewGuid(), "local-shadow-v1",
        SHA256.HashData("config"u8),
        DeterministicDevelopmentEmbeddingService.ProviderCode,
        DeterministicDevelopmentEmbeddingService.ModelCode,
        "matching", "semantic-text-v1", "project-semantic-v1",
        "opportunity-semantic-v1", "cosine-linear-shadow-v1", 1, 3, 1536, 300, 1);

    private sealed class RecordingEmbeddingService : IEmbeddingService
    {
        public int Calls { get; private set; }
        public bool ReturnWrongModel { get; init; }
        public bool ThrowTimeout { get; init; }
        public List<SemanticEmbeddingRequest> Requests { get; } = [];

        public Task<SemanticEmbeddingGeneration> GenerateAsync(
            SemanticEmbeddingRequest request,
            CancellationToken cancellationToken)
        {
            Calls++;
            Requests.Add(request);
            if (ThrowTimeout) throw new OperationCanceledException();
            return Task.FromResult(new SemanticEmbeddingGeneration(
                request.ProviderCode,
                ReturnWrongModel ? "wrong-model" : request.ModelCode,
                request.TemplateVersion,
                request.Dimensions,
                Enumerable.Repeat(1f / MathF.Sqrt(request.Dimensions), request.Dimensions).ToArray(),
                10,
                null,
                0m,
                null,
                1));
        }
    }

    private sealed class FakeProcessingRepository : ISemanticProcessingRepository
    {
        public IReadOnlyList<SemanticEmbeddingJobLease> EmbeddingJobs { get; init; } = [];
        public IReadOnlyList<SemanticShadowEvaluationRunLease> ShadowRuns { get; init; } = [];
        public SemanticShadowEvaluationWorkState? WorkState { get; init; }
        public SemanticEmbeddingInput? Input { get; init; }
        public Dictionary<Guid, SemanticEmbeddingInput> InputsByJob { get; } = [];
        public Dictionary<Guid, int> InputErrorNumbers { get; } = [];
        public bool Renewed { get; init; } = true;
        public int ClaimEmbeddingCalls { get; private set; }
        public int CompleteCalls { get; private set; }
        public int CompletionFailuresRemaining { get; set; }
        public bool CompletionCommitsBeforeThrow { get; set; }
        public List<string> Events { get; } = [];
        public Guid? CompletedReservationId { get; private set; }
        public string? FailureCode { get; private set; }
        public SemanticProviderCallAccounting? FailureAccounting { get; private set; }
        public bool ShadowCompleted { get; private set; }
        public int ShadowCompleteCalls { get; private set; }
        public int ShadowCompletionFailuresRemaining { get; set; }
        public bool ShadowCompletionCommitsBeforeThrow { get; set; }
        private Queue<SemanticEmbeddingJobLease>? embeddingQueue;
        private readonly HashSet<Guid> completedEmbeddingJobs = [];

        public Task<IReadOnlyList<SemanticEmbeddingJobLease>> ClaimEmbeddingJobsAsync(
            string workerInstanceId, int batchSize, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            ClaimEmbeddingCalls++;
            embeddingQueue ??= new Queue<SemanticEmbeddingJobLease>(EmbeddingJobs);
            var claimed = new List<SemanticEmbeddingJobLease>(batchSize);
            while (claimed.Count < batchSize && embeddingQueue.TryDequeue(out var job))
                claimed.Add(job);
            return Task.FromResult<IReadOnlyList<SemanticEmbeddingJobLease>>(claimed);
        }

        public Task<SemanticEmbeddingInput?> GetEmbeddingInputAsync(
            Guid jobPublicId, Guid leaseId, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Events.Add("input");
            if (InputErrorNumbers.TryGetValue(jobPublicId, out var errorNumber))
            {
                throw new SemanticProcessingDataException(
                    "get input", errorNumber, new InvalidOperationException());
            }

            return Task.FromResult(
                InputsByJob.TryGetValue(jobPublicId, out var input) ? input : Input);
        }

        public Task<bool> RenewEmbeddingJobLeaseAsync(
            Guid jobPublicId, Guid leaseId, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            Events.Add("renew");
            return Task.FromResult(Renewed && !completedEmbeddingJobs.Contains(jobPublicId));
        }

        public Task CompleteEmbeddingJobAsync(
            Guid jobPublicId, Guid leaseId, Guid budgetReservationPublicId,
            SemanticEmbeddingGeneration generation, DateTimeOffset completedAtUtc,
            CancellationToken cancellationToken)
        {
            Events.Add("complete");
            CompleteCalls++;
            if (completedEmbeddingJobs.Contains(jobPublicId))
                return Task.CompletedTask;
            if (CompletionFailuresRemaining > 0)
            {
                CompletionFailuresRemaining--;
                if (CompletionCommitsBeforeThrow)
                {
                    CompletedReservationId = budgetReservationPublicId;
                    completedEmbeddingJobs.Add(jobPublicId);
                }
                throw new SemanticProcessingDataException(
                    "complete", -1, new InvalidOperationException());
            }
            CompletedReservationId = budgetReservationPublicId;
            completedEmbeddingJobs.Add(jobPublicId);
            return Task.CompletedTask;
        }

        public Task FailEmbeddingJobAsync(
            Guid jobPublicId, Guid leaseId, string errorCode, bool retryable,
            SemanticProviderCallAccounting providerCallAccounting,
            DateTimeOffset failedAtUtc, CancellationToken cancellationToken)
        {
            Events.Add("fail");
            FailureCode = errorCode;
            FailureAccounting = providerCallAccounting;
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<SemanticShadowEvaluationRunLease>> ClaimShadowEvaluationRunsAsync(
            string workerInstanceId, int batchSize, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult(ShadowRuns);

        public Task<bool> RenewShadowEvaluationRunLeaseAsync(
            Guid runPublicId, Guid leaseId, TimeSpan leaseDuration,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            Events.Add("renew-shadow");
            return Task.FromResult(Renewed && !ShadowCompleted);
        }

        public Task<SemanticShadowEvaluationWorkState?> GetShadowEvaluationWorkStateAsync(
            Guid runPublicId, Guid leaseId, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Events.Add("work-shadow");
            return Task.FromResult(WorkState);
        }

        public Task CompleteShadowEvaluationRunAsync(
            Guid runPublicId, Guid leaseId,
            DateTimeOffset completedAtUtc, CancellationToken cancellationToken)
        {
            Events.Add("complete-shadow");
            ShadowCompleteCalls++;
            if (ShadowCompleted)
                return Task.CompletedTask;
            if (ShadowCompletionFailuresRemaining > 0)
            {
                ShadowCompletionFailuresRemaining--;
                if (ShadowCompletionCommitsBeforeThrow)
                    ShadowCompleted = true;
                throw new SemanticProcessingDataException(
                    "complete shadow", -1, new InvalidOperationException());
            }
            ShadowCompleted = true;
            return Task.CompletedTask;
        }

        public Task ReleaseShadowEvaluationRunAsync(
            Guid runPublicId, Guid leaseId, string reasonCode,
            DateTimeOffset nextAttemptAtUtc, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Events.Add("wait-shadow");
            FailureCode = reasonCode;
            return Task.CompletedTask;
        }

        public Task FailShadowEvaluationRunAsync(
            Guid runPublicId, Guid leaseId, string errorCode, bool retryable,
            DateTimeOffset failedAtUtc, CancellationToken cancellationToken)
        {
            Events.Add("fail-shadow");
            FailureCode = errorCode;
            return Task.CompletedTask;
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class FakeHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = string.Empty;
        public string ApplicationName { get; set; } = string.Empty;
        public string ContentRootPath { get; set; } = string.Empty;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
