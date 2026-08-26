using FundingPlatform.Application.Networking;
using FundingPlatform.Core.Networking;

namespace FundingPlatform.UnitTests;

public sealed class NetworkingServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Create_normalizes_message_and_hashes_a_stable_request()
    {
        var repository = new FakeRepository();
        var service = new NetworkingService(repository, new FixedTimeProvider(Now));
        var userId = Guid.NewGuid();
        var organizationId = Guid.NewGuid();
        var recipientId = Guid.NewGuid();
        var first = new CreateConnectionCommand(userId, organizationId, recipientId, null,
            ConnectionPurpose.Partnership, "  Buscamos   una alianza técnica segura. ",
            "organization-connect-0001");

        await service.CreateConnectionAsync(first, CancellationToken.None);
        await service.CreateConnectionAsync(first with
        {
            Message = "Buscamos una alianza técnica segura."
        }, CancellationToken.None);

        Assert.Equal("Buscamos una alianza técnica segura.", repository.Message);
        Assert.Equal(2, repository.RequestHashes.Count);
        Assert.Equal(repository.RequestHashes[0], repository.RequestHashes[1]);
        Assert.All(repository.RequestHashes, value => Assert.Equal(32, value.Length));
        Assert.Equal(Now, repository.NowUtc);
    }

    [Theory]
    [InlineData("Escríbenos a persona@example.org")]
    [InlineData("Visita https://example.org para colaborar")]
    [InlineData("Mi teléfono directo es 12345678")]
    public async Task Create_rejects_contact_data_before_the_repository(string message)
    {
        var repository = new FakeRepository();
        var result = await new NetworkingService(repository, new FixedTimeProvider(Now))
            .CreateConnectionAsync(new CreateConnectionCommand(Guid.NewGuid(), Guid.NewGuid(),
                Guid.NewGuid(), null, ConnectionPurpose.Expertise, message,
                "organization-connect-0002"), CancellationToken.None);

        Assert.Equal(NetworkingMutationOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(0, repository.CreateCalls);
        Assert.Contains("message", result.Errors!.Keys, StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Directory_normalizes_deduplicates_and_sorts_filters()
    {
        var repository = new FakeRepository();
        var service = new NetworkingService(repository, new FixedTimeProvider(Now));
        var result = await service.SearchDirectoryAsync(Guid.NewGuid(), Guid.NewGuid(),
            new NetworkDirectoryFilters("  agua  ", [152, 56, 152], [4, 2, 4], [8, 3], 1, 20),
            CancellationToken.None);

        Assert.Null(result.Errors);
        Assert.Equal("agua", repository.Filters!.Query);
        Assert.Equal([56, 152], repository.Filters.CountryIds);
        Assert.Equal([2, 4], repository.Filters.CategoryIds);
        Assert.Equal([3, 8], repository.Filters.ProjectTypeIds);
    }

    [Fact]
    public async Task Preference_rejects_requests_when_visibility_is_off()
    {
        var repository = new FakeRepository();
        var result = await new NetworkingService(repository, new FixedTimeProvider(Now))
            .PutPreferenceAsync(Guid.NewGuid(), Guid.NewGuid(), false, true, null,
                CancellationToken.None);

        Assert.Equal(NetworkingMutationOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(0, repository.PreferenceCalls);
    }

    private sealed class FixedTimeProvider(DateTimeOffset value) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => value;
    }

    private sealed class FakeRepository : INetworkingRepository
    {
        public int CreateCalls { get; private set; }
        public int PreferenceCalls { get; private set; }
        public string? Message { get; private set; }
        public DateTimeOffset NowUtc { get; private set; }
        public NetworkDirectoryFilters? Filters { get; private set; }
        public List<byte[]> RequestHashes { get; } = [];

        public Task<NetworkingPreference?> GetPreferenceAsync(Guid userPublicId,
            Guid organizationPublicId, CancellationToken cancellationToken) =>
            Task.FromResult<NetworkingPreference?>(null);
        public Task<NetworkingPreferenceMutation> PutPreferenceAsync(Guid userPublicId,
            Guid organizationPublicId, bool isDiscoverable, bool allowRequests,
            byte[]? expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            PreferenceCalls++;
            return Task.FromResult(new NetworkingPreferenceMutation(NetworkingMutationOutcome.Updated));
        }
        public Task<NetworkDirectoryPage?> SearchDirectoryAsync(Guid userPublicId,
            Guid organizationPublicId, NetworkDirectoryFilters filters,
            CancellationToken cancellationToken)
        {
            Filters = filters;
            return Task.FromResult<NetworkDirectoryPage?>(new([], 0, filters.PageNumber, filters.PageSize));
        }
        public Task<OrganizationConnectionPage?> ListConnectionsAsync(Guid userPublicId,
            Guid organizationPublicId, ConnectionDirection direction,
            OrganizationConnectionStatus? status, int pageNumber, int pageSize,
            CancellationToken cancellationToken) =>
            Task.FromResult<OrganizationConnectionPage?>(new([], 0, pageNumber, pageSize));
        public Task<OrganizationConnection?> GetConnectionAsync(Guid userPublicId,
            Guid organizationPublicId, Guid connectionPublicId,
            CancellationToken cancellationToken) => Task.FromResult<OrganizationConnection?>(null);
        public Task<OrganizationConnectionMutation> CreateConnectionAsync(Guid userPublicId,
            Guid requesterOrganizationPublicId, Guid recipientOrganizationPublicId,
            Guid? requesterProjectPublicId, ConnectionPurpose purpose, string message,
            byte[] idempotencyKeyHash, byte[] requestHash, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            CreateCalls++; Message = message; NowUtc = nowUtc; RequestHashes.Add(requestHash);
            return Task.FromResult(new OrganizationConnectionMutation(NetworkingMutationOutcome.Created));
        }
        public Task<OrganizationConnectionMutation> ActionConnectionAsync(Guid userPublicId,
            Guid organizationPublicId, Guid connectionPublicId,
            OrganizationConnectionStatus action, byte[] expectedRowVersion,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult(new OrganizationConnectionMutation(NetworkingMutationOutcome.Updated));
    }
}
