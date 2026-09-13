using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class GapRecommendationEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Theory]
    [InlineData("anonymous", false, 0, 401)]
    [InlineData("partial", false, 0, 403)]
    [InlineData("full", true, 0, 400)]
    [InlineData("full", false, 55501, 404)]
    [InlineData("full", false, 55502, 404)]
    [InlineData("full", false, 55601, 404)]
    [InlineData("full", false, 55901, 404)]
    [InlineData("full", false, -1, 404)]
    [InlineData("full", false, 0, 200)]
    public async Task Endpoint_is_full_session_only_validated_non_disclosing_and_no_store(string level, bool invalid, int error, int status)
    {
        var repository = new Repository(error);
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IGapRecommendationRepository>(); services.AddSingleton<IGapRecommendationRepository>(repository);
            services.RemoveAll<IDiscoveryMatchingRepository>(); services.AddSingleton<IDiscoveryMatchingRepository>(repository);
        }));
        using var client = app.CreateClient();
        var actor = Guid.NewGuid();
        if (level != "anonymous")
        {
            var now = DateTime.UtcNow;
            var jwt = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
                [new(JwtRegisteredClaimNames.Sub, actor.ToString()), new(ClaimTypes.NameIdentifier, actor.ToString()), new("auth_level", level), new("amr", "pwd")],
                now.AddMinutes(-1), now.AddMinutes(10), new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(jwt));
        }
        var request = new GapRecommendationRequest(invalid ? Guid.Empty : Guid.NewGuid(), Guid.NewGuid());
        using var response = await client.PostAsJsonAsync("/api/v1/matching/gap-recommendations", request);
        Assert.Equal((HttpStatusCode)status, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.DoesNotContain("private SQL", await response.Content.ReadAsStringAsync());
        Assert.Equal(status is 200 or 404 ? 1 : 0, repository.ContextCalls);
        Assert.Equal(status == 200 ? 1 : 0, repository.DiscoveryCalls);
        if (status == 200)
        {
            Assert.Equal(actor, repository.Actor); Assert.Equal(request, repository.Request);
            var payload = await response.Content.ReadFromJsonAsync<GapRecommendationResult>();
            var item = Assert.Single(payload!.Items);
            Assert.Equal("international-partner", item.Code); Assert.Single(item.Candidates);
            Assert.Equal(1, payload.ContentVersion);
            Assert.Equal("specific", payload.GeographyState); Assert.Equal(["EU"], payload.PartnerGeography!.RegionCodes);
        }
    }

    private sealed class Repository(int error) : IGapRecommendationRepository, IDiscoveryMatchingRepository
    {
        public int ContextCalls, DiscoveryCalls; public Guid Actor; public GapRecommendationRequest? Request;
        public Task<GapRecommendationContext?> ReadAsync(Guid userId, GapRecommendationRequest request, CancellationToken token)
        {
            ContextCalls++; Actor = userId; Request = request;
            if (error > 0) throw new DiscoveryMatchingDataException(error, new Exception("private SQL"));
            return Task.FromResult<GapRecommendationContext?>(error == -1 ? null : new("Own project", "Public opportunity", 1, 152,
                1, false, true, "https://example.invalid/terms", null, null, false, DateTimeOffset.UtcNow,
                new(PartnerGeographyScope.Specific, [], ["EU"], PartnerGeographyCatalog.Version), [250]));
        }
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token)
        {
            DiscoveryCalls++; Assert.Equal(Actor, userId); Assert.Equal(Request!.ProjectId, request.SourceId);
            return Task.FromResult<DiscoveryMatchingContext?>(new("Own project", new([152], [1], [], null, null, null),
                [new(Guid.NewGuid(), "Opted-in partner", null, "/marketplace/organizations/example", new([250], [1], [], null, null, null))], 1, DateTimeOffset.UtcNow));
        }
    }
}
