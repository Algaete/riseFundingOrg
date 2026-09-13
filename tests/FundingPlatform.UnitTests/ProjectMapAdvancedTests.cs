using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;
using System.Text.Json;

namespace FundingPlatform.UnitTests;

public sealed class ProjectMapAdvancedTests
{
    [Fact]
    public void Sql_parameters_preserve_decimal_precision_and_only_explicit_public_ids()
    {
        var id = Guid.NewGuid();
        var parameters = JsonSerializer.SerializeToElement(SqlProjectMapRepository.CreateParameters(new(
            OrganizationTypeId: 2, MinimumFundingGap: 0, MaximumFundingGap: 900.1234m,
            Currency: "USD", SeekingFunding: true, SeekingPartners: true,
            SeekingProfessionals: true, SeekingConsortium: true, ProjectIds: [id])));
        Assert.Equal(2, parameters.GetProperty("OrganizationTypeId").GetInt16());
        Assert.Equal(0, parameters.GetProperty("MinimumFundingGap").GetDecimal());
        Assert.Equal(900.1234m, parameters.GetProperty("MaximumFundingGap").GetDecimal());
        Assert.Equal("USD", parameters.GetProperty("Currency").GetString());
        foreach (var name in new[] { "SeekingFunding", "SeekingPartners", "SeekingProfessionals", "SeekingConsortium" })
            Assert.True(parameters.GetProperty(name).GetBoolean());
        Assert.Equal(new[] { id }, JsonSerializer.Deserialize<Guid[]>(parameters.GetProperty("ProjectIdsJson").GetString()!));
        var defaults = JsonSerializer.SerializeToElement(SqlProjectMapRepository.CreateParameters(new()));
        Assert.Equal(JsonValueKind.Null, defaults.GetProperty("ProjectIdsJson").ValueKind);
    }

    [Fact]
    public void Result_contract_fixture_parses_and_requires_an_existing_rollback_transaction()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = File.ReadAllText(Path.Combine(root, "database/Fixtures/project_map_contract.sql"));
        using var reader = new StringReader(sql);
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
        Assert.Empty(errors);
        Assert.Contains("IF @@TRANCOUNT = 0 THROW", sql);
        Assert.Contains("@example.invalid", sql);
        Assert.DoesNotContain("COMMIT", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("projects.PublicId = cases.PublicId", sql);
    }

    public static TheoryData<ProjectMapFilters> Invalid => new()
    {
        new(OrganizationTypeId: 0), new(MinimumFundingGap: -1, Currency: "USD"),
        new(MaximumFundingGap: 1000000000000m, Currency: "USD"), new(MinimumFundingGap: 1.00001m, Currency: "USD"),
        new(MinimumFundingGap: 11, MaximumFundingGap: 10, Currency: "USD"),
        new(MinimumFundingGap: 0), new(MaximumFundingGap: 0), new(Currency: "usd"),
        new(Currency: "USDX"), new(Currency: "US1"), new(Currency: ""),
        new(ProjectIds: []), new(ProjectIds: [Guid.Empty]),
        new(ProjectIds: [Guid.Parse("11111111-1111-1111-1111-111111111111"), Guid.Parse("11111111-1111-1111-1111-111111111111")]),
        new(ProjectIds: Enumerable.Range(0, 51).Select(_ => Guid.NewGuid()).ToArray())
    };

    [Theory, MemberData(nameof(Invalid))]
    public void Rejects_invalid_advanced_filters(ProjectMapFilters filters) => Assert.NotEmpty(ProjectMapService.Validate(filters));

    [Fact]
    public void Accepts_zero_same_currency_and_bounded_explicit_projects()
    {
        Assert.Empty(ProjectMapService.Validate(new(OrganizationTypeId: 2, MinimumFundingGap: 0, MaximumFundingGap: 0,
            Currency: "USD", SeekingPartners: true, SeekingProfessionals: true, SeekingConsortium: true,
            ProjectIds: Enumerable.Range(0, 50).Select(_ => Guid.NewGuid()).ToArray())));
        Assert.Empty(ProjectMapService.Validate(new(Currency: "EUR")));
        Assert.Empty(ProjectMapService.Validate(new()));
    }

    [Fact]
    public void Migration_and_smoke_parse_and_preserve_readiness_consent_and_global_counts()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = Assert.Single(SqlScriptCatalog.DiscoverMigrations(root), s => s.Sequence == 49);
        var smoke = Assert.Single(SqlScriptCatalog.DiscoverTests(root), s => s.Sequence == 49);
        foreach (var script in new[] { migration, smoke })
        foreach (var batch in script.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.Empty(errors);
        }
        var sql = File.ReadAllText(Path.Combine(root, "database/Migrations/049_project_map_advanced_filters.sql"));
        Assert.Contains("INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
        Assert.Contains("'$.locationVisibility') = N'2'", sql);
        Assert.Contains("ROUND(coordinates.Latitude, 2)", sql);
        Assert.Contains("projects.FundingGap >= @MinimumFundingGap", sql);
        Assert.Contains("projects.Currency = @Currency", sql);
        Assert.Contains("organizations.OrganizationTypeId = @OrganizationTypeId", sql);
        Assert.Contains("@SelectedProjects WHERE Id = projects.PublicId", sql);
        Assert.Contains("WithoutPublicLocationCount FROM #Visible", sql);
        Assert.DoesNotContain("CREATE OR ALTER FUNCTION", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
        Assert.DoesNotContain("UPDATE dbo.", sql);
        Assert.DoesNotContain("DELETE FROM dbo.", sql);
    }
}
