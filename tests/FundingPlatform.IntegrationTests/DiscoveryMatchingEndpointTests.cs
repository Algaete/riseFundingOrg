using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;
public sealed class DiscoveryMatchingEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Theory]
    [InlineData(false, 1, 2, 0, 401)]
    [InlineData(true, 1, 1, 0, 400)]
    [InlineData(true, 1, 2, 55601, 404)]
    [InlineData(true, 1, 2, 0, 200)]
    public async Task Matching_is_authenticated_validated_and_non_disclosing(bool authenticated, byte source, byte target, int sqlError, int status)
    {
        var repository = new Repository(sqlError);
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IDiscoveryMatchingRepository>(); services.AddSingleton<IDiscoveryMatchingRepository>(repository);
        }));
        using var client = app.CreateClient();
        var actor = Guid.NewGuid();
        if (authenticated)
        {
            var now = DateTime.UtcNow;
            var token = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
                [new(JwtRegisteredClaimNames.Sub, actor.ToString()), new(ClaimTypes.NameIdentifier, actor.ToString()), new("auth_level", "full"), new("amr", "pwd")],
                now.AddMinutes(-1), now.AddMinutes(10), new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }
        using var response = await client.PostAsJsonAsync("/api/v1/matching/discovery", new DiscoveryMatchingRequest((DiscoverySubjectKind)source, Guid.NewGuid(), (DiscoveryTargetKind)target));
        Assert.Equal((HttpStatusCode)status, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.DoesNotContain("private SQL", await response.Content.ReadAsStringAsync());
        Assert.Equal(status is 200 or 404 ? 1 : 0, repository.Calls);
        if (status == 200) Assert.Equal(actor, repository.Actor);
    }
    private sealed class Repository(int error) : IDiscoveryMatchingRepository
    {
        public int Calls; public Guid Actor;
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token)
        {
            Calls++; Actor = userId;
            if (error != 0) throw new DiscoveryMatchingDataException(error, new Exception("private SQL"));
            return Task.FromResult<DiscoveryMatchingContext?>(new("Own source", new([], [], [], null, null, null), [], 0, DateTimeOffset.UtcNow));
        }
    }
}
