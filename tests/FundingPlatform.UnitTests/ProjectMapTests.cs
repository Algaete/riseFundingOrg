using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectMapTests
{
    public static TheoryData<ProjectMapFilters> InvalidFilters => new()
    {
        new(Query: new string('x', 201)), new(CountryId: 0), new(CategoryId: -1),
        new(ProjectStage: 6), new(ProjectStatus: 7), new(SustainableDevelopmentGoalId: 0),
        new(SustainableDevelopmentGoalId: 18), new(Page: 0), new(Page: 10001),
        new(PageSize: 0), new(PageSize: 201)
    };

    [Theory, MemberData(nameof(InvalidFilters))]
    public void Invalid_filters_are_rejected(ProjectMapFilters filters) => Assert.NotEmpty(ProjectMapService.Validate(filters));

    [Fact]
    public async Task Normalizes_query_and_preserves_zero_values_and_cancellation()
    {
        var repository = new Repository();
        var service = new ProjectMapService(repository);
        using var cancellation = new CancellationTokenSource();
        await service.SearchAsync(new(Query: "  salud  ", ProjectStage: 0, ProjectStatus: 0), cancellation.Token);
        Assert.Equal("salud", repository.Filters!.Query);
        Assert.Equal((byte)0, repository.Filters.ProjectStage);
        Assert.Equal((byte)0, repository.Filters.ProjectStatus);
        Assert.Equal(cancellation.Token, repository.CancellationToken);
        await Assert.ThrowsAsync<ArgumentException>(() => service.SearchAsync(new(Page: 0), default));
        Assert.Equal(1, repository.Calls);
    }

    [Fact]
    public void Migration_and_readonly_smoke_parse_and_keep_publication_and_privacy_guards()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 41);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 41);
        foreach (var script in new[] { migration, smoke })
        foreach (var batch in script.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => e.Message)));
        }
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", migration.FileName));
        Assert.Contains("INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
        Assert.Contains("'$.locationVisibility') = N'2'", sql);
        Assert.Contains("ROUND(coordinates.Latitude, 2)", sql);
        Assert.Contains("ROUND(coordinates.Longitude, 2)", sql);
        Assert.Contains("coordinates.Latitude BETWEEN -90 AND 90 AND coordinates.Longitude BETWEEN -180 AND 180", sql);
        Assert.Contains("WHERE Latitude IS NOT NULL AND Longitude IS NOT NULL", sql);
        Assert.DoesNotContain("CREATE OR ALTER FUNCTION", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
    }

    private sealed class Repository : IProjectMapRepository
    {
        public ProjectMapFilters? Filters { get; private set; }
        public CancellationToken CancellationToken { get; private set; }
        public int Calls { get; private set; }
        public Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken)
        {
            Calls++; Filters = filters; CancellationToken = cancellationToken;
            return Task.FromResult(new ProjectMapPage([], 0, 0, filters.Page, filters.PageSize));
        }
    }
}
