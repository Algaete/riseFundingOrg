using FundingPlatform.Application.Imports;
using FundingPlatform.Core.Imports;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Workers.Configuration;
using FundingPlatform.Workers.Functions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class OnDemandImportTests
{
    private static readonly Guid RunId = Guid.Parse("71717171-7171-7171-7171-717171717171");
    private static readonly DateTimeOffset Now = new(2026, 9, 10, 3, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData("Migrations", "047_on_demand_imports.sql")]
    [InlineData("Tests", "047_on_demand_imports_smoke.sql")]
    public void Queue_delivery_sql_parses_as_Azure_SQL(string directory, string file)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = File.ReadAllText(Path.Combine(root, "database", directory, file));
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(sql), out var errors);
        Assert.Empty(errors);
    }

    [Fact]
    public async Task Accepted_requires_persistence_then_durable_queue_notification()
    {
        var events = new List<string>();
        var durable = new Durable(events);
        var activation = new Activation(events);
        var result = await Create(new(durable, activation));
        Assert.Equal(ImportRunOutcome.Success, result.Outcome);
        Assert.Equal(["persist", "notify"], events);
        Assert.Equal(RunId, Assert.Single(activation.Notifications));
    }

    [Fact]
    public async Task Failed_send_preserves_the_run_and_replay_retries_the_same_notification()
    {
        var durable = new Durable([]);
        var activation = new Activation([]) { Fail = true };
        var service = new OnDemandImportRunService(durable, activation);
        var failure = await Create(service);
        Assert.Equal(ImportRunOutcome.Unavailable, failure.Outcome);
        Assert.Equal("queue-unavailable", failure.Code);
        Assert.Equal(RunId, failure.Value!.RunId);
        activation.Fail = false;
        var replay = await Create(service);
        Assert.Equal(ImportRunOutcome.Success, replay.Outcome);
        Assert.True(replay.Value!.WasReplay);
        Assert.Equal(["same-idempotency-key", "same-idempotency-key"], durable.Keys);
        Assert.All(activation.Notifications, id => Assert.Equal(RunId, id));
    }

    [Theory]
    [InlineData(ImportRunOutcome.Forbidden)]
    [InlineData(ImportRunOutcome.Invalid)]
    [InlineData(ImportRunOutcome.Conflict)]
    [InlineData(ImportRunOutcome.NotFound)]
    [InlineData(ImportRunOutcome.Unavailable)]
    public async Task Failed_persistence_never_sends_a_queue_message(ImportRunOutcome outcome)
    {
        var activation = new Activation([]);
        var result = await Create(new(new Durable([]) { Outcome = outcome }, activation));
        Assert.Equal(outcome, result.Outcome);
        Assert.Empty(activation.Notifications);
    }

    [Fact]
    public async Task Disabled_dispatch_cannot_accept_a_new_orphaned_run()
    {
        var durable = new Durable([]);
        var result = await Create(new(durable, new Activation([]) { IsEnabled = false }));
        Assert.Equal("queue-disabled", result.Code);
        Assert.Empty(durable.Keys);
    }

    [Theory]
    [InlineData(ImportRunStatus.Completed)]
    [InlineData(ImportRunStatus.Partial)]
    [InlineData(ImportRunStatus.Failed)]
    [InlineData(ImportRunStatus.Canceled)]
    public async Task Terminal_replays_do_not_start_another_import(ImportRunStatus status)
    {
        var activation = new Activation([]);
        var service = new OnDemandImportRunService(new Durable([]) { Status = status }, activation);
        await Create(service);
        await service.DispatchAsync(Guid.NewGuid(), RunId, CancellationToken.None);
        Assert.Empty(activation.Notifications);
    }

    [Fact]
    public async Task Reads_never_activate_and_manual_recovery_rechecks_access_without_creating()
    {
        var durable = new Durable([]);
        var activation = new Activation([]);
        var service = new OnDemandImportRunService(durable, activation);
        await service.ListAsync(Guid.NewGuid(), null, null, 1, 10, CancellationToken.None);
        await service.GetAsync(Guid.NewGuid(), RunId, CancellationToken.None);
        Assert.Empty(activation.Notifications);
        durable.Outcome = ImportRunOutcome.Forbidden;
        Assert.Equal(ImportRunOutcome.Forbidden,
            (await service.DispatchAsync(Guid.NewGuid(), RunId, CancellationToken.None)).Outcome);
        Assert.Empty(activation.Notifications);
        durable.Outcome = ImportRunOutcome.Success;
        await service.DispatchAsync(Guid.NewGuid(), RunId, CancellationToken.None);
        Assert.Equal(RunId, Assert.Single(activation.Notifications));
        Assert.Empty(durable.Keys);
    }

    [Fact]
    public async Task Default_timer_guards_do_not_touch_their_SQL_services()
    {
        var options = Options.Create(new ImportWorkerOptions());
        Assert.True(options.Value.OnDemandOnly);
        await new ImportSchedulerFunction(null!, options,
            NullLogger<ImportSchedulerFunction>.Instance).RunAsync(null!, CancellationToken.None);
        await new ImportOutboxDispatcherFunction(null!, options,
            NullLogger<ImportOutboxDispatcherFunction>.Instance).RunAsync(null!, CancellationToken.None);
    }

    [Fact]
    public async Task Retry_is_a_single_delayed_message_using_the_SQL_retry_time()
    {
        var deliveries = new Deliveries(new(ImportRunStatus.Queued, Now, null),
            new(ImportRunStatus.Queued, Now.AddSeconds(30), null));
        var queue = new RetryQueue();
        await QueueService(deliveries, queue).ProcessAsync(RunId,
            (_, _) => Task.FromResult(new ImportRunProcessingResult(ImportRunProcessingOutcome.Failed, RunId)),
            CancellationToken.None);
        Assert.Equal([true, false], deliveries.Receipts);
        Assert.Equal(TimeSpan.FromSeconds(31), Assert.Single(queue.Messages).Delay);
    }

    [Fact]
    public async Task Active_lease_delivery_is_deferred_without_resetting_the_run()
    {
        var state = new ImportQueueDeliveryState(ImportRunStatus.Running, Now, Now.AddMinutes(10));
        var queue = new RetryQueue();
        await QueueService(new(state, state), queue).ProcessAsync(RunId,
            (_, _) => Task.FromResult(new ImportRunProcessingResult(ImportRunProcessingOutcome.Ignored, RunId, Code: "lease-active")),
            CancellationToken.None);
        Assert.Equal(TimeSpan.FromSeconds(601), Assert.Single(queue.Messages).Delay);
    }

    [Fact]
    public async Task Terminal_and_missing_deliveries_do_not_process_or_reschedule()
    {
        foreach (var state in new ImportQueueDeliveryState?[]
                 { null, new(ImportRunStatus.Failed, Now, null), new(ImportRunStatus.Completed, Now, null) })
        {
            var queue = new RetryQueue();
            await QueueService(new(state), queue).ProcessAsync(RunId,
                (_, _) => throw new InvalidOperationException("Must not process"), CancellationToken.None);
            Assert.Empty(queue.Messages);
        }
    }

    [Fact]
    public async Task Successful_processing_does_not_schedule_more_work()
    {
        var queue = new RetryQueue();
        await QueueService(new(new(ImportRunStatus.Queued, Now, null),
            new(ImportRunStatus.Completed, Now, null)), queue).ProcessAsync(RunId,
            (_, _) => Task.FromResult(new ImportRunProcessingResult(ImportRunProcessingOutcome.Completed, RunId)),
            CancellationToken.None);
        Assert.Empty(queue.Messages);
    }

    [Fact]
    public async Task Processing_or_retry_publication_failure_abandons_delivery_for_native_recovery()
    {
        var pending = new ImportQueueDeliveryState(ImportRunStatus.Queued, Now.AddSeconds(5), null);
        await Assert.ThrowsAsync<InvalidOperationException>(() => QueueService(new(pending), new())
            .ProcessAsync(RunId, (_, _) => throw new InvalidOperationException("crash"), CancellationToken.None));
        await Assert.ThrowsAsync<InvalidOperationException>(() => QueueService(new(pending, pending),
            new() { Fail = true }).ProcessAsync(RunId,
            (_, _) => Task.FromResult(new ImportRunProcessingResult(ImportRunProcessingOutcome.Failed, RunId)),
            CancellationToken.None));
    }

    [Theory]
    [InlineData("https://account.queue.core.windows.net/?sig=secret", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    [InlineData("http://account.queue.core.windows.net/", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    [InlineData("https://account.queue.core.windows.net/other", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    [InlineData("https://account.queue.core.windows.net/", "00000000-0000-0000-0000-000000000000")]
    public void Sender_configuration_rejects_credentials_insecure_endpoints_and_missing_identity(string endpoint, string id)
    {
        var configuration = Config(new() { ["ImportDispatch:Enabled"] = "true",
            ["ImportDispatch:QueueServiceUri"] = endpoint, ["ImportDispatch:ManagedIdentityClientId"] = id });
        Assert.Throws<InvalidOperationException>(() => ImportDispatchConfiguration.Resolve(configuration, false));
    }

    [Fact]
    public void Sender_is_disabled_by_default_and_Azurite_is_never_allowed_in_Azure()
    {
        Assert.False(ImportDispatchConfiguration.Resolve(Config([]), false).Enabled);
        var local = Config(new() { ["ImportDispatch:Enabled"] = "true", ["ImportDispatch:UseDevelopmentStorage"] = "true" });
        Assert.Throws<InvalidOperationException>(() => ImportDispatchConfiguration.Resolve(local, false));
        Assert.True(ImportDispatchConfiguration.Resolve(local, true).UseDevelopmentStorage);
    }

    private static IConfiguration Config(Dictionary<string, string?> values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values).Build();
    private static Task<ImportRunResult<ImportRunAccepted>> Create(OnDemandImportRunService service) =>
        service.CreateManualAsync(Guid.NewGuid(), 1, "nonprofit", 1,
            "same-idempotency-key", "trace", CancellationToken.None);
    private static OnDemandImportQueueService QueueService(Deliveries deliveries, RetryQueue queue) =>
        new(deliveries, queue, new Clock());
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Deliveries(params ImportQueueDeliveryState?[] states) : IImportQueueDeliveryRepository
    {
        public List<bool> Receipts { get; } = [];
        public Task<ImportQueueDeliveryState?> GetAsync(Guid runId, bool confirmReceipt, CancellationToken cancellationToken)
        {
            Assert.Equal(RunId, runId);
            Receipts.Add(confirmReceipt);
            return Task.FromResult(states[Receipts.Count - 1]);
        }
    }
    private sealed class RetryQueue : IImportRetryQueuePublisher
    {
        public bool Fail { get; init; }
        public List<(Guid RunId, TimeSpan Delay)> Messages { get; } = [];
        public Task PublishAfterAsync(ImportRunQueueMessage message, TimeSpan delay, CancellationToken cancellationToken)
        {
            if (Fail) throw new InvalidOperationException("queue unavailable");
            Messages.Add((message.RunId, delay));
            return Task.CompletedTask;
        }
    }
    private sealed class Activation(List<string> events) : IImportRunActivation
    {
        public bool IsEnabled { get; init; } = true;
        public bool Fail { get; set; }
        public List<Guid> Notifications { get; } = [];
        public Task NotifyAsync(Guid runId, CancellationToken cancellationToken)
        {
            events.Add("notify");
            Notifications.Add(runId);
            if (Fail) throw new ImportQueueActivationException(new InvalidOperationException("storage unavailable"));
            return Task.CompletedTask;
        }
    }
    private sealed class Durable(List<string> events) : IImportRunService
    {
        public ImportRunOutcome Outcome { get; set; } = ImportRunOutcome.Success;
        public ImportRunStatus Status { get; init; } = ImportRunStatus.Queued;
        public List<string> Keys { get; } = [];
        public Task<ImportRunResult<ImportRunAccepted>> CreateManualAsync(Guid actor, int source, string keyword,
            int maximum, string key, string correlation, CancellationToken token)
        {
            events.Add("persist"); Keys.Add(key);
            return Task.FromResult(new ImportRunResult<ImportRunAccepted>(Outcome,
                Outcome == ImportRunOutcome.Success ? new(RunId, 1, "Grants.gov", Status, Now, Keys.Count > 1) : null));
        }
        public Task<ImportRunResult<ImportRunPage>> ListAsync(Guid actor, int? source, ImportRunStatus? status,
            int page, int size, CancellationToken token) => Task.FromResult(new ImportRunResult<ImportRunPage>(Outcome));
        public Task<ImportRunResult<ImportRunDetail>> GetAsync(Guid actor, Guid runId, CancellationToken token) =>
            Task.FromResult(new ImportRunResult<ImportRunDetail>(Outcome,
                Outcome == ImportRunOutcome.Success ? new(runId, 1, "Grants.gov", "grants-gov",
                    ImportTriggerType.Manual, Status, "nonprofit", 1, 0, 0, 0, 0, 0, 0, 1, Now, null, null, null, [], []) : null));
    }
}
