using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.UnitTests;

public sealed class EventIngressTrustPolicyAdministrationTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 9, 8, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Request_hash_is_bound_to_the_selected_workload()
    {
        var repository = new RecordingRepository();
        var service = new EventIngressTrustPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));

        await service.UpsertAsync(
            ValidCommand(EventIngressWorkloadKind.SourceDocument), CancellationToken.None);
        var sourceDocumentHash = repository.RequestHash;

        await service.UpsertAsync(
            ValidCommand(EventIngressWorkloadKind.ProjectAsset), CancellationToken.None);

        Assert.NotNull(sourceDocumentHash);
        Assert.NotEqual(sourceDocumentHash, repository.RequestHash);
        Assert.Equal(EventIngressWorkloadKind.ProjectAsset, repository.Command!.WorkloadKind);
    }

    [Fact]
    public async Task Source_document_request_hash_preserves_the_v1_idempotency_domain()
    {
        var repository = new RecordingRepository();
        var service = new EventIngressTrustPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));
        var command = ValidCommand(EventIngressWorkloadKind.SourceDocument);

        await service.UpsertAsync(command, CancellationToken.None);

        var expected = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "EventIngressTrustPolicy/v1",
            string.Empty,
            string.Empty,
            command.TenantId.ToString("D"),
            command.PrincipalObjectId.ToString("D"),
            command.ApplicationClientId.ToString("D"),
            command.TopicResourceId,
            command.EventSubscriptionName,
            command.StorageAccountResourceId,
            command.StorageAccountHost,
            command.QuarantineContainer,
            "1",
            command.ValidFromUtc.UtcDateTime.ToString("O"),
            command.ExpiresAtUtc!.Value.UtcDateTime.ToString("O"),
            command.Reason)));
        Assert.Equal(expected, repository.RequestHash);
    }

    [Fact]
    public async Task Unsupported_workload_is_rejected_before_SQL()
    {
        var repository = new RecordingRepository();
        var service = new EventIngressTrustPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));

        await Assert.ThrowsAsync<ArgumentException>(() => service.UpsertAsync(
            ValidCommand((EventIngressWorkloadKind)3), CancellationToken.None));

        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task Resource_identifiers_are_canonicalized_before_persistence()
    {
        var repository = new RecordingRepository();
        var service = new EventIngressTrustPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));
        var command = ValidCommand(EventIngressWorkloadKind.ProjectAsset) with
        {
            TopicResourceId =
                " /SUBSCRIPTIONS/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/RESOURCEGROUPS/RG/PROVIDERS/MICROSOFT.EVENTGRID/SYSTEMTOPICS/DEFENDER ",
            StorageAccountResourceId =
                " /SUBSCRIPTIONS/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/RESOURCEGROUPS/RG/PROVIDERS/MICROSOFT.STORAGE/STORAGEACCOUNTS/ACCOUNT ",
            StorageAccountHost = " ACCOUNT.BLOB.CORE.WINDOWS.NET ",
            QuarantineContainer = " FP-PROJECT-QUARANTINE "
        };

        await service.UpsertAsync(command, CancellationToken.None);

        Assert.Equal(command.TopicResourceId.Trim().ToLowerInvariant(),
            repository.Command!.TopicResourceId);
        Assert.Equal(command.StorageAccountResourceId.Trim().ToLowerInvariant(),
            repository.Command.StorageAccountResourceId);
        Assert.Equal("account.blob.core.windows.net", repository.Command.StorageAccountHost);
        Assert.Equal("fp-project-quarantine", repository.Command.QuarantineContainer);
    }

    private static EventIngressTrustPolicyCommand ValidCommand(
        EventIngressWorkloadKind workloadKind) => new(
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        null,
        null,
        workloadKind,
        Guid.Parse("22222222-2222-2222-2222-222222222222"),
        Guid.Parse("33333333-3333-3333-3333-333333333333"),
        Guid.Parse("44444444-4444-4444-4444-444444444444"),
        "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.eventgrid/systemtopics/defender",
        "project-asset-defender-results",
        "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.storage/storageaccounts/account",
        "account.blob.core.windows.net",
        "fp-project-quarantine",
        true,
        Now.AddMinutes(-5),
        Now.AddDays(30),
        "Enable the exact project asset ingress.",
        "trust-policy-test-0001",
        "trust-policy-correlation-0001");

    private sealed class RecordingRepository : IEventIngressTrustPolicyRepository
    {
        public int Calls { get; private set; }
        public EventIngressTrustPolicyCommand? Command { get; private set; }
        public byte[]? RequestHash { get; private set; }

        public Task<EventIngressTrustPolicyMutation> UpsertAsync(
            EventIngressTrustPolicyCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            Command = command;
            RequestHash = requestHash;
            return Task.FromResult(new EventIngressTrustPolicyMutation(
                true,
                "created",
                Guid.Parse("55555555-5555-5555-5555-555555555555"),
                command.IsEnabled,
                new byte[8],
                false));
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
