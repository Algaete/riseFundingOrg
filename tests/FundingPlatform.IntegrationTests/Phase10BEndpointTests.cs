using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Networking;
using FundingPlatform.Core.Networking;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class Phase10BEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly Guid UserId = Guid.Parse("91000000-0000-0000-0000-000000000001");
    private static readonly Guid OrganizationId = Guid.Parse("92000000-0000-0000-0000-000000000001");
    private static readonly Guid RecipientId = Guid.Parse("93000000-0000-0000-0000-000000000001");
    private static readonly Guid ConnectionId = Guid.Parse("94000000-0000-0000-0000-000000000001");
    private readonly FakeNetworkingRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase10BEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<INetworkingRepository>();
            services.AddSingleton<INetworkingRepository>(repository);
        }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
    }

    [Theory]
    [InlineData("GET", "/settings")]
    [InlineData("GET", "/directory")]
    [InlineData("GET", "/connections")]
    [InlineData("POST", "/connections")]
    public async Task Networking_routes_require_full_session_and_are_no_store(string method, string suffix)
    {
        using var response = await client.SendAsync(new HttpRequestMessage(new HttpMethod(method), Path(suffix)));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Settings_and_directory_return_only_safe_contracts()
    {
        using var settingsRequest = Authenticated(HttpMethod.Get, Path("/settings"));
        using var settings = await client.SendAsync(settingsRequest);
        using var directoryRequest = Authenticated(HttpMethod.Get, Path("/directory?q=agua&page=1&pageSize=20"));
        using var directory = await client.SendAsync(directoryRequest);
        using var payload = JsonDocument.Parse(await directory.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, settings.StatusCode);
        Assert.Equal("\"0102030405060708\"", settings.Headers.ETag?.Tag);
        Assert.Equal(HttpStatusCode.OK, directory.StatusCode);
        var item = payload.RootElement.GetProperty("items")[0];
        Assert.Equal("Organización Agua", item.GetProperty("name").GetString());
        Assert.False(item.TryGetProperty("email", out _));
        Assert.False(item.TryGetProperty("taxIdentifier", out _));
    }

    [Fact]
    public async Task Create_requires_idempotency_and_rejects_contact_data_before_repository()
    {
        var body = new { recipientOrganizationId = RecipientId, requesterProjectId = (Guid?)null,
            purpose = "partnership", message = "Buscamos una alianza para agua segura." };
        using var missing = Authenticated(HttpMethod.Post, Path("/connections"), body);
        using var missingResponse = await client.SendAsync(missing);
        using var invalid = Authenticated(HttpMethod.Post, Path("/connections"), new
        {
            recipientOrganizationId = RecipientId, requesterProjectId = (Guid?)null,
            purpose = "partnership", message = "Escríbenos a persona@example.org"
        });
        invalid.Headers.Add("Idempotency-Key", "organization-connect-invalid");
        using var invalidResponse = await client.SendAsync(invalid);

        Assert.Equal((HttpStatusCode)428, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, invalidResponse.StatusCode);
        Assert.Equal(0, repository.CreateCalls);
    }

    [Fact]
    public async Task Create_and_accept_use_durable_key_and_strong_etag()
    {
        using var create = Authenticated(HttpMethod.Post, Path("/connections"), new
        {
            recipientOrganizationId = RecipientId, requesterProjectId = (Guid?)null,
            purpose = "partnership", message = "Buscamos una alianza para agua segura."
        });
        create.Headers.Add("Idempotency-Key", "organization-connect-0001");
        using var created = await client.SendAsync(create);
        using var missingEtag = Authenticated(HttpMethod.Patch,
            Path($"/connections/{ConnectionId:D}"), new { action = "accept" });
        using var missingEtagResponse = await client.SendAsync(missingEtag);
        using var accept = Authenticated(HttpMethod.Patch,
            Path($"/connections/{ConnectionId:D}"), new { action = "accept" });
        accept.Headers.TryAddWithoutValidation("If-Match", "\"0102030405060708\"");
        using var accepted = await client.SendAsync(accept);

        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Equal("\"0102030405060708\"", created.Headers.ETag?.Tag);
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal(32, repository.IdempotencyHash?.Length);
        Assert.Equal((HttpStatusCode)428, missingEtagResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        Assert.Equal(OrganizationConnectionStatus.Accepted, repository.Action);
    }

    public void Dispose() { client.Dispose(); application.Dispose(); }

    private static string Path(string suffix) =>
        $"/api/v1/organizations/{OrganizationId:D}/network{suffix}";
    private static HttpRequestMessage Authenticated(HttpMethod method, string path, object? body = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Jwt());
        if (body is not null) request.Content = JsonContent.Create(body);
        return request;
    }
    private static string Jwt()
    {
        var now = DateTime.UtcNow;
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(JwtIssuer, JwtAudience,
            [new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
             new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
             new Claim("auth_level", "full"), new Claim("amr", "pwd")],
            now.AddMinutes(-1), now.AddMinutes(10),
            new SigningCredentials(new SymmetricSecurityKey(SigningKey), SecurityAlgorithms.HmacSha512)));
    }

    private sealed class FakeNetworkingRepository : INetworkingRepository
    {
        public int TotalCalls { get; private set; }
        public int CreateCalls { get; private set; }
        public byte[]? IdempotencyHash { get; private set; }
        public OrganizationConnectionStatus? Action { get; private set; }
        private static NetworkingPreference Preference() => new(true, true, true,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, "\"0102030405060708\"");
        private static OrganizationConnection Connection(OrganizationConnectionStatus status = OrganizationConnectionStatus.Pending) =>
            new(ConnectionId, ConnectionDirection.Outgoing, status, ConnectionPurpose.Partnership,
                "Buscamos una alianza para agua segura.", RecipientId, "Organización Agua", true,
                null, null, null, status == OrganizationConnectionStatus.Pending, false, true,
                DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, "\"0102030405060708\"");
        public Task<NetworkingPreference?> GetPreferenceAsync(Guid userPublicId, Guid organizationPublicId, CancellationToken cancellationToken)
        { TotalCalls++; return Task.FromResult<NetworkingPreference?>(Preference()); }
        public Task<NetworkingPreferenceMutation> PutPreferenceAsync(Guid userPublicId, Guid organizationPublicId, bool isDiscoverable, bool allowRequests, byte[]? expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        { TotalCalls++; return Task.FromResult(new NetworkingPreferenceMutation(NetworkingMutationOutcome.Updated, Preference())); }
        public Task<NetworkDirectoryPage?> SearchDirectoryAsync(Guid userPublicId, Guid organizationPublicId, NetworkDirectoryFilters filters, CancellationToken cancellationToken)
        { TotalCalls++; return Task.FromResult<NetworkDirectoryPage?>(new([new NetworkDirectoryOrganization(RecipientId, "Organización Agua", "Agua segura", "https://example.invalid", new(152, "CL", "Chile"), new(1, "foundation", "Fundación"), 1, true, null, DirectoryConnectionState.None, [], [])], 1, 1, 20)); }
        public Task<OrganizationConnectionPage?> ListConnectionsAsync(Guid userPublicId, Guid organizationPublicId, ConnectionDirection direction, OrganizationConnectionStatus? status, int pageNumber, int pageSize, CancellationToken cancellationToken)
        { TotalCalls++; return Task.FromResult<OrganizationConnectionPage?>(new([], 0, pageNumber, pageSize)); }
        public Task<OrganizationConnection?> GetConnectionAsync(Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId, CancellationToken cancellationToken)
        { TotalCalls++; return Task.FromResult<OrganizationConnection?>(Connection()); }
        public Task<OrganizationConnectionMutation> CreateConnectionAsync(Guid userPublicId, Guid requesterOrganizationPublicId, Guid recipientOrganizationPublicId, Guid? requesterProjectPublicId, ConnectionPurpose purpose, string message, byte[] idempotencyKeyHash, byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        { TotalCalls++; CreateCalls++; IdempotencyHash = idempotencyKeyHash; return Task.FromResult(new OrganizationConnectionMutation(NetworkingMutationOutcome.Created, Connection())); }
        public Task<OrganizationConnectionMutation> ActionConnectionAsync(Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId, OrganizationConnectionStatus action, byte[] expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        { TotalCalls++; Action = action; return Task.FromResult(new OrganizationConnectionMutation(NetworkingMutationOutcome.Updated, Connection(action))); }
    }
}
