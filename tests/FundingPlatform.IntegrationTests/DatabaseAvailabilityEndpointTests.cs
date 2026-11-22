using System.Net;
using System.Text.Json;
using FundingPlatform.Api.Middleware;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.TestFixtures;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed class DatabaseAvailabilityEndpointTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Exhausted_connection_returns_sanitized_uncacheable_503_and_recovers_on_a_new_request(bool wrapped)
    {
        var sql = SqlExceptionFixture.Create(40613);
        var repository = new UnavailableRepository
        {
            Error = wrapped ? new InvalidOperationException("private wrapper", new AggregateException(sql, sql)) : sql
        };
        await using var root = new ApiFactory();
        await using var app = root.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IFundingOpportunityRepository>();
            services.AddSingleton<IFundingOpportunityRepository>(repository);
        }));
        using var client = app.CreateClient();
        client.DefaultRequestHeaders.Add("Origin", "http://localhost:5173");
        using var response = await client.GetAsync("/api/v1/funding-opportunities?pageSize=1");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(TimeSpan.FromSeconds(10), response.Headers.RetryAfter?.Delta);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.Contains("Retry-After", string.Join(",", response.Headers.GetValues("Access-Control-Expose-Headers")));
        var text = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("private", text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("40613", text);
        using var problem = JsonDocument.Parse(text);
        Assert.Equal(DatabaseAvailabilityExceptionHandler.ProblemType, problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(503, problem.RootElement.GetProperty("status").GetInt32());
        Assert.True(problem.RootElement.TryGetProperty("correlationId", out _));
        Assert.Equal(1, repository.ReadCalls); // HTTP middleware never replays a repository operation.

        repository.Error = null;
        using var recovered = await client.GetAsync("/api/v1/funding-opportunities?pageSize=1");
        Assert.Equal(HttpStatusCode.OK, recovered.StatusCode);
        Assert.Equal(2, repository.ReadCalls);
        Assert.Null(recovered.Headers.RetryAfter);
    }

    [Theory]
    [InlineData(18456)]
    [InlineData(51601)]
    public async Task Permanent_database_failures_are_not_mislabelled_as_resume_delays(int number)
    {
        var repository = new UnavailableRepository { Error = SqlExceptionFixture.Create(number) };
        await using var root = new ApiFactory();
        await using var app = root.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IFundingOpportunityRepository>();
            services.AddSingleton<IFundingOpportunityRepository>(repository);
        }));
        using var client = app.CreateClient();
        using var response = await client.GetAsync("/api/v1/funding-opportunities");
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Null(response.Headers.RetryAfter);
        Assert.Equal(1, repository.ReadCalls);
    }

    private sealed class UnavailableRepository : IFundingOpportunityRepository
    {
        public Exception? Error { get; set; }
        public int ReadCalls { get; private set; }
        public Task<FundingOpportunityPage> SearchPublishedAsync(string? query, int pageNumber,
            int pageSize, CancellationToken cancellationToken, bool includeReviewedTranslations = false)
        {
            ReadCalls++;
            return Error is { } error ? Task.FromException<FundingOpportunityPage>(error) :
                Task.FromResult(new FundingOpportunityPage([], 0, pageNumber, pageSize));
        }
        public Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(string slug,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
            int expectedFundingSourceId, string expectedProviderCode, ExternalFundingOpportunity opportunity,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }
}
