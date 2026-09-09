using System.Net;
using System.Net.Http.Json;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed class ProjectMapEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Theory]
    [InlineData("page=0")]
    [InlineData("pageSize=201")]
    [InlineData("projectStage=6")]
    [InlineData("projectStatus=7")]
    [InlineData("sustainableDevelopmentGoalId=18")]
    [InlineData("countryId=0")]
    [InlineData("categoryId=-1")]
    public async Task Rejects_invalid_filters_without_accessing_database(string query)
    {
        var repository = new Repository();
        await using var app = Create(repository);
        using var client = app.CreateClient();
        using var result = await client.GetAsync($"/api/v1/marketplace/project-map?{query}");
        Assert.Equal(HttpStatusCode.BadRequest, result.StatusCode);
        Assert.Equal(0, repository.Calls);
        Assert.Contains("validationIssues", await result.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Anonymous_map_rounds_coordinates_and_exposes_only_public_contract()
    {
        var repository = new Repository();
        await using var app = Create(repository);
        using var client = app.CreateClient();
        using var result = await client.GetAsync("/api/v1/marketplace/project-map?q=%20salud%20&projectStage=0&page=2");
        Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        var page = await result.Content.ReadFromJsonAsync<ProjectMapPage>();
        var point = Assert.Single(page!.Items);
        Assert.Equal(-33.46m, point.Latitude);
        Assert.Equal(-70.65m, point.Longitude);
        Assert.Equal(2, page.Page);
        Assert.Equal(4, page.WithoutPublicLocationCount);
        Assert.Equal("salud", repository.Filters!.Query);
        Assert.True(result.Headers.CacheControl!.Public);
        var json = await result.Content.ReadAsStringAsync();
        Assert.DoesNotContain("enrichment", json);
        Assert.DoesNotContain("email", json);
        Assert.DoesNotContain("33.455", json);
    }

    private WebApplicationFactory<Program> Create(Repository repository) => factory.WithWebHostBuilder(builder =>
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IProjectMapRepository>();
            services.AddSingleton<IProjectMapRepository>(repository);
        }));

    private sealed class Repository : IProjectMapRepository
    {
        public int Calls { get; private set; }
        public ProjectMapFilters? Filters { get; private set; }
        public Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken)
        {
            Calls++; Filters = filters;
            return Task.FromResult(new ProjectMapPage([new(Guid.NewGuid(), "public-project", "Project", null,
                "Organization", -33.455m, -70.654321m, 2, 0, 100, "USD")], 101, 4, filters.Page, filters.PageSize));
        }
    }
}
