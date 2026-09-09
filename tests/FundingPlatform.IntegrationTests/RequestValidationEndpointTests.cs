using System.Net;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed class RequestValidationEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Theory]
    [InlineData("/api/v1/funding-opportunities?pageNumber=PRIVATE-SUBMITTED-VALUE", "request", "request-invalid-format")]
    [InlineData("/api/v1/funding-opportunities?pageSize=0", "pagination", "api-validation-093")]
    [InlineData("/api/v1/funding-opportunities?pageNumber=-1", "pagination", "api-validation-093")]
    public async Task Invalid_public_queries_return_stable_codes_before_any_repository_access(
        string path, string field, string code)
    {
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IFundingOpportunityRepository>();
            services.AddSingleton<IFundingOpportunityRepository, NoAccessRepository>();
        }));
        using var client = app.CreateClient();
        using var response = await client.GetAsync(path);
        await AssertIssue(response, HttpStatusCode.BadRequest, field, code);
    }

    [Theory]
    [InlineData("{", "application/json", HttpStatusCode.BadRequest)]
    [InlineData("{\"email\":{\"PRIVATE-SUBMITTED-VALUE\":true}}", "application/json", HttpStatusCode.BadRequest)]
    [InlineData("PRIVATE-SUBMITTED-VALUE", "text/plain", HttpStatusCode.UnsupportedMediaType)]
    public async Task Malformed_registration_body_is_safe_before_identity_or_email_work(
        string body, string contentType, HttpStatusCode status)
    {
        using var client = factory.CreateClient();
        using var content = new StringContent(body, Encoding.UTF8, contentType);
        using var response = await client.PostAsync("/api/v1/auth/register", content);
        await AssertIssue(response, status, "request", "request-invalid-format");
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    private static async Task AssertIssue(HttpResponseMessage response, HttpStatusCode status, string field, string code)
    {
        var body = await response.Content.ReadAsStringAsync();
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var problem = JsonDocument.Parse(body);
        Assert.Equal(code, problem.RootElement.GetProperty("validationIssues").GetProperty(field)[0].GetProperty("code").GetString());
        Assert.NotEmpty(problem.RootElement.GetProperty("errors").GetProperty(field).EnumerateArray());
        Assert.DoesNotContain("PRIVATE-SUBMITTED-VALUE", body);
        Assert.DoesNotContain("JsonException", body);
        Assert.DoesNotContain("System.", body);
    }

    private sealed class NoAccessRepository : IFundingOpportunityRepository
    {
        public Task<FundingOpportunityPage> SearchPublishedAsync(string? query, int pageNumber, int pageSize, CancellationToken cancellationToken)
            => throw new InvalidOperationException("Validation must not call persistence.");
        public Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(string slug, CancellationToken cancellationToken)
            => throw new InvalidOperationException("Validation must not call persistence.");
        public Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(int expectedFundingSourceId, string expectedProviderCode, ExternalFundingOpportunity opportunity, CancellationToken cancellationToken)
            => throw new InvalidOperationException("Validation must not write.");
    }
}
