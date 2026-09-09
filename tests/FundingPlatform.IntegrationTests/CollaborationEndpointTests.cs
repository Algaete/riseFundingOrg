using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class CollaborationEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private static readonly Guid Actor = Guid.Parse("a1111111-1111-1111-1111-111111111111");
    private static readonly Guid Entity = Guid.Parse("b1111111-1111-1111-1111-111111111111");
    private const string ETag = "\"0102030405060708\"";
    private readonly Repository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;
    public CollaborationEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IProfessionalProfileRepository>(); services.RemoveAll<IConsortiumRepository>();
            services.AddSingleton<IProfessionalProfileRepository>(repository);
            services.AddSingleton<IConsortiumRepository>(repository);
        }));
        client = application.CreateClient();
    }
    [Theory]
    [InlineData("/api/v1/me/professional-profile")]
    [InlineData("/api/v1/professionals")]
    [InlineData("/api/v1/consortia")]
    public async Task Private_routes_reject_anonymous_and_mark_responses_no_store(string path)
    {
        using var response = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.Calls);
    }
    [Theory]
    [InlineData("/api/v1/professionals?page=0")]
    [InlineData("/api/v1/professionals?pageSize=51")]
    [InlineData("/api/v1/professionals?countryId=-1")]
    [InlineData("/api/v1/professionals?categoryId=0")]
    [InlineData("/api/v1/consortia?page=10001")]
    public async Task Invalid_filters_do_not_reach_repository(string path)
    {
        using var request = Request(HttpMethod.Get, path);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }
    [Fact]
    public async Task Professional_profile_is_not_automatically_created()
    {
        using var request = Request(HttpMethod.Get, "/api/v1/me/professional-profile");
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("null", await response.Content.ReadAsStringAsync());
        Assert.Equal(Actor, repository.ActorId);
        Assert.Equal(0, repository.Writes);
    }
    [Fact]
    public async Task Profile_create_accepts_optional_fields_and_explicit_create_header_without_an_organization()
    {
        using var request = Request(HttpMethod.Put, "/api/v1/me/professional-profile", new { displayName = " Nombre ", headline = " Profesional " }, create: true);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(ETag, response.Headers.ETag?.ToString());
        Assert.Null(repository.Expected);
        Assert.Equal("Nombre", repository.Profile!.DisplayName);
        Assert.False(repository.Profile.IsDiscoverable);
        Assert.False(repository.Profile.AllowsInvitations);
        Assert.Equal(1, repository.Writes);
    }
    [Theory]
    [InlineData(false, false, 428)]
    [InlineData(true, false, 428)]
    [InlineData(true, true, 200)]
    public async Task Profile_updates_require_key_and_version(bool key, bool version, int expectedStatus)
    {
        using var request = Request(HttpMethod.Put, "/api/v1/me/professional-profile", new { displayName = "Nombre", headline = "Especialidad" }, headers: false);
        if (key) request.Headers.Add("Idempotency-Key", "collaboration-command-0001");
        if (version) request.Headers.TryAddWithoutValidation("If-Match", ETag);
        using var response = await client.SendAsync(request);
        Assert.Equal(expectedStatus, (int)response.StatusCode);
        Assert.Equal(expectedStatus == 200 ? 1 : 0, repository.Writes);
    }
    [Fact]
    public async Task Profile_invitation_optin_requires_directory_consent()
    {
        using var request = Request(HttpMethod.Put, "/api/v1/me/professional-profile", new { displayName = "Nombre", headline = "Especialidad", allowsInvitations = true }, create: true);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("validationIssues", await response.Content.ReadAsStringAsync());
        Assert.Equal(0, repository.Writes);
    }
    [Fact]
    public async Task Consortium_create_returns_location_and_never_needs_global_admin()
    {
        using var request = Request(HttpMethod.Post, "/api/v1/consortia", new { projectId = Entity, name = " Alianza local ", summary = "" });
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal($"/api/v1/consortia/{Entity}", response.Headers.Location!.ToString());
        Assert.Equal(Actor, repository.ActorId);
        Assert.Equal("Alianza local", repository.CreateData!.Name);
        Assert.Null(repository.CreateData.Summary);
    }
    [Theory]
    [InlineData(0)]
    [InlineData(6)]
    public async Task Invalid_participant_action_cannot_reach_storage(int action)
    {
        using var request = Request(HttpMethod.Patch, $"/api/v1/consortia/{Entity}/participants/{Guid.NewGuid()}", new { action });
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, repository.Writes);
    }
    [Fact]
    public async Task Contact_data_in_invitation_is_rejected_before_storage()
    {
        using var request = Request(HttpMethod.Post, $"/api/v1/consortia/{Entity}/invitations", new { kind = 2, targetId = Guid.NewGuid(), contribution = "Investigación", message = "Correo: no-publicar@example.invalid" });
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, repository.Writes);
    }
    [Theory]
    [InlineData(55501, 404)]
    [InlineData(55502, 403)]
    [InlineData(55503, 412)]
    [InlineData(55504, 409)]
    [InlineData(55505, 422)]
    [InlineData(55506, 409)]
    [InlineData(55507, 409)]
    [InlineData(55508, 429)]
    [InlineData(1205, 503)]
    public async Task Database_failures_are_sanitized(int number, int expected)
    {
        repository.ErrorNumber = number;
        using var request = Request(HttpMethod.Get, "/api/v1/consortia");
        using var response = await client.SendAsync(request);
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.DoesNotContain("private database text", await response.Content.ReadAsStringAsync());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }
    [Fact]
    public async Task Participant_command_forwards_exact_actor_target_version_and_request_hash()
    {
        var participant = Guid.NewGuid();
        using var request = Request(HttpMethod.Patch, $"/api/v1/consortia/{Entity}/participants/{participant}", new { action = 1 });
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(Actor, repository.ActorId);
        Assert.Equal(participant, repository.ParticipantId);
        Assert.Equal(Convert.FromHexString("0102030405060708"), repository.Expected);
        Assert.Equal(32, repository.Hash!.Length);
        Assert.Equal(ConsortiumParticipantStatus.Accepted, repository.Action);
    }
    [Theory]
    [InlineData("00000000-0000-0000-0000-000000000000", "b1111111-1111-1111-1111-111111111111")]
    [InlineData("b1111111-1111-1111-1111-111111111111", "00000000-0000-0000-0000-000000000000")]
    public async Task Empty_route_identifiers_fail_closed_without_application_exception(string consortium, string participant)
    {
        using var request = Request(HttpMethod.Patch, $"/api/v1/consortia/{consortium}/participants/{participant}", new { action = 1 });
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(0, repository.Calls);
    }
    private static HttpRequestMessage Request(HttpMethod method, string path, object? body = null, bool headers = true, bool create = false)
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
            [new(JwtRegisteredClaimNames.Sub, Actor.ToString()), new(ClaimTypes.NameIdentifier, Actor.ToString()), new("auth_level", "full"), new("amr", "pwd")],
            now.AddMinutes(-1), now.AddMinutes(10), new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        if (body is not null) request.Content = JsonContent.Create(body);
        if (headers && body is not null)
        {
            request.Headers.Add("Idempotency-Key", "collaboration-command-0001");
            if (create) request.Headers.TryAddWithoutValidation("If-None-Match", "*");
            else if (method != HttpMethod.Post || path.EndsWith("/invitations")) request.Headers.TryAddWithoutValidation("If-Match", ETag);
        }
        return request;
    }
    public void Dispose() { client.Dispose(); application.Dispose(); }
    private sealed class Repository : IProfessionalProfileRepository, IConsortiumRepository
    {
        public int Calls, Writes, ErrorNumber;
        public Guid ActorId, ParticipantId;
        public ProfessionalProfileData? Profile; public ConsortiumCreateData? CreateData;
        public byte[]? Expected, Hash; public ConsortiumParticipantStatus Action;
        private void Read(Guid actor) { Calls++; ActorId = actor; if (ErrorNumber != 0) throw new CollaborationDataException(ErrorNumber, new Exception("private database text")); }
        private Task<CollaborationWriteResult> Write(Guid actor, byte[]? expected, byte[] hash) { Read(actor); Writes++; Expected = expected; Hash = hash; return Task.FromResult(new CollaborationWriteResult(Entity, ETag, false)); }
        public Task<ProfessionalProfile?> GetOwnAsync(Guid userId, CancellationToken token) { Read(userId); return Task.FromResult<ProfessionalProfile?>(null); }
        public Task<CollaborationPage<ProfessionalDirectoryEntry>> SearchAsync(Guid userId, ProfessionalDirectoryFilters filters, CancellationToken token) { Read(userId); return Task.FromResult(new CollaborationPage<ProfessionalDirectoryEntry>([], 0, filters.Page, filters.PageSize)); }
        public Task<CollaborationWriteResult> SaveAsync(Guid userId, ProfessionalProfileData data, byte[]? expected, byte[] keyHash, byte[] requestHash, CancellationToken token) { Profile = data; return Write(userId, expected, requestHash); }
        public Task<CollaborationPage<ConsortiumSummary>> ListAsync(Guid userId, int page, int pageSize, CancellationToken token) { Read(userId); return Task.FromResult(new CollaborationPage<ConsortiumSummary>([], 0, page, pageSize)); }
        public Task<ConsortiumDetails?> GetAsync(Guid userId, Guid consortiumId, CancellationToken token) { Read(userId); return Task.FromResult<ConsortiumDetails?>(null); }
        public Task<CollaborationWriteResult> CreateAsync(Guid userId, ConsortiumCreateData data, byte[] keyHash, byte[] requestHash, CancellationToken token) { CreateData = data; return Write(userId, null, requestHash); }
        public Task<CollaborationWriteResult> UpdateAsync(Guid userId, Guid id, ConsortiumUpdateData data, byte[] expected, byte[] keyHash, byte[] requestHash, CancellationToken token) => Write(userId, expected, requestHash);
        public Task<CollaborationWriteResult> InviteAsync(Guid userId, Guid id, ConsortiumInvitationData data, byte[] expected, byte[] keyHash, byte[] requestHash, CancellationToken token) => Write(userId, expected, requestHash);
        public Task<CollaborationWriteResult> ActAsync(Guid userId, Guid id, Guid participantId, ConsortiumParticipantStatus action, byte[] expected, byte[] keyHash, byte[] requestHash, CancellationToken token) { ParticipantId = participantId; Action = action; return Write(userId, expected, requestHash); }
    }
}
