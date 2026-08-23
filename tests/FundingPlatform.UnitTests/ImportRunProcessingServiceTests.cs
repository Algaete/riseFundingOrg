using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.UnitTests;

public sealed class ImportRunProcessingServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 15, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Create_manual_run_hashes_idempotency_material_and_returns_replay()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId)
        {
            CreateMutation = new ImportRunCreateMutation(
                true,
                "replayed",
                new ImportRunAccepted(
                    runId, 1, "Grants.gov", ImportRunStatus.Queued, Now, true))
        };
        var service = new ImportRunService(repository);

        var result = await service.CreateManualAsync(
            Guid.NewGuid(),
            1,
            " nonprofit ",
            10,
            "stable-import-key-0001",
            "trace:abc-123",
            CancellationToken.None);

        Assert.Equal(ImportRunOutcome.Success, result.Outcome);
        Assert.True(result.Value?.WasReplay);
        Assert.Equal("nonprofit", repository.CreatedKeyword);
        Assert.Equal(32, repository.IdempotencyHash?.Length);
        Assert.Equal(32, repository.RequestHash?.Length);
        Assert.Equal("trace:abc-123", repository.CorrelationId);
    }

    [Fact]
    public async Task Create_manual_run_rejects_invalid_input_before_persistence()
    {
        var repository = new FakeImportRunRepository(Guid.NewGuid());
        var service = new ImportRunService(repository);

        var result = await service.CreateManualAsync(
            Guid.Empty, 0, "x", 26, "short", "email@example.org",
            CancellationToken.None);

        Assert.Equal(ImportRunOutcome.Invalid, result.Outcome);
        Assert.NotNull(result.Errors);
        Assert.False(repository.CreateWasCalled);
        Assert.Contains("correlationId", result.Errors.Keys);
    }

    [Fact]
    public void Semantic_fingerprint_ignores_observation_time_but_detects_content_changes()
    {
        var original = CreateObservation("semantic").Opportunity;
        var later = original with { RetrievedAtUtc = original.RetrievedAtUtc.AddHours(3) };
        var changed = later with { Title = later.Title + " updated" };

        var originalHash = FundingOpportunitySnapshotSerializer.ComputeSemanticHash(original);
        var laterHash = FundingOpportunitySnapshotSerializer.ComputeSemanticHash(later);
        var changedHash = FundingOpportunitySnapshotSerializer.ComputeSemanticHash(changed);

        Assert.Equal(originalHash, laterHash);
        Assert.NotEqual(originalHash, changedHash);
    }

    [Fact]
    public async Task Process_persists_raw_before_staging_and_completes_without_publishing()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(CreateObservation("one"), CreateObservation("two"));
        var opportunities = new FakeOpportunityRepository(
            FundingOpportunityUpsertOutcome.Created,
            FundingOpportunityUpsertOutcome.Unchanged);
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, result.Outcome);
        Assert.Equal(2, result.ProcessedCount);
        Assert.Equal(0, result.FailedCount);
        Assert.True(repository.RunCompleted);
        Assert.Equal(
            ["raw:one", "raw:two", "stage:one", "stage:two", "run:complete"],
            repository.Events);
        Assert.All(opportunities.Received, item =>
            Assert.Equal("grants-gov", item.ProviderCode));
        Assert.All(opportunities.ReceivedSourceIds, sourceId => Assert.Equal(1, sourceId));
        Assert.All(opportunities.ReceivedProviderCodes, providerCode =>
            Assert.Equal("grants-gov", providerCode));
    }

    [Fact]
    public async Task Process_stages_only_against_the_claimed_source_identity()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId, fundingSourceId: 42);
        var provider = new FakeProvider(
            "A renamed display label that must never become a new source",
            CreateObservation("claimed-source"));
        var opportunities = new FakeOpportunityRepository();
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, result.Outcome);
        Assert.Equal([42], opportunities.ReceivedSourceIds);
        Assert.Equal(["grants-gov"], opportunities.ReceivedProviderCodes);
        Assert.Single(opportunities.Received);
    }

    [Fact]
    public async Task Process_reuses_duplicate_raw_and_does_not_stage_it_twice()
    {
        var runId = Guid.NewGuid();
        var observation = CreateObservation("same");
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(observation, observation);
        var opportunities = new FakeOpportunityRepository(
            FundingOpportunityUpsertOutcome.Created);
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, result.Outcome);
        Assert.Equal(2, result.ProcessedCount);
        Assert.Single(opportunities.Received);
        Assert.Equal(2, repository.RawRecordCalls);
        Assert.Equal(1, repository.CompletedItemCount);
    }

    [Fact]
    public async Task Process_preserves_raw_and_retries_run_when_editorial_staging_fails()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(CreateObservation("ok"), CreateObservation("bad"));
        var opportunities = new FakeOpportunityRepository(
            FundingOpportunityUpsertOutcome.Created,
            new InvalidOperationException("database detail must not escape"));
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, result.Outcome);
        Assert.Equal("editorial-staging-failed", result.Code);
        Assert.Equal(1, result.ProcessedCount);
        Assert.Equal(1, result.FailedCount);
        Assert.Equal("editorial-staging-failed", repository.RunFailureCode);
        Assert.DoesNotContain("database detail", repository.RunFailureMessage);
        Assert.False(repository.RunCompleted);
    }

    [Fact]
    public async Task Stage_failure_after_fetch_leaves_the_entire_window_durable_for_retry()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var fetchCount = 0;
        var provider = new FakeProvider(_ =>
        {
            fetchCount++;
            IReadOnlyList<FundingSourceObservation> result = fetchCount == 1
                ? [
                    CreateObservation("durable-1"),
                    CreateObservation("durable-2"),
                    CreateObservation("durable-3")
                ]
                : [];
            return Task.FromResult(result);
        });
        var opportunities = new FakeOpportunityRepository(
            new InvalidOperationException("first staging attempt failed"));
        var service = CreateService(repository, provider, opportunities);

        var first = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, first.Outcome);
        Assert.Equal("editorial-staging-failed", first.Code);
        Assert.Equal(3, repository.DurableObservationCount);
        Assert.Equal(3, repository.RawRecordCalls);
        Assert.Equal(
            ["raw:durable-1", "raw:durable-2", "raw:durable-3"],
            repository.Events);

        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Equal(3, retry.ProcessedCount);
        Assert.Equal(2, fetchCount);
        Assert.Equal(3, repository.RawRecordCalls);
        Assert.Equal(3, repository.CompletedItemCount);
        Assert.True(repository.RunCompleted);
    }

    [Fact]
    public async Task Stage_retry_reuses_durable_raw_and_completes_on_the_next_attempt()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(CreateObservation("retry-stage"));
        var opportunities = new FakeOpportunityRepository(
            new InvalidOperationException("temporary database failure"),
            FundingOpportunityUpsertOutcome.Created);
        var service = CreateService(repository, provider, opportunities);

        var first = await service.ProcessAsync(runId, CancellationToken.None);
        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, first.Outcome);
        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Equal(1, repository.RawRecordCalls);
        Assert.Equal(2, opportunities.Received.Count);
        Assert.Equal(1, repository.CompletedItemCount);
        Assert.True(repository.RunCompleted);
    }

    [Fact]
    public async Task Retry_after_crash_reuses_completed_item_and_finishes_run()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId)
        {
            ThrowOnFirstRunCompletion = true
        };
        var provider = new FakeProvider(CreateObservation("retry"));
        var opportunities = new FakeOpportunityRepository(
            FundingOpportunityUpsertOutcome.Created);
        var service = CreateService(repository, provider, opportunities);

        await Assert.ThrowsAsync<SimulatedCrashException>(() =>
            service.ProcessAsync(runId, CancellationToken.None));
        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Single(opportunities.Received);
        Assert.Equal(2, repository.RawRecordCalls);
        Assert.Equal(2, repository.RunCompletionCalls);
        Assert.True(repository.RunCompleted);
    }

    [Fact]
    public async Task Abort_after_raw_record_replays_the_same_item_before_staging()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        using var abortedAttempt = new CancellationTokenSource();
        var opportunities = new AbortOnceOpportunityRepository(abortedAttempt);
        var service = CreateService(
            repository,
            new FakeProvider(CreateObservation("raw-before-crash")),
            opportunities);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            service.ProcessAsync(runId, abortedAttempt.Token));
        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Equal(1, repository.RawRecordCalls);
        Assert.Equal(2, opportunities.Attempts);
        Assert.Equal(1, repository.CompletedItemCount);
        Assert.True(repository.RunCompleted);
    }

    [Fact]
    public async Task Unknown_provider_fails_run_with_safe_code()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId, providerCode: "unknown-provider");
        var provider = new FakeProvider();
        var opportunities = new FakeOpportunityRepository();
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, result.Outcome);
        Assert.Equal("provider-not-allowlisted", result.Code);
        Assert.Equal("provider-not-allowlisted", repository.RunFailureCode);
        Assert.Empty(opportunities.Received);
    }

    [Fact]
    public async Task Retry_stages_durable_pending_snapshot_when_provider_no_longer_returns_item()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var fetchCount = 0;
        var provider = new FakeProvider(_ =>
        {
            fetchCount++;
            IReadOnlyList<FundingSourceObservation> result = fetchCount == 1
                ? [CreateObservation("dropped-from-provider")]
                : [];
            return Task.FromResult(result);
        });
        var opportunities = new FakeOpportunityRepository(
            new InvalidOperationException("transient staging failure"),
            FundingOpportunityUpsertOutcome.Created);
        var service = CreateService(repository, provider, opportunities);

        var first = await service.ProcessAsync(runId, CancellationToken.None);
        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, first.Outcome);
        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Equal(2, fetchCount);
        Assert.Equal(1, repository.RawRecordCalls);
        Assert.Equal(2, opportunities.Received.Count);
        Assert.True(repository.RunCompleted);
    }

    [Fact]
    public async Task Partial_retry_refetches_full_window_and_fills_remaining_durable_slots()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var fetchCount = 0;
        var provider = new FakeProvider(_ =>
        {
            fetchCount++;
            var count = fetchCount == 1 ? 10 : 25;
            return Task.FromResult<IReadOnlyList<FundingSourceObservation>>(
                Enumerable.Range(1, count)
                    .Select(number => CreateObservation($"window-{number}"))
                    .ToArray());
        });
        var initialOutcomes = Enumerable.Repeat<object>(
                FundingOpportunityUpsertOutcome.Created, 9)
            .Append(new InvalidOperationException("item ten failed transiently"))
            .ToArray();
        var opportunities = new FakeOpportunityRepository(initialOutcomes);
        var service = CreateService(repository, provider, opportunities);

        var first = await service.ProcessAsync(runId, CancellationToken.None);
        var retry = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, first.Outcome);
        Assert.Equal(ImportRunProcessingOutcome.Completed, retry.Outcome);
        Assert.Equal(25, retry.ProcessedCount);
        Assert.Equal(25, repository.DurableObservationCount);
        Assert.Equal(25, repository.CompletedItemCount);
        Assert.Equal(2, fetchCount);
    }

    [Fact]
    public async Task Unknown_or_terminal_run_message_is_idempotently_ignored()
    {
        var repository = new FakeImportRunRepository(Guid.NewGuid());
        var service = CreateService(
            repository, new FakeProvider(), new FakeOpportunityRepository());

        var result = await service.ProcessAsync(Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Ignored, result.Outcome);
        Assert.Equal("not-claimable", result.Code);
        Assert.False(repository.RunCompleted);
        Assert.Null(repository.RunFailureCode);
    }

    [Fact]
    public async Task Unsupported_provider_terminal_claim_is_acknowledged_as_failed()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId)
        {
            ClaimFailureCode = "provider-not-supported"
        };
        var service = CreateService(
            repository, new FakeProvider(), new FakeOpportunityRepository());

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, result.Outcome);
        Assert.Equal("provider-not-supported", result.Code);
        Assert.False(repository.RunCompleted);
    }

    [Fact]
    public async Task Policy_changed_terminal_claim_does_not_fetch_or_stage()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId)
        {
            ClaimFailureCode = "policy-changed"
        };
        var providerCalls = 0;
        var provider = new FakeProvider(_ =>
        {
            providerCalls++;
            return Task.FromResult<IReadOnlyList<FundingSourceObservation>>([]);
        });
        var opportunities = new FakeOpportunityRepository();
        var service = CreateService(repository, provider, opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, result.Outcome);
        Assert.Equal("policy-changed", result.Code);
        Assert.Equal(0, providerCalls);
        Assert.Empty(opportunities.Received);
        Assert.False(repository.RunCompleted);
    }

    [Fact]
    public async Task Invalid_raw_hash_fails_before_staging()
    {
        var runId = Guid.NewGuid();
        var valid = CreateObservation("tampered");
        var invalid = valid with { ContentHash = new byte[32] };
        var repository = new FakeImportRunRepository(runId);
        var opportunities = new FakeOpportunityRepository();
        var service = CreateService(
            repository, new FakeProvider(invalid), opportunities);

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Failed, result.Outcome);
        Assert.Equal("raw-content-hash-mismatch", result.Code);
        Assert.Empty(opportunities.Received);
        Assert.False(repository.RunCompleted);
    }

    [Fact]
    public async Task Cancellation_is_propagated_without_marking_run_failed()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(fetch: async cancellationToken =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return [];
        });
        var service = CreateService(repository, provider, new FakeOpportunityRepository());
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            service.ProcessAsync(runId, cancellation.Token));

        Assert.Null(repository.RunFailureCode);
        Assert.False(repository.RunCompleted);
    }

    [Fact]
    public async Task Processing_renews_its_lease_while_the_provider_is_busy()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId);
        var provider = new FakeProvider(async cancellationToken =>
        {
            await repository.FirstLeaseRenewal.Task.WaitAsync(
                TimeSpan.FromSeconds(2), cancellationToken);
            return [CreateObservation("heartbeat")];
        });
        var service = CreateService(
            repository,
            provider,
            new FakeOpportunityRepository(FundingOpportunityUpsertOutcome.Created),
            TimeProvider.System,
            TimeSpan.FromMilliseconds(10));

        var result = await service.ProcessAsync(runId, CancellationToken.None);

        Assert.Equal(ImportRunProcessingOutcome.Completed, result.Outcome);
        Assert.True(repository.LeaseRenewalCalls >= 1);
    }

    [Fact]
    public async Task Processing_stops_safely_when_lease_renewal_is_rejected()
    {
        var runId = Guid.NewGuid();
        var repository = new FakeImportRunRepository(runId)
        {
            LeaseRenewalSucceeds = false
        };
        var provider = new FakeProvider(async cancellationToken =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return [];
        });
        var service = CreateService(
            repository,
            provider,
            new FakeOpportunityRepository(),
            TimeProvider.System,
            TimeSpan.FromMilliseconds(10));

        var exception = await Assert.ThrowsAsync<ImportRunLeaseLostException>(() =>
            service.ProcessAsync(runId, CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(2)));

        Assert.Equal(runId, exception.RunId);
        Assert.Equal("lease-lost", exception.Code);
        Assert.Null(repository.RunFailureCode);
        Assert.False(repository.RunCompleted);
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-json")]
    [InlineData("{}")]
    [InlineData("{\"runId\":\"00000000-0000-0000-0000-000000000000\",\"version\":1}")]
    [InlineData("{\"runId\":\"507ff6bd-d1f5-4fb1-908f-5d6257116cdc\",\"version\":2}")]
    [InlineData("{\"runId\":\"507ff6bd-d1f5-4fb1-908f-5d6257116cdc\",\"version\":1,\"payload\":\"secret\"}")]
    [InlineData("{\"runId\":\"507ff6bd-d1f5-4fb1-908f-5d6257116cdc\",\"runId\":\"507ff6bd-d1f5-4fb1-908f-5d6257116cdc\",\"version\":1}")]
    public void Queue_parser_rejects_malformed_or_unknown_messages(string payload)
    {
        Assert.False(ImportQueueMessageParser.TryParse(payload, out _));
    }

    [Fact]
    public void Queue_parser_accepts_only_id_and_supported_version()
    {
        var runId = Guid.NewGuid();

        var parsed = ImportQueueMessageParser.TryParse(
            $"{{\"runId\":\"{runId:D}\",\"version\":1}}", out var message);

        Assert.True(parsed);
        Assert.Equal(runId, message.RunId);
        Assert.Equal(1, message.Version);
    }

    private static ImportRunProcessingService CreateService(
        FakeImportRunRepository repository,
        IFundingSourceProvider provider,
        IFundingOpportunityRepository opportunities,
        TimeProvider? timeProvider = null,
        TimeSpan? leaseRenewalInterval = null)
    {
        var registry = new FundingSourceProviderRegistry(
            [provider], ["grants-gov"]);
        return new ImportRunProcessingService(
            repository,
            registry,
            opportunities,
            timeProvider ?? new FixedTimeProvider(Now),
            TimeSpan.FromMinutes(5),
            leaseRenewalInterval);
    }

    private static FundingSourceObservation CreateObservation(string externalId)
    {
        var sourceUrl = $"https://www.grants.gov/search-results-detail/{externalId}";
        var raw = $"{{\"data\":{{\"id\":\"{externalId}\"}},\"errorcode\":0}}";
        var opportunity = new ExternalFundingOpportunity(
            "grants-gov",
            externalId,
            $"REF-{externalId}",
            $"Opportunity {externalId}",
            "Agency",
            "Description",
            "Eligibility",
            "Grant",
            "Health",
            new DateOnly(2026, 8, 22),
            new DateOnly(2026, 9, 22),
            1000,
            5000,
            false,
            sourceUrl,
            sourceUrl,
            Now);
        return new FundingSourceObservation(
            externalId,
            sourceUrl,
            raw,
            SHA256.HashData(Encoding.UTF8.GetBytes(raw)),
            Now,
            opportunity);
    }

    private sealed class FakeProvider : IFundingSourceProvider
    {
        private readonly Func<CancellationToken, Task<IReadOnlyList<FundingSourceObservation>>> fetch;

        public FakeProvider(params FundingSourceObservation[] observations)
            : this(_ => Task.FromResult<IReadOnlyList<FundingSourceObservation>>(observations))
        {
        }

        public FakeProvider(
            string sourceName,
            params FundingSourceObservation[] observations)
            : this(observations)
        {
            Source = Source with { Name = sourceName };
        }

        public FakeProvider(
            Func<CancellationToken, Task<IReadOnlyList<FundingSourceObservation>>> fetch)
        {
            this.fetch = fetch;
        }

        public FundingSourceDescriptor Source { get; } = new(
            "grants-gov", "Grants.gov", 1,
            "https://api.grants.gov/v1/api/",
            "https://www.grants.gov/api/terms-conditions",
            "0 0 11 * * *", 1, "FundingPlatform-Tests/1.0");

        public Task<IReadOnlyList<FundingSourceObservation>> FetchOpenAsync(
            string keyword,
            int maximumResults,
            GovernedAcquisitionContext governance,
            CancellationToken cancellationToken) => fetch(cancellationToken);
    }

    private sealed class FakeOpportunityRepository(params object[] outcomes)
        : IFundingOpportunityRepository
    {
        private int index;
        public List<ExternalFundingOpportunity> Received { get; } = [];
        public List<int> ReceivedSourceIds { get; } = [];
        public List<string> ReceivedProviderCodes { get; } = [];

        public Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
            int expectedFundingSourceId,
            string expectedProviderCode,
            ExternalFundingOpportunity opportunity,
            CancellationToken cancellationToken)
        {
            Received.Add(opportunity);
            ReceivedSourceIds.Add(expectedFundingSourceId);
            ReceivedProviderCodes.Add(expectedProviderCode);
            var result = outcomes.Length == 0 || index >= outcomes.Length
                ? FundingOpportunityUpsertOutcome.Created
                : outcomes[index++];
            return result is Exception exception
                ? Task.FromException<FundingOpportunityUpsertResult>(exception)
                : Task.FromResult(new FundingOpportunityUpsertResult(
                    (FundingOpportunityUpsertOutcome)result,
                    Guid.NewGuid()));
        }

        public Task<FundingOpportunityPage> SearchPublishedAsync(
            string? query, int pageNumber, int pageSize, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(
            string slug, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class AbortOnceOpportunityRepository(
        CancellationTokenSource firstAttemptCancellation) : IFundingOpportunityRepository
    {
        public int Attempts { get; private set; }

        public Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
            int expectedFundingSourceId,
            string expectedProviderCode,
            ExternalFundingOpportunity opportunity,
            CancellationToken cancellationToken)
        {
            Attempts++;
            if (Attempts == 1)
            {
                firstAttemptCancellation.Cancel();
                return Task.FromCanceled<FundingOpportunityUpsertResult>(
                    firstAttemptCancellation.Token);
            }

            return Task.FromResult(new FundingOpportunityUpsertResult(
                FundingOpportunityUpsertOutcome.Created,
                Guid.NewGuid()));
        }

        public Task<FundingOpportunityPage> SearchPublishedAsync(
            string? query,
            int pageNumber,
            int pageSize,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(
            string slug,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FakeImportRunRepository(
        Guid runId,
        string providerCode = "grants-gov",
        int fundingSourceId = 1) : IImportRunRepository
    {
        private readonly Dictionary<string, (
            Guid ItemId,
            Guid RawId,
            FundingSourceObservation Observation)> observations =
            new(StringComparer.Ordinal);
        private readonly HashSet<Guid> completedItems = [];

        public List<string> Events { get; } = [];
        public int RawRecordCalls { get; private set; }
        public int DurableObservationCount => observations.Count;
        public int CompletedItemCount => completedItems.Count;
        public bool RunCompleted { get; private set; }
        public int RunCompletionCalls { get; private set; }
        public bool ThrowOnFirstRunCompletion { get; init; }
        public string? ItemFailureCode { get; private set; }
        public string? ItemFailureMessage { get; private set; }
        public string? RunFailureCode { get; private set; }
        public string? RunFailureMessage { get; private set; }
        public ImportRunCreateMutation CreateMutation { get; init; } =
            new(false, "not-found");
        public bool CreateWasCalled { get; private set; }
        public string? CreatedKeyword { get; private set; }
        public byte[]? IdempotencyHash { get; private set; }
        public byte[]? RequestHash { get; private set; }
        public string? CorrelationId { get; private set; }
        public bool LeaseRenewalSucceeds { get; init; } = true;
        public string? ClaimFailureCode { get; init; }
        public int LeaseRenewalCalls { get; private set; }
        public TaskCompletionSource FirstLeaseRenewal { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<ImportRunClaimMutation> ClaimAsync(
            Guid requestedRunId,
            Guid leaseId,
            DateTimeOffset nowUtc,
            TimeSpan leaseDuration,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (ClaimFailureCode is not null)
                return Task.FromResult(new ImportRunClaimMutation(false, ClaimFailureCode));
            var claim = requestedRunId == runId && !RunCompleted
                ? new ImportRunClaimMutation(true, "claimed", new ImportRunClaim(
                    runId, fundingSourceId, providerCode, "nonprofit", 25,
                    observations.Count, 1, leaseId,
                    60, 1_048_576, 90, 1, new byte[32]))
                : new ImportRunClaimMutation(false, "not-claimable");
            return Task.FromResult(claim);
        }

        public Task<bool> RenewLeaseAsync(
            Guid requestedRunId,
            Guid leaseId,
            DateTimeOffset nowUtc,
            TimeSpan leaseDuration,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LeaseRenewalCalls++;
            FirstLeaseRenewal.TrySetResult();
            return Task.FromResult(LeaseRenewalSucceeds);
        }

        public Task<IReadOnlyList<PendingImportRunItem>> ListPendingItemsAsync(
            Guid requestedRunId,
            Guid leaseId,
            int batchSize,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var pending = observations.Values
                .Where(value => !completedItems.Contains(value.ItemId))
                .Take(batchSize)
                .Select(value =>
                {
                    var snapshot = FundingOpportunitySnapshotSerializer.Serialize(
                        value.Observation.Opportunity);
                    return new PendingImportRunItem(
                        value.ItemId,
                        value.RawId,
                        value.Observation.ExternalId,
                        snapshot.Version,
                        snapshot.Json,
                        snapshot.Hash);
                })
                .ToArray();
            return Task.FromResult<IReadOnlyList<PendingImportRunItem>>(pending);
        }

        public Task<ImportObservationRecord> RecordObservationAsync(
            Guid requestedRunId,
            Guid leaseId,
            FundingSourceObservation observation,
            byte[] sourceItemKeyHash,
            CancellationToken cancellationToken)
        {
            RawRecordCalls++;
            Events.Add($"raw:{observation.ExternalId}");
            if (!observations.TryGetValue(observation.ExternalId, out var ids))
            {
                ids = (Guid.NewGuid(), Guid.NewGuid(), observation);
                observations.Add(observation.ExternalId, ids);
            }

            return Task.FromResult(new ImportObservationRecord(
                ids.ItemId,
                ids.RawId,
                RawRecordCalls > observations.Count,
                completedItems.Contains(ids.ItemId)));
        }

        public Task CompleteItemAsync(
            Guid requestedRunId,
            Guid leaseId,
            Guid itemId,
            Guid? opportunityId,
            FundingOpportunityUpsertOutcome outcome,
            DateTimeOffset completedAtUtc,
            CancellationToken cancellationToken)
        {
            completedItems.Add(itemId);
            var externalId = observations.Single(pair => pair.Value.ItemId == itemId).Key;
            Events.Add($"stage:{externalId}");
            return Task.CompletedTask;
        }

        public Task FailItemAsync(
            Guid requestedRunId,
            Guid leaseId,
            Guid itemId,
            string stage,
            string errorCode,
            string safeMessage,
            bool isRetryable,
            DateTimeOffset failedAtUtc,
            CancellationToken cancellationToken)
        {
            ItemFailureCode = errorCode;
            ItemFailureMessage = safeMessage;
            return Task.CompletedTask;
        }

        public Task CompleteRunAsync(
            Guid requestedRunId,
            Guid leaseId,
            DateTimeOffset completedAtUtc,
            CancellationToken cancellationToken)
        {
            RunCompletionCalls++;
            if (ThrowOnFirstRunCompletion && RunCompletionCalls == 1)
            {
                throw new SimulatedCrashException();
            }

            Events.Add("run:complete");
            RunCompleted = true;
            return Task.CompletedTask;
        }

        public Task FailRunAsync(
            Guid requestedRunId,
            Guid leaseId,
            string stage,
            string errorCode,
            string safeMessage,
            bool isRetryable,
            DateTimeOffset failedAtUtc,
            CancellationToken cancellationToken)
        {
            RunFailureCode = errorCode;
            RunFailureMessage = safeMessage;
            return Task.CompletedTask;
        }

        public Task<ImportRunCreateMutation> CreateManualAsync(
            Guid adminUserPublicId, int fundingSourceId, string keyword,
            int maximumResults, byte[] idempotencyKeyHash, byte[] requestHash,
            string correlationId, CancellationToken cancellationToken)
        {
            CreateWasCalled = true;
            CreatedKeyword = keyword;
            IdempotencyHash = [.. idempotencyKeyHash];
            RequestHash = [.. requestHash];
            CorrelationId = correlationId;
            return Task.FromResult(CreateMutation);
        }

        public Task<ImportRunPage> ListAsync(
            Guid adminUserPublicId, int? fundingSourceId, ImportRunStatus? status,
            int page, int pageSize, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ImportRunDetail?> GetAsync(
            Guid adminUserPublicId, Guid requestedRunId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<IReadOnlyList<ScheduledImportRun>> CreateDueScheduledAsync(
            DateTimeOffset nowUtc, int batchSize, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<IReadOnlyList<ScheduledImportRun>> RequeueStrandedAsync(
            DateTimeOffset nowUtc, int batchSize, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class SimulatedCrashException : Exception;
}
