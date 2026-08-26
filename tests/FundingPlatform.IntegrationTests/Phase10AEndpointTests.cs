using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Alerts;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class Phase10AEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid SearchId =
        Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

    private readonly FakeAlertRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public Phase10AEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ISavedSearchAlertRepository>();
                services.AddSingleton<ISavedSearchAlertRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/saved-searches")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/saved-searches")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/notification-logs")]
    public async Task Private_alert_routes_require_full_session_and_are_no_store(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.TotalCalls);
    }

    [Fact]
    public async Task Saved_search_create_requires_idempotency_and_returns_private_detail()
    {
        using var missing = AuthenticatedRequest(
            HttpMethod.Post, OrganizationPath("saved-searches"), SearchBody());
        using var missingResponse = await client.SendAsync(missing);

        Assert.Equal(HttpStatusCode.BadRequest, missingResponse.StatusCode);
        Assert.Equal(0, repository.CreateCalls);

        using var request = AuthenticatedRequest(
            HttpMethod.Post, OrganizationPath("saved-searches"), SearchBody());
        request.Headers.Add("Idempotency-Key", "saved-search-0001");
        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal("\"0102030405060708\"", response.Headers.ETag?.Tag);
        Assert.Equal(SearchId, payload.RootElement.GetProperty("id").GetGuid());
        Assert.Equal("Fondos de agua", payload.RootElement.GetProperty("name").GetString());
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal(UserId, repository.UserId);
        Assert.Equal(OrganizationId, repository.OrganizationId);
    }

    [Fact]
    public async Task Update_requires_strong_if_match_before_repository()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Patch,
            OrganizationPath($"saved-searches/{SearchId:D}"),
            SearchBody());

        using var response = await client.SendAsync(request);

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(0, repository.UpdateCalls);
    }

    [Fact]
    public async Task Email_activation_is_explicitly_unavailable_while_kill_switch_is_off()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Put,
            OrganizationPath($"saved-searches/{SearchId:D}/alert"),
            new { preferredHourLocal = 8, timeZoneId = "America/Santiago" });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/alerts-disabled",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(0, repository.PutAlertCalls);
    }

    [Fact]
    public async Task Public_unsubscribe_is_non_enumerating_and_always_no_content()
    {
        using var first = await client.PostAsJsonAsync(
            "/api/v1/alerts/unsubscribe", new { token = "invalid" });
        using var second = await client.PostAsJsonAsync(
            "/api/v1/alerts/unsubscribe", new { token = "another-invalid-token" });

        Assert.Equal(HttpStatusCode.NoContent, first.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, second.StatusCode);
        Assert.Contains("no-store", first.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.UnsubscribeCalls);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static string OrganizationPath(string suffix) =>
        $"/api/v1/organizations/{OrganizationId:D}/{suffix}";

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        object? body = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        if (body is not null) request.Content = JsonContent.Create(body);
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
                new Claim("auth_level", "full"),
                new Claim("amr", "pwd"),
                new Claim("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
            ],
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey), SecurityAlgorithms.HmacSha512)));
    }

    private static object SearchBody() => new
    {
        name = "Fondos de agua",
        query = "agua",
        sponsor = (string?)null,
        minimumAmount = (decimal?)null,
        maximumAmount = (decimal?)null,
        currency = (string?)null,
        closingFrom = (string?)null,
        closingTo = (string?)null,
        onlyOpen = true,
        sort = "relevance",
        countryIds = new short[] { 152 },
        regionIds = Array.Empty<int>(),
        categoryIds = Array.Empty<int>(),
        tagIds = Array.Empty<long>(),
        beneficiaryTypeIds = Array.Empty<int>(),
        projectTypeIds = Array.Empty<int>(),
        fundingTypeIds = Array.Empty<short>(),
        organizationTypeIds = Array.Empty<short>(),
        funderIds = Array.Empty<Guid>()
    };

    private sealed class FakeAlertRepository : ISavedSearchAlertRepository
    {
        public int TotalCalls { get; private set; }
        public int CreateCalls { get; private set; }
        public int UpdateCalls { get; private set; }
        public int PutAlertCalls { get; private set; }
        public int UnsubscribeCalls { get; private set; }
        public Guid UserId { get; private set; }
        public Guid OrganizationId { get; private set; }

        public Task<SavedSearchPage?> ListSavedSearchesAsync(
            Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult<SavedSearchPage?>(new([], 0, pageNumber, pageSize));
        }

        public Task<SavedSearchDetails?> GetSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult<SavedSearchDetails?>(Details(Filters()));
        }

        public Task<SavedSearchMutation> CreateSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, string name,
            FundingOpportunitySearchFilters filters, byte[] idempotencyKeyHash,
            byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            TotalCalls++;
            CreateCalls++;
            UserId = userPublicId;
            OrganizationId = organizationPublicId;
            return Task.FromResult(new SavedSearchMutation(
                SavedSearchMutationOutcome.Created, Details(filters)));
        }

        public Task<SavedSearchMutation> UpdateSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            string name, FundingOpportunitySearchFilters filters, byte[] expectedRowVersion,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            TotalCalls++;
            UpdateCalls++;
            return Task.FromResult(new SavedSearchMutation(
                SavedSearchMutationOutcome.Updated, Details(filters)));
        }

        public Task<SavedSearchMutation> DeleteSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            byte[] expectedRowVersion, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult(new SavedSearchMutation(SavedSearchMutationOutcome.Deleted));

        public Task<AlertSubscriptionMutation> PutAlertAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            byte preferredHourLocal, string timeZoneId, DateTimeOffset nextRunAtUtc,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            TotalCalls++;
            PutAlertCalls++;
            return Task.FromResult(new AlertSubscriptionMutation(
                AlertSubscriptionMutationOutcome.Created));
        }

        public Task<AlertSubscriptionMutation> DeleteAlertAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult(new AlertSubscriptionMutation(AlertSubscriptionMutationOutcome.Deleted));

        public Task<AlertSubscriptionMutation> UnsubscribeAsync(
            Guid alertSubscriptionPublicId, Guid unsubscribeNonce, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            UnsubscribeCalls++;
            return Task.FromResult(new AlertSubscriptionMutation(
                AlertSubscriptionMutationOutcome.Deleted));
        }

        public Task<NotificationLogPage?> ListNotificationLogsAsync(
            Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken)
        {
            TotalCalls++;
            return Task.FromResult<NotificationLogPage?>(new([], 0, pageNumber, pageSize));
        }

        public Task<IReadOnlyList<AlertScheduleLease>> ClaimSchedulesAsync(
            Guid leaseOwner, int batchSize, int leaseSeconds, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<AlertScheduleLease>>([]);

        public Task<AlertScheduleMaterialization> MaterializeScheduleAsync(
            Guid alertSubscriptionPublicId, Guid leaseId, DateTimeOffset scheduledForUtc,
            DateTimeOffset nextRunAtUtc, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<AlertDeliveryLease?> ClaimDeliveryAsync(
            Guid leaseOwner, int leaseSeconds, int maximumAttempts, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) => Task.FromResult<AlertDeliveryLease?>(null);

        public Task<bool> RenewDeliveryLeaseAsync(
            Guid notificationLogPublicId, Guid leaseId, int leaseSeconds,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> CompleteDeliveryAsync(
            Guid notificationLogPublicId, Guid leaseId, string providerMessageId,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> FailDeliveryAsync(
            Guid notificationLogPublicId, Guid leaseId, bool deliveryUnknown,
            string errorCode, int retryDelaySeconds, int maximumAttempts,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) => Task.FromResult(false);

        private static SavedSearchDetails Details(FundingOpportunitySearchFilters filters) => new(
            SearchId,
            "Fondos de agua",
            filters,
            null,
            new DateTimeOffset(2026, 8, 25, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 25, 12, 0, 0, TimeSpan.Zero),
            "\"0102030405060708\"");

        private static FundingOpportunitySearchFilters Filters() => new(
            "agua", null, null, null, null, null, null, true,
            FundingOpportunitySearchSort.Relevance, 1, 20,
            [152], [], [], [], [], [], [], [], []);
    }
}
